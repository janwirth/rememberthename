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
import gleam/string
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

pub type QueuePolicy {
  QueuePolicy(max_concurrency: Int, requests_per_second: Int)
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
  resolve_profile_url_with_debug_and_limit(
    profile_url,
    depth,
    0,
    expand,
    fn(_) { Nil },
  )
}

pub fn resolve_profile_url_with_debug(
  profile_url: String,
  depth: DepthMode,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  resolve_profile_url_with_debug_and_limit(profile_url, depth, 0, expand, on_debug)
}

pub fn default_queue_policy() -> QueuePolicy {
  QueuePolicy(max_concurrency: 3, requests_per_second: 3)
}

pub fn resolve_profile_url_with_debug_and_limit(
  profile_url: String,
  depth: DepthMode,
  max_items: Int,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  resolve_profile_url_with_debug_limit_and_queue_policy(
    profile_url,
    depth,
    max_items,
    default_queue_policy(),
    expand,
    on_debug,
  )
}

pub fn resolve_profile_url_with_debug_limit_and_queue_policy(
  profile_url: String,
  depth: DepthMode,
  max_items: Int,
  queue_policy: QueuePolicy,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  case depth {
    All ->
      resolve_profile_url_with_default_queue(
        profile_url,
        max_items,
        queue_policy,
        expand,
        on_debug,
      )
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
        max_items,
        expand,
        on_debug,
      )
  }
}

type WorkerMsg {
  WorkerDone(node: AdapterNode, level: Int, result: ExpandResult)
}

