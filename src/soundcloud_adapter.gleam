import gleam/list
import gleam/result
import gleam/set

pub type DepthMode {
  Depth1
  Depth2
  Full
}

pub type SourceIdentity {
  SourceIdentity(service: String, source_type: String, source_id: String)
}

pub type AdapterNode {
  ProfileEntry(SourceIdentity)
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

pub fn resolve_profile(
  profile: SourceIdentity,
  depth: DepthMode,
  expand: fn(AdapterNode) -> ExpandResult,
) -> ResolveResult {
  loop(
    [#(ProfileEntry(profile), 0)],
    set.new(),
    set.new(),
    set.new(),
    [],
    [],
    [],
    depth,
    expand,
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
  expand: fn(AdapterNode) -> ExpandResult,
) -> ResolveResult {
  case queue == [] {
    True -> ResolveResult(items, lists, unresolved)
    False -> {
      let current = result.unwrap(list.first(queue), #(PageNode(""), 0))
      let rest = result.unwrap(list.rest(queue), [])
      let #(node, level) = current
      let key = node_key(node)
      case set.contains(visited, key) {
        True -> {
          loop(rest, visited, item_seen, list_seen, items, lists, unresolved, depth, expand)
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
              )
            }
            True -> {
              let ExpandResult(next_items, next_lists, next_nodes, next_unresolved) = expand(node)
              let #(items, item_seen) = merge_items(items, item_seen, next_items)
              let #(lists, list_seen) = merge_lists(lists, list_seen, next_lists)
              let queue = list.append(rest, with_level(next_nodes, level + 1))
              let unresolved = list.append(unresolved, next_unresolved)
              loop(queue, visited, item_seen, list_seen, items, lists, unresolved, depth, expand)
            }
          }
        }
      }
    }
  }
}

fn can_expand(level: Int, depth: DepthMode) -> Bool {
  case depth {
    Depth1 -> level < 1
    Depth2 -> level < 2
    Full -> True
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
    ProfileEntry(SourceIdentity(service, source_type, source_id)) -> {
      "profile:" <> service <> ":" <> source_type <> ":" <> source_id
    }
    CategoryNode(id) -> "category:" <> id
    ListNode(id) -> "list:" <> id
    PageNode(id) -> "page:" <> id
  }
}
