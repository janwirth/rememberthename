# Source Queue Retry Spec

Platform/adapter timing and queue policy is centralized in:

- `PROVIDER_TIMING_SPEC.md`

Implementation docs/types:

- `src/adapters/core.gleam`
- `src/default_queue.gleam`
- `src/platform_queue_policy.gleam`
# Source Queue Retry Spec

Moved into code as module docs and types:

- `src/platform_queue_policy.gleam`
- `src/default_queue.gleam`
# Source Queue Retry Spec

This file is platform/adapter integration only. Generic queue behavior lives in `QUEUE_SPEC.md`.

Platform queue is reused by adapter type, not by source URL:

```gleam
pub type AdapterType {
  BandcampAdapter
  SoundcloudAdapter
  SpotifyAdapter
  YoutubeAdapter
}
```

Platform policy wraps generic `QueuePolicy` and adds source error fields:

```gleam
pub type ItemError {
  ItemError(
    entity_type: String, // "track" | "list"
    service: String,
    title: Option(String),
    resource_id: Option(String), // prefer resource_id.to_string(...)
    source_id: String, // fallback when resource_id unavailable
    task_key: String,
    reason: String,
  )
}

pub type PlatformPolicy {
  PlatformPolicy(
    adapter_type: AdapterType,
    queue: queue.QueuePolicy,
  )
}
```

Hard-coded per-platform policies:

```gleam
pub const spotify_policy =
  PlatformPolicy(
    adapter_type: SpotifyAdapter,
    queue:
      queue.QueuePolicy(
        max_queue_size: 500,
        requests_per_minute: 180,
        backoff_intervals_ms: [250, 750, 1500, 3000],
      ),
  )
```

Depth runner plugs tasks into generic queue:

```gleam
pub type DepthTask {
  DepthTask(node: AdapterNode, level: Int)
}

pub fn execute_depth_task(
  task: DepthTask,
  depth: DepthMode,
  expand: fn(AdapterNode) -> ExpandResult,
) -> Result(queue.TaskOutcome(DepthTask, ExpandResult, ItemError), queue.TaskError(ItemError)) {
  let DepthTask(node, level) = task
  case can_expand(level, depth) {
    False ->
      Ok(queue.TaskOutcome(recurse: [], results: [], errors: []))
    True -> {
      let result = expand(node)
      let ExpandResult(_, _, next_nodes, _) = result
      let recurse = list.map(next_nodes, fn(n) { DepthTask(n, level + 1) })
      Ok(queue.TaskOutcome(recurse: recurse, results: [result], errors: []))
    }
  }
}
```

Error mapping contract:

- If `resource_id` can be constructed/parsed, set `resource_id: Some(resource_id.to_string(...))`.
- Otherwise set `resource_id: None` and keep `source_id` as fallback.
- Errors are item-level only; no source-wide fatal termination.

Tuna:

- Tuna bypasses platform queue and retry path.
# Platform Queue Plugin Spec

Queue runtime is keyed by adapter type (platform), reused across tasks of that adapter:

```gleam
pub type AdapterType {
  BandcampAdapter
  SoundcloudAdapter
  SpotifyAdapter
  YoutubeAdapter
}

pub type PlatformQueuePolicy {
  PlatformQueuePolicy(
    max_queue_size: Int,
    requests_per_minute: Int,
    // Fixed retry delays, no dynamic/exponential math.
    backoff_intervals_ms: List(Int),
  )
}
```

One queue instance per adapter type:

```gleam
pub type PlatformQueueState(task, result) {
  PlatformQueueState(
    adapter_type: AdapterType,
    pending: List(task),
    active: Int,
    policy: PlatformQueuePolicy,
    last_request_at_ms: Int,
    results: List(result),
    errors: List(ItemError),
  )
}
```

Item-level error payload (no attempts):

```gleam
pub type ItemError {
  ItemError(
    entity_type: String, // "track" | "list"
    service: String,
    title: Option(String), // title if available
    resource_id: Option(String), // prefer `resource_id.to_string(...)` shape
    source_id: String, // fallback when resource_id is unavailable
    task_key: String,
    reason: String,
  )
}
```

Resource id expectation:

```gleam
// Preferred:
//   resource_id: Some(resource_id.to_string(rid))
// Fallback:
//   resource_id: None
//   source_id: <adapter source id>
```