fn resolve_profile_url_with_default_queue(
  profile_url: String,
  max_items: Int,
  queue_policy: QueuePolicy,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  let QueuePolicy(max_concurrency, requests_per_second) =
    normalize_queue_policy(queue_policy)
  let queue_interval_ms = 1000 / requests_per_second
  let subject = process.new_subject()
  emit_debug(
    All,
    on_debug,
    "[queue] enabled mode=concurrent req_per_sec="
    <> int.to_string(requests_per_second)
    <> " concurrency="
    <> int.to_string(max_concurrency),
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
      max_items,
      max_concurrency,
      queue_interval_ms,
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
      max_items,
      max_concurrency,
      queue_interval_ms,
      subject,
      expand,
      on_debug,
    )
  emit_debug(
    All,
    on_debug,
    "[queue] complete",
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
  max_items: Int,
  max_concurrency: Int,
  queue_interval_ms: Int,
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
  case running >= max_concurrency || queue == [] || reached_item_limit(items, max_items) {
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
      let key = node_visit_key(node)
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
            max_items,
            max_concurrency,
            queue_interval_ms,
            subject,
            expand,
            on_debug,
          )
        False -> {
          let visited = set.insert(visited, key)
          emit_debug(
            All,
            on_debug,
            "[queue] start node=" <> node_debug_label(node) <> " level=" <> int.to_string(level),
          )
          emit_debug(
            All,
            on_debug,
            "[fetch] start node="
            <> node_debug_label(node)
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
            max_items,
            max_concurrency,
            queue_interval_ms,
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
  max_items: Int,
  max_concurrency: Int,
  queue_interval_ms: Int,
  subject: process.Subject(WorkerMsg),
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  case queue == [] && running == 0 || reached_item_limit(items, max_items) {
    True ->
      case reached_item_limit(items, max_items) {
        True ->
          ResolveResult(
            items,
            lists,
            with_limit_unresolved(unresolved, queue, max_items),
          )
        False -> ResolveResult(items, lists, unresolved)
      }
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
          max_items,
          max_concurrency,
          queue_interval_ms,
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
            <> node_debug_label(node)
            <> " items="
            <> int.to_string(list.length(next_items))
            <> " lists="
            <> int.to_string(list.length(next_lists))
            <> " next="
            <> int.to_string(list.length(next_nodes)),
          )
          let #(items, item_seen, limit_hit) =
            merge_items(items, item_seen, next_items, max_items)
          let #(lists, list_seen) = merge_lists(lists, list_seen, next_lists)
          let unresolved = list.append(unresolved, next_unresolved)
          emit_debug(
            All,
            on_debug,
            "[queue] complete node="
            <> node_debug_label(node)
            <> " pushed="
            <> int.to_string(list.length(next_nodes))
            <> " unresolved="
            <> int.to_string(list.length(next_unresolved)),
          )
          case limit_hit {
            True -> {
              let deferred =
                list.append(queue, with_level(next_nodes, level + 1))
              ResolveResult(
                items,
                lists,
                with_limit_unresolved(unresolved, deferred, max_items),
              )
            }
            False -> {
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
                max_items,
                max_concurrency,
                queue_interval_ms,
                subject,
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

fn max_int(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}

fn normalize_queue_policy(policy: QueuePolicy) -> QueuePolicy {
  let QueuePolicy(max_concurrency, requests_per_second) = policy
  QueuePolicy(
    max_concurrency: max_int(1, max_concurrency),
    requests_per_second: max_int(1, requests_per_second),
  )
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
  max_items: Int,
  expand: fn(AdapterNode) -> ExpandResult,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  // Tail-recursive resolver with:
  // - queue for deterministic traversal order
  // - visited set for cycle safety
  // - item/list seen sets for deduplication
  case queue == [] || reached_item_limit(items, max_items) {
    True ->
      case reached_item_limit(items, max_items) {
        True ->
          ResolveResult(
            items,
            lists,
            with_limit_unresolved(unresolved, queue, max_items),
          )
        False -> ResolveResult(items, lists, unresolved)
      }
    False -> {
      let current = result.unwrap(list.first(queue), #(PageNode(""), 0))
      let rest = result.unwrap(list.rest(queue), [])
      let #(node, level) = current
      let key = node_visit_key(node)
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
            max_items,
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
                max_items,
                expand,
                on_debug,
              )
            }
            True -> {
              emit_debug(
                depth,
                on_debug,
                "[fetch] start node="
                <> node_debug_label(node)
                <> " level="
                <> int.to_string(level),
              )
              let ExpandResult(next_items, next_lists, next_nodes, next_unresolved) = expand(node)
              emit_debug(
                depth,
                on_debug,
                "[fetch] complete node="
                <> node_debug_label(node)
                <> " items="
                <> int.to_string(list.length(next_items))
                <> " lists="
                <> int.to_string(list.length(next_lists))
                <> " next="
                <> int.to_string(list.length(next_nodes)),
              )
              let #(items, item_seen, limit_hit) =
                merge_items(items, item_seen, next_items, max_items)
              let #(lists, list_seen) = merge_lists(lists, list_seen, next_lists)
              let queue = list.append(rest, with_level(next_nodes, level + 1))
              let unresolved = list.append(unresolved, next_unresolved)
              case limit_hit {
                True ->
                  ResolveResult(
                    items,
                    lists,
                    with_limit_unresolved(unresolved, queue, max_items),
                  )
                False ->
                  loop(
                    queue,
                    visited,
                    item_seen,
                    list_seen,
                    items,
                    lists,
                    unresolved,
                    depth,
                    max_items,
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
  max_items: Int,
) -> #(List(UnifiedItem), set.Set(String), Bool) {
  list.fold(
    incoming,
    #(items, seen, reached_item_limit(items, max_items)),
    fn(acc, item) {
      let #(items, seen, limit_hit) = acc
      case limit_hit {
        True -> #(items, seen, True)
        False -> {
          let key = item_key(item)
          case set.contains(seen, key) {
            True -> #(items, seen, reached_item_limit(items, max_items))
            False -> {
              let next_items = list.append(items, [item])
              let next_seen = set.insert(seen, key)
              #(next_items, next_seen, reached_item_limit(next_items, max_items))
            }
          }
        }
      }
    },
  )
}

fn reached_item_limit(items: List(UnifiedItem), max_items: Int) -> Bool {
  case max_items > 0 {
    True -> list.length(items) >= max_items
    False -> False
  }
}

fn with_limit_unresolved(
  unresolved: List(AdapterNode),
  deferred_queue: List(#(AdapterNode, Int)),
  max_items: Int,
) -> List(AdapterNode) {
  let deferred_nodes = list.map(deferred_queue, fn(pair) { first(pair) })
  list.append(
    unresolved,
    list.append(
      deferred_nodes,
      [PageNode("error:source_limit_reached:max_items=" <> int.to_string(max_items))],
    ),
  )
}

fn first(pair: #(a, b)) -> a {
  let #(value, _) = pair
  value
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

fn node_visit_key(node: AdapterNode) -> String {
  case node {
    ProfileEntry(profile_url) -> "profile:" <> profile_url
    CategoryNode(id) -> "category:" <> id
    ListNode(id) -> "list:" <> id
    PageNode(id) -> "page:" <> id
  }
}

fn node_debug_label(node: AdapterNode) -> String {
  case node {
    ProfileEntry(profile_url) -> "profile:" <> short_url(profile_url)
    CategoryNode(id) -> "category:" <> compact_context(id)
    ListNode(id) -> "list:" <> compact_context(id)
    PageNode(id) -> "page:" <> compact_context(id)
  }
}

fn compact_context(ctx: String) -> String {
  let parts = string.split(ctx, "|")
  case parts {
    [first, second, third, ..] ->
      compact_text(first) <> " | " <> compact_text(second) <> " | " <> compact_text(third)
    [first, second, ..] -> compact_text(first) <> " | " <> compact_text(second)
    [first, ..] -> compact_text(first)
    _ -> compact_text(ctx)
  }
}

fn compact_text(value: String) -> String {
  case string.starts_with(value, "http://") || string.starts_with(value, "https://") {
    True -> short_url(value)
    False ->
      case string.split(value, "|") {
        [first, second, ..] -> first <> "|" <> second
        [first, ..] -> first
        _ -> value
      }
  }
}

fn short_url(url: String) -> String {
  let without_scheme =
    case string.split(url, "://") {
      [_, rest, ..] -> rest
      _ -> url
    }
  let host =
    case string.split(without_scheme, "/") {
      [first, ..] -> first
      _ -> without_scheme
    }
  let path =
    case string.split_once(without_scheme, "/") {
      Ok(#(_, rest)) -> rest
      Error(_) -> ""
    }
  let tail = last_non_empty(string.split(path, "/"))
  case tail == "" {
    True -> host
    False -> host <> "/.../" <> strip_query(tail)
  }
}

fn strip_query(value: String) -> String {
  case string.split_once(value, "?") {
    Ok(#(base, _)) -> base
    Error(_) -> value
  }
}

fn last_non_empty(parts: List(String)) -> String {
  case list.reverse(parts) {
    [] -> ""
    [head, ..rest] ->
      case head == "" {
        True -> last_non_empty(list.reverse(rest))
        False -> head
      }
  }
}
