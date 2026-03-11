//// Unified adapter traversal core for rememberthename.
////
//// Scope:
//// - Backend-only recursive resolution for service profile roots.
//// - Deterministic traversal order, deduplication, and cycle safety.
//// - Canonical normalized output nodes (`UnifiedItem`, `UnifiedCollection`).
//// - No media/artwork fetching and no search behavior.
////
//// Adapter contract:
//// - Adapters expose service-specific opaque profile types + constructors.
//// - Root traversal starts at `ProfileEntry(profile_url)`.
//// - Adapter `expand` keeps this shape:
////   `AdapterNode -> ExpandResult(items, lists, next_nodes, unresolved)`.
//// - Emitted `next_nodes` must keep deterministic order.
//// - Partially resolved lists stay internal; exported lists are complete.
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
////
//// Update stream expectations are handled by callers:
//// - started
//// - progress
//// - completed
import gleam/int
import gleam/list
import gleam/result
import gleam/erlang/process
import gleam/set
import source_id_normalizer

// Shared traversal/runtime implementation used by all live adapters.
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

type WorkerMsg {
  WorkerDone(node: AdapterNode, level: Int, result: ExpandResult)
}

const queue_max_concurrency = 3
const queue_requests_per_second = 3
const queue_interval_ms = 333

fn resolve_profile_url_with_default_queue(
  profile_url: String,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  let subject = process.new_subject()
  emit_debug(
    All,
    on_debug,
    "[queue] enabled mode=concurrent req_per_sec="
    <> int.to_string(queue_requests_per_second)
    <> " concurrency="
    <> int.to_string(queue_max_concurrency),
  )
  let #(queue, running, visited, item_seen, list_seen, items, lists, unresolved, starts, max_active) =
    start_workers(
      [#(ProfileEntry(profile_url), 0)],
      0,
      set.new(),
      set.new(),
      set.new(),
      [],
      [],
      [],
      0,
      0,
      subject,
      expand,
      on_debug,
    )
  let ResolveResult(items, lists, unresolved) =
    concurrent_loop(
      queue,
      running,
      visited,
      item_seen,
      list_seen,
      items,
      lists,
      unresolved,
      starts,
      max_active,
      subject,
      expand,
      on_debug,
    )
  emit_debug(
    All,
    on_debug,
    "[queue] complete starts="
    <> int.to_string(starts)
    <> " max_active="
    <> int.to_string(max_active),
  )
  ResolveResult(items, lists, unresolved)
}

fn start_workers(
  queue: List(#(AdapterNode, Int)),
  running: Int,
  visited: set.Set(String),
  item_seen: set.Set(String),
  list_seen: set.Set(String),
  items: List(UnifiedItem),
  lists: List(UnifiedCollection),
  unresolved: List(AdapterNode),
  starts: Int,
  max_active: Int,
  subject: process.Subject(WorkerMsg),
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> #(
  List(#(AdapterNode, Int)),
  Int,
  set.Set(String),
  set.Set(String),
  set.Set(String),
  List(UnifiedItem),
  List(UnifiedCollection),
  List(AdapterNode),
  Int,
  Int,
) {
  case running >= queue_max_concurrency || queue == [] {
    True ->
      #(
        queue,
        running,
        visited,
        item_seen,
        list_seen,
        items,
        lists,
        unresolved,
        starts,
        max_active,
      )
    False -> {
      let current = result.unwrap(list.first(queue), #(PageNode(""), 0))
      let rest = result.unwrap(list.rest(queue), [])
      let #(node, level) = current
      let key = node_key(node)
      case set.contains(visited, key) || !can_expand(level, All) {
        True ->
          start_workers(
            rest,
            running,
            visited,
            item_seen,
            list_seen,
            items,
            lists,
            unresolved,
            starts,
            max_active,
            subject,
            expand,
            on_debug,
          )
        False -> {
          let visited = set.insert(visited, key)
          emit_debug(
            All,
            on_debug,
            "[queue] start node=" <> key <> " level=" <> int.to_string(level),
          )
          emit_debug(
            All,
            on_debug,
            "[fetch] start node="
            <> node_key(node)
            <> " level="
            <> int.to_string(level),
          )
          let _ =
            process.spawn_unlinked(fn() {
              let payload = expand(node)
              process.send(subject, WorkerDone(node: node, level: level, result: payload))
            })
          process.sleep(queue_interval_ms)
          let next_running = running + 1
          start_workers(
            rest,
            next_running,
            visited,
            item_seen,
            list_seen,
            items,
            lists,
            unresolved,
            starts + 1,
            max_int(max_active, next_running),
            subject,
            expand,
            on_debug,
          )
        }
      }
    }
  }
}

fn concurrent_loop(
  queue: List(#(AdapterNode, Int)),
  running: Int,
  visited: set.Set(String),
  item_seen: set.Set(String),
  list_seen: set.Set(String),
  items: List(UnifiedItem),
  lists: List(UnifiedCollection),
  unresolved: List(AdapterNode),
  starts: Int,
  max_active: Int,
  subject: process.Subject(WorkerMsg),
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  case queue == [] && running == 0 {
    True -> ResolveResult(items, lists, unresolved)
    False -> {
      let #(queue, running, visited, item_seen, list_seen, items, lists, unresolved, starts, max_active) =
        start_workers(
          queue,
          running,
          visited,
          item_seen,
          list_seen,
          items,
          lists,
          unresolved,
          starts,
          max_active,
          subject,
          expand,
          on_debug,
        )
      case running == 0 {
        True ->
          ResolveResult(items, lists, unresolved)
        False -> {
          let message = process.receive_forever(subject)
          let WorkerDone(node, level, payload) = message
          let ExpandResult(next_items, next_lists, next_nodes, next_unresolved) = payload
          emit_debug(
            All,
            on_debug,
            "[fetch] complete node="
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
          emit_debug(
            All,
            on_debug,
            "[queue] complete node="
            <> node_key(node)
            <> " pushed="
            <> int.to_string(list.length(next_nodes))
            <> " unresolved="
            <> int.to_string(list.length(next_unresolved)),
          )
          let queue = list.append(queue, with_level(next_nodes, level + 1))
          concurrent_loop(
            queue,
            running - 1,
            visited,
            item_seen,
            list_seen,
            items,
            lists,
            unresolved,
            starts,
            max_active,
            subject,
            expand,
            on_debug,
          )
        }
      }
    }
  }
}

fn max_int(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
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
              emit_debug(
                depth,
                on_debug,
                "[fetch] start node="
                <> node_key(node)
                <> " level="
                <> int.to_string(level),
              )
              let ExpandResult(next_items, next_lists, next_nodes, next_unresolved) = expand(node)
              emit_debug(
                depth,
                on_debug,
                "[fetch] complete node="
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