Hard-coded backoff examples:

```gleam
pub const spotify_policy =
  PlatformQueuePolicy(
    max_queue_size: 500,
    requests_per_minute: 180,
    backoff_intervals_ms: [250, 750, 1500, 3000],
  )

pub const youtube_policy =
  PlatformQueuePolicy(
    max_queue_size: 500,
    requests_per_minute: 120,
    backoff_intervals_ms: [500, 1000, 2000, 5000],
  )
```

Generic plugin hook: the depth executor feeds tasks to a platform queue runner.

```gleam
pub type TaskOutcome(task, result) {
  TaskOutcome(
    recurse: List(task),
    results: List(result),
    errors: List(ItemError),
  )
}

pub type TaskError {
  RetryableTaskError(reason: String)
  FatalTaskError(reason: String)
}

pub fn run_platform_queue(
  initial_tasks: List(task),
  queue: PlatformQueueState(task, result),
  execute_task: fn(task) -> Result(TaskOutcome(task, result), TaskError),
) -> #(List(result), List(ItemError)) {
  // queue loop:
  // - dequeue one task (FIFO)
  // - enforce requests_per_minute gate
  // - run task with retry list from `backoff_intervals_ms`
  // - append recurse/results/errors
  // - continue until pending empty
  todo
}
```

Depth integration stays generic:

```gleam
// Existing depth traversal becomes a task producer.
pub type DepthTask {
  DepthTask(node: AdapterNode, level: Int)
}

pub fn execute_depth_task(
  task: DepthTask,
  depth: DepthMode,
  expand: fn(AdapterNode) -> ExpandResult,
) -> Result(TaskOutcome(DepthTask, ExpandResult), TaskError) {
  let DepthTask(node, level) = task
  case can_expand(level, depth) {
    False -> Ok(TaskOutcome(recurse: [], results: [], errors: []))
    True -> {
      let result = expand(node)
      let ExpandResult(_, _, next_nodes, _) = result
      let recurse = list.map(next_nodes, fn(n) { DepthTask(n, level + 1) })
      Ok(TaskOutcome(recurse: recurse, results: [result], errors: []))
    }
  }
}
```

Adapter-side usage sketch:

```gleam
let initial = [DepthTask(core.ProfileEntry(profile_url), 0)]
let queue =
  PlatformQueueState(
    adapter_type: SpotifyAdapter,
    pending: initial,
    active: 0,
    policy: spotify_policy,
    last_request_at_ms: 0,
    results: [],
    errors: [],
  )
let #(task_results, task_errors) =
  run_platform_queue(initial, queue, fn(task) {
    execute_depth_task(task, depth, fn(node) { expand(node, config, cache_mode) })
  })
```

Rules:

- queue state is reused by adapter type (platform), not by individual source url
- throttling unit is requests per minute
- retries use only hard-coded `backoff_intervals_ms`
- only item-level errors are surfaced
- tuna bypasses this queue plugin
# Platform Queue + Retry (Depth Plugin)

One bounded queue per platform (`bandcamp`, `soundcloud`, `spotify`, `youtube`), with per-platform rate limit + retries. Only individual failed `track`/`list` entities are raised. Tuna is out of scope.

```gleam
pub type Platform {
  Bandcamp
  Soundcloud
  Spotify
  Youtube
}

pub type QueuePolicy {
  QueuePolicy(
    max_queue_size: Int,
    requests_per_second: Int,
    max_attempts: Int,
    base_backoff_ms: Int,
    max_backoff_ms: Int,
  )
}

pub type ItemError {
  ItemError(
    entity_type: String, // "track" | "list"
    service: String,
    source_id: String,
    node_key: String,
    attempts: Int,
    reason: String,
  )
}
```

```gleam
pub type ResolveResult {
  ResolveResult(
    items: List(UnifiedItem),
    lists: List(UnifiedCollection),
    unresolved: List(AdapterNode),
    errored_items: List(ItemError),
  )
}
```

Hook point is `adapters/core.resolve_profile_url_with_debug`, so adapters keep current `expand(node)` signatures.

