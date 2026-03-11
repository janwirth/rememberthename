//// Unified adapter traversal core for rememberthename.
////
//// Scope:
//// - Backend-only recursive resolution for collection/profile roots.
//// - Deterministic traversal order, deduplication, and cycle safety.
//// - Canonical normalized output nodes (`UnifiedItem`, `UnifiedCollection`).
////
//// Contract:
//// - Adapters expose service-specific opaque profile entry types and constructor
////   functions, then delegate recursion here through `resolve_profile_url`.
//// - Adapters provide an `expand` function:
////   `AdapterNode -> ExpandResult`.
////
//// Recursive queue model (tail-recursive):
//// - State: `queue`, `visited`, `item_seen`, `list_seen`, accumulators.
//// - Loop:
////   1) pop queue head
////   2) skip if visited
////   3) expand node if depth allows
////   4) merge emitted items/lists with deterministic key dedupe
////   5) append emitted `next_nodes` with incremented level
////   6) continue until queue empty
////
//// Depth semantics:
//// - `Depth1`, `Depth2`, `Depth3`, `Depth10`, `Depth20`, `All`
//// - depth is recursion hop count from profile root level 0.
////
//// Output guarantees:
//// - Stable item/list identity key: `service:source_type:source_id`.
//// - No duplicate canonical nodes in final output.
//// - Unresolved traversal nodes are surfaced for diagnostics/tests.
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import default_queue
import source_id_normalizer

// Spec integration:
// - Implements SPEC.md section 7.1 recursive queue model.
// - Shared canonical model and traversal contracts from adapters.spec.md.
// - Entry node is a profile URL root; adapters provide service-specific constructors.
pub type DepthMode {
  Depth1
  Depth2
  Depth3
  Depth10
  Depth20
  All
}

pub type AdapterNode {
  ProfileEntry(String)
  CategoryNode(String)
  ListNode(String)
  PageNode(String)
}

pub type UnifiedItem {
  UnifiedItem(
    id: String,
    title: String,
    artist: String,
    service: String,
    source_type: String,
    source_id: String,
  )
}

pub type UnifiedCollection {
  UnifiedCollection(
    id: String,
    title: String,
    track_ids: List(String),
    list_ids: List(String),
    service: String,
    source_type: String,
    source_id: String,
  )
}

pub fn track_item(
  service: String,
  raw_source_id: String,
  title: String,
  artist: String,
) -> Result(UnifiedItem, Nil) {
  let source_id = source_id_normalizer.normalize(service, raw_source_id)
  case source_id == "" {
    True -> Error(Nil)
    False ->
      Ok(
        UnifiedItem(
          id: service <> ":item:" <> source_id,
          title: title,
          artist: artist,
          service: service,
          source_type: "item",
          source_id: source_id,
        ),
      )
  }
}

pub type ExpandResult {
  ExpandResult(
    items: List(UnifiedItem),
    lists: List(UnifiedCollection),
    next_nodes: List(AdapterNode),
    unresolved: List(AdapterNode),
  )
}

pub type ResolveResult {
  ResolveResult(
    items: List(UnifiedItem),
    lists: List(UnifiedCollection),
    unresolved: List(AdapterNode),
  )
}

pub fn resolve_profile_url(
  profile_url: String,
  depth: DepthMode,
  expand: fn(AdapterNode) -> ExpandResult,
) -> ResolveResult {
  resolve_profile_url_with_debug(profile_url, depth, expand, fn(_) { Nil })
}

pub fn resolve_profile_url_with_debug(
  profile_url: String,
  depth: DepthMode,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  case depth {
    All -> resolve_profile_url_with_default_queue(profile_url, expand, on_debug)
    _ ->
      // Start traversal exactly once from the profile entry root.
      loop(
        [#(ProfileEntry(profile_url), 0)],
        set.new(),
        set.new(),
        set.new(),
        [],
        [],
        [],
        depth,
        expand,
        on_debug,
      )
  }
}

type QueueTask {
  QueueTask(node: AdapterNode, level: Int)
}

type QueueState {
  QueueState(
    visited: set.Set(String),
    item_seen: set.Set(String),
    list_seen: set.Set(String),
    items: List(UnifiedItem),
    lists: List(UnifiedCollection),
    unresolved: List(AdapterNode),
  )
}

fn resolve_profile_url_with_default_queue(
  profile_url: String,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  let policy = default_queue.QueuePolicy(max_concurrency: 3, requests_per_second: 3)
  let initial_state =
    QueueState(
      visited: set.new(),
      item_seen: set.new(),
      list_seen: set.new(),
      items: [],
      lists: [],
      unresolved: [],
    )
  let queue_run =
    default_queue.run_default_queue_with_state(
      [QueueTask(node: ProfileEntry(profile_url), level: 0)],
      policy,
      initial_state,
      fn(task, state) { queue_execute_task(task, state, expand, on_debug) },
    )
  let #(_, QueueState(_, _, _, items, lists, unresolved)) = queue_run
  ResolveResult(items, lists, unresolved)
}

fn queue_execute_task(
  task: QueueTask,
  state: QueueState,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> #(QueueState, default_queue.TaskPlan(QueueTask, Nil, Nil)) {
  let QueueTask(node, level) = task
  let QueueState(visited, item_seen, list_seen, items, lists, unresolved) = state
  let key = node_key(node)
  case set.contains(visited, key) || !can_expand(level, All) {
    True ->
      #(
        state,
        default_queue.TaskPlan(
          duration_ms: 0,
          outcome: default_queue.TaskOutcome(recurse: [], results: [], errors: []),
        ),
      )
    False -> {
      let visited = set.insert(visited, key)
      emit_debug(All, on_debug, "[fetch] node=" <> node_key(node) <> " level=" <> int.to_string(level))
      let ExpandResult(next_items, next_lists, next_nodes, next_unresolved) = expand(node)
      emit_debug(
        All,
        on_debug,
        "[fetched] node="
        <> node_key(node)
        <> " items="
        <> int.to_string(list.length(next_items))
        <> " lists="
        <> int.to_string(list.length(next_lists))
        <> " next="
        <> int.to_string(list.length(next_nodes)),
      )
      let #(items, item_seen) = merge_items(items, item_seen, next_items)
      let #(lists, list_seen) = merge_lists(lists, list_seen, next_lists)
      let unresolved = list.append(unresolved, next_unresolved)
      let recurse = list.map(next_nodes, fn(next) { QueueTask(next, level + 1) })
      #(
        QueueState(
          visited: visited,
          item_seen: item_seen,
          list_seen: list_seen,
          items: items,
          lists: lists,
          unresolved: unresolved,
        ),
        default_queue.TaskPlan(
          duration_ms: 0,
          outcome: default_queue.TaskOutcome(recurse: recurse, results: [], errors: []),
        ),
      )
    }
  }
}

fn loop(
  queue: List(#(AdapterNode, Int)),
  visited: set.Set(String),
  item_seen: set.Set(String),
  list_seen: set.Set(String),
  items: List(UnifiedItem),
  lists: List(UnifiedCollection),
  unresolved: List(AdapterNode),
  depth: DepthMode,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  // Tail-recursive resolver with:
  // - queue for deterministic traversal order
  // - visited set for cycle safety
  // - item/list seen sets for deduplication
  case queue == [] {
    True -> ResolveResult(items, lists, unresolved)
    False -> {
      let current = result.unwrap(list.first(queue), #(PageNode(""), 0))
      let rest = result.unwrap(list.rest(queue), [])
      let #(node, level) = current
      let key = node_key(node)
      case set.contains(visited, key) {
        True -> {
          loop(
            rest,
            visited,
            item_seen,
            list_seen,
            items,
            lists,
            unresolved,
            depth,
            expand,
            on_debug,
          )
        }
        False -> {
          let visited = set.insert(visited, key)
          case can_expand(level, depth) {
            False -> {
              loop(
                rest,
                visited,
                item_seen,
                list_seen,
                items,
                lists,
                unresolved,
                depth,
                expand,
                on_debug,
              )
            }
            True -> {
              emit_debug(depth, on_debug, "[fetch] node=" <> node_key(node) <> " level=" <> int.to_string(level))
              let ExpandResult(next_items, next_lists, next_nodes, next_unresolved) = expand(node)
              emit_debug(
                depth,
                on_debug,
                "[fetched] node="
                <> node_key(node)
                <> " items="
                <> int.to_string(list.length(next_items))
                <> " lists="
                <> int.to_string(list.length(next_lists))
                <> " next="
                <> int.to_string(list.length(next_nodes)),
              )
              let #(items, item_seen) = merge_items(items, item_seen, next_items)
              let #(lists, list_seen) = merge_lists(lists, list_seen, next_lists)
              let queue = list.append(rest, with_level(next_nodes, level + 1))
              let unresolved = list.append(unresolved, next_unresolved)
              loop(
                queue,
                visited,
                item_seen,
                list_seen,
                items,
                lists,
                unresolved,
                depth,
                expand,
                on_debug,
              )
            }
          }
        }
      }
    }
  }
}

fn emit_debug(depth: DepthMode, on_debug: fn(String) -> Nil, line: String) {
  case depth {
    All -> on_debug(line)
    _ -> Nil
  }
}

fn can_expand(level: Int, depth: DepthMode) -> Bool {
  // Depth semantics are recursion-hop limits.
  case depth {
    Depth1 -> level < 1
    Depth2 -> level < 2
    Depth3 -> level < 3
    Depth10 -> level < 10
    Depth20 -> level < 20
    All -> True
  }
}

fn with_level(nodes: List(AdapterNode), level: Int) -> List(#(AdapterNode, Int)) {
  list.map(nodes, fn(node) { #(node, level) })
}

fn merge_items(
  items: List(UnifiedItem),
  seen: set.Set(String),
  incoming: List(UnifiedItem),
) -> #(List(UnifiedItem), set.Set(String)) {
  list.fold(
    incoming,
    #(items, seen),
    fn(acc, item) {
      let #(items, seen) = acc
      let key = item_key(item)
      case set.contains(seen, key) {
        True -> #(items, seen)
        False -> #(list.append(items, [item]), set.insert(seen, key))
      }
    },
  )
}

fn merge_lists(
  lists: List(UnifiedCollection),
  seen: set.Set(String),
  incoming: List(UnifiedCollection),
) -> #(List(UnifiedCollection), set.Set(String)) {
  list.fold(
    incoming,
    #(lists, seen),
    fn(acc, collection) {
      let #(lists, seen) = acc
      let key = collection_key(collection)
      case set.contains(seen, key) {
        True -> #(lists, seen)
        False -> #(list.append(lists, [collection]), set.insert(seen, key))
      }
    },
  )
}

fn item_key(item: UnifiedItem) -> String {
  let UnifiedItem(_, _, _, service, source_type, source_id) = item
  service <> ":" <> source_type <> ":" <> source_id
}

fn collection_key(collection: UnifiedCollection) -> String {
  let UnifiedCollection(_, _, _, _, service, source_type, source_id) = collection
  service <> ":" <> source_type <> ":" <> source_id
}

fn node_key(node: AdapterNode) -> String {
  case node {
    ProfileEntry(profile_url) -> "profile:" <> profile_url
    CategoryNode(id) -> "category:" <> id
    ListNode(id) -> "list:" <> id
    PageNode(id) -> "page:" <> id
  }
}