```gleam
pub fn resolve_profile_url_with_debug_and_policy(
  profile_url: String,
  depth: DepthMode,
  platform: Platform,
  expand: fn(AdapterNode) -> ExpandResult,
  policy: QueuePolicy,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  loop(
    [#(ProfileEntry(profile_url), 0)],
    set.new(),
    set.new(),
    set.new(),
    [],
    [],
    [],
    [],
    depth,
    platform,
    expand,
    policy,
    on_debug,
  )
}
```

```gleam
fn loop(
  queue: List(#(AdapterNode, Int)),
  visited: set.Set(String),
  item_seen: set.Set(String),
  list_seen: set.Set(String),
  items: List(UnifiedItem),
  lists: List(UnifiedCollection),
  unresolved: List(AdapterNode),
  errors: List(ItemError),
  depth: DepthMode,
  platform: Platform,
  expand: fn(AdapterNode) -> ExpandResult,
  policy: QueuePolicy,
  on_debug: fn(String) -> Nil,
) -> ResolveResult {
  case queue {
    [] -> ResolveResult(items, lists, unresolved, errors)
    [#(node, level), ..rest] -> {
      let key = node_key(node)
      case set.contains(visited, key) || !can_expand(level, depth) {
        True ->
          loop(
            rest,
            visited,
            item_seen,
            list_seen,
            items,
            lists,
            unresolved,
            errors,
            depth,
            platform,
            expand,
            policy,
            on_debug,
          )
        False -> {
          let visited = set.insert(visited, key)
          let _ = enforce_rate_limit(platform, policy)
          let #(result, retry_errors) =
            expand_with_retry(platform, node, expand, policy)
          let ExpandResult(next_items, next_lists, next_nodes, next_unresolved) = result
          let #(items, item_seen) = merge_items(items, item_seen, next_items)
          let #(lists, list_seen) = merge_lists(lists, list_seen, next_lists)
          let #(bounded_next, overflow_errors) = enqueue_bounded(node, next_nodes, policy)
          let queue = list.append(rest, with_level(bounded_next, level + 1))
          loop(
            queue,
            visited,
            item_seen,
            list_seen,
            items,
            lists,
            list.append(unresolved, next_unresolved),
            errors |> list.append(retry_errors) |> list.append(overflow_errors),
            depth,
            platform,
            expand,
            policy,
            on_debug,
          )
        }
      }
    }
  }
}
```

```gleam
fn expand_with_retry(
  platform: Platform,
  node: AdapterNode,
  expand: fn(AdapterNode) -> ExpandResult,
  policy: QueuePolicy,
) -> #(ExpandResult, List(ItemError)) {
  let QueuePolicy(_, _, max_attempts, base_backoff_ms, max_backoff_ms) = policy
  attempt_expand(
    platform,
    node,
    expand,
    1,
    max_attempts,
    base_backoff_ms,
    max_backoff_ms,
    [],
  )
}
```

```gleam
fn enqueue_bounded(
  parent: AdapterNode,
  next_nodes: List(AdapterNode),
  policy: QueuePolicy,
) -> #(List(AdapterNode), List(ItemError)) {
  let QueuePolicy(max_queue_size, _, _, _, _) = policy
  case list.length(next_nodes) <= max_queue_size {
    True -> #(next_nodes, [])
    False -> {
      let kept = list.take(next_nodes, max_queue_size)
      let dropped = list.drop(next_nodes, max_queue_size)
      let overflow_errors =
        list.map(dropped, fn(node) {
          ItemError(
            entity_type: node_entity_type(node),
            service: node_service(parent),
            source_id: node_source_id(node),
            node_key: node_key(node),
            attempts: 0,
            reason: "queue_overflow",
          )
        })
      #(kept, overflow_errors)
    }
  }
}
```

Adapter integration remains simple:

```gleam
core.resolve_profile_url_with_debug_and_policy(
  profile_url,
  depth,
  core.Spotify,
  fn(node) { expand(node, config, cache_mode) },
  core.QueuePolicy(
    max_queue_size: 500,
    requests_per_second: 4,
    max_attempts: 4,
    base_backoff_ms: 250,
    max_backoff_ms: 3000,
  ),
  on_debug,
)
```

Required tests:

- isolated queue per platform
- bounded enqueue creates item-level overflow errors
- per-platform limiter does not block other platforms
- retriable node eventually succeeds
- retry exhaustion emits item-level error only
- non-retriable error emits item-level error immediately
- partial success still returns other items/lists
# rememberthename - Platform Queue, Rate Limit, Retry Spec

## Goal

Define queue execution for adapter traversal with:

- one bounded queue per platform
- per-platform rate limiting
- retry policy
- error surfacing only at item granularity (`track` or `list`)

Tuna is out of scope for this queue model.

## Scope

In scope:

- `bandcamp`, `soundcloud`, `spotify`, `youtube`
- queueing adapter traversal nodes (`ProfileEntry`, `CategoryNode`, `ListNode`, `PageNode`, ...)
- platform-local throttling and retry handling
- end-of-run error reporting for failed track/list items

Out of scope:

- cross-platform shared queue
- global process-wide rate limits
- tuna adapter runtime behavior

## Queue Model

Each platform gets an independent queue runtime:

- `queue: List(AdapterNode)` with max length `max_queue_size`
- `inflight: Int` (single worker per platform initially; can be extended later)
- `visited: Set(NodeKey)` for dedupe/cycle safety
- `errors: List(ItemError)` for item-level failures

Behavior:

1. enqueue source root node
2. pop head node (FIFO)
3. expand node through adapter callback
4. append emitted `next_nodes` in order
5. continue until queue empty

When queue is full:

- reject newly emitted nodes beyond capacity
- record an `ItemError` on the originating source item/list context

## Rate Limiting

Per-platform limiter is required:

- config: `requests_per_second: Int`
- minimum interval: `1000 / requests_per_second` ms between source requests
- limiter applies before each adapter fetch/expand that touches remote source data

No cross-platform blocking: one platform hitting limits must not stall others.

## Retry Policy

Per node retry with bounded attempts:

- config:
  - `max_attempts: Int` (includes first attempt)
  - `base_backoff_ms: Int`
  - `max_backoff_ms: Int`
- backoff: exponential (`base * 2^(attempt-1)`) capped by `max_backoff_ms`
- retry only retriable failures (network/timeout/5xx/rate-limit responses)
- non-retriable failures are finalized immediately

On retry exhaustion:

- do not fail entire platform run
- emit one `ItemError` for the concrete platform item/list context

## Error Contract (Item-Level Only)

Only individual errored platform entities are raised:

- `entity_type: "track" | "list"`
- `service`
- `source_id`
- `node_key`
- `attempts`
- `reason`

Rules:

- no source-wide fatal raise for recoverable per-item failures
- success of other items/lists continues
- final output includes:
  - successful items/lists
  - `errored_items: List(ItemError)`

## Architecture Hook-In (Depth Plugin)

Queue/rate-limit/retry is a plugin layer on top of current depth traversal, not a replacement.

Current execution path:

- CLI depth flow -> `cli.resolve_source(...)`
- Adapter resolver -> `*_live_expander.resolve_profile_with_debug(...)`
- Shared recursion core -> `adapters/core.resolve_profile_url_with_debug(...)`

Plugin integration points:

1. Add optional execution policy arg to core:
   - `resolve_profile_url_with_debug(..., policy: QueuePolicy, ...)`
2. Keep adapter `expand(node)` contract unchanged.
3. Inside core loop, replace direct expand call with:
   - `policy.before_expand(platform, node)` (rate-limit)
   - `policy.expand_with_retry(platform, node, expand)` (retry wrapper)
   - `policy.after_expand(platform, node, result)` (metrics/debug)
4. Queue bound enforcement is in core when appending `next_nodes`:
   - if over `max_queue_size`, drop overflow nodes and emit `ItemError`.
5. Return shape extends with `errored_items` while preserving existing `items/lists/unresolved`.

Why this is depth-compatible:

- depth semantics stay in core (`can_expand(level, depth)`) exactly as now.
- plugin runs per expand step, so it naturally applies to `Depth1`, `Depth2`, `Depth3`, `All`.
- existing adapters need no traversal rewrites; they benefit via shared core path.

## Ordering + Determinism

- FIFO processing order is stable per source queue
- retries preserve logical order of successful outputs
- emitted `next_nodes` keep adapter order

## Required Tests

- one queue instance per platform is created and isolated
- queue bound is enforced and overflow is reported as item errors
- rate limiter delays per platform without blocking other platforms
- retriable failure succeeds before `max_attempts`
- retriable failure exhausted -> item-level error emitted
- non-retriable failure -> immediate item-level error emitted
- partial success: failed items/lists are reported, others still resolve
