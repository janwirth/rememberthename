# Queue Spec

Queue behavior is specified in code docs and shared timing spec:

- `src/default_queue.gleam`
- `PROVIDER_TIMING_SPEC.md`
# Queue Spec

Moved into code as module docs:

- `src/default_queue.gleam`
# Queue Spec

Default queue supports:

- requests-per-second rate limiting
- max concurrency
- deterministic FIFO task flow with recursive task emission

No backpressure is part of the default queue.

```gleam
pub type QueuePolicy {
  QueuePolicy(
    max_concurrency: Int,
    requests_per_second: Int,
  )
}

pub type TaskOutcome(task, result, error) {
  TaskOutcome(
    recurse: List(task),
    results: List(result),
    errors: List(error),
  )
}

pub type TaskPlan(task, result, error) {
  TaskPlan(
    duration_ms: Int,
    outcome: TaskOutcome(task, result, error),
  )
}

pub type QueueReport(result, error) {
  QueueReport(
    results: List(result),
    errors: List(error),
    start_times_ms: List(Int),
    elapsed_ms: Int,
    max_active: Int,
  )
}
```

```gleam
pub fn run_default_queue(
  initial_tasks: List(task),
  policy: QueuePolicy,
  execute_task: fn(task) -> TaskPlan(task, result, error),
) -> QueueReport(result, error)
```

Execution model:

1. Start tasks FIFO while both constraints allow:
   - active tasks < `max_concurrency`
   - current time >= next allowed start time (`requests_per_second`)
2. Complete tasks at finish time, merge:
   - `results`
   - `errors`
   - `recurse` appended to pending queue tail
3. Continue until no pending and no active tasks.

Testing strategy:

- unit: req/s gate spacing (`start_times_ms`)
- unit: max concurrency cap (`max_active`)
- unit: recursive task enqueue keeps FIFO order
- integration: deterministic `results` ordering under concurrency + rate limits
# Queue Spec

Generic queue runtime for task execution, retries, rate limiting, and backpressure.

```gleam
pub type QueuePolicy {
  QueuePolicy(
    max_queue_size: Int,
    requests_per_minute: Int,
    backoff_intervals_ms: List(Int),
  )
}

pub type QueueState(task, result, error) {
  QueueState(
    pending: List(task),
    active: Int,
    last_request_at_ms: Int,
    results: List(result),
    errors: List(error),
  )
}

pub type TaskOutcome(task, result, error) {
  TaskOutcome(
    recurse: List(task),
    results: List(result),
    errors: List(error),
  )
}

pub type TaskError(error) {
  RetryableTaskError(reason: String, error: error)
  FatalTaskError(reason: String, error: error)
}
```

```gleam
pub fn run_queue(
  initial_tasks: List(task),
  state: QueueState(task, result, error),
  policy: QueuePolicy,
  execute_task: fn(task) -> Result(TaskOutcome(task, result, error), TaskError(error)),
  now_ms: fn() -> Int,
  sleep_ms: fn(Int) -> Nil,
) -> #(List(result), List(error)) {
  // loop:
  // 1) pop FIFO task
  // 2) rate-limit gate (requests_per_minute)
  // 3) execute with retry using backoff_intervals_ms
  // 4) append recurse/results/errors
  // 5) apply backpressure policy on enqueue
  // 6) continue until pending empty
  todo
}
```

Backpressure (required):

```gleam
pub type BackpressureMode {
  RejectNewest
  DropOldest
}

pub fn enqueue_bounded(
  queue: List(task),
  incoming: List(task),
  max_queue_size: Int,
  mode: BackpressureMode,
) -> #(List(task), List(task)) {
  let merged = list.append(queue, incoming)
  case list.length(merged) <= max_queue_size {
    True -> #(merged, [])
    False ->
      case mode {
        RejectNewest -> {
          let kept = list.take(merged, max_queue_size)
          let dropped = list.drop(merged, max_queue_size)
          #(kept, dropped)
        }
        DropOldest -> {
          let overflow = list.length(merged) - max_queue_size
          let kept = list.drop(merged, overflow)
          let dropped = list.take(merged, overflow)
          #(kept, dropped)
        }
      }
  }
}
```

Rate-limit gate (RPM):

```gleam
fn wait_for_rpm(
  requests_per_minute: Int,
  last_request_at_ms: Int,
  now_ms: fn() -> Int,
  sleep_ms: fn(Int) -> Nil,
) -> Int {
  let min_interval = 60000 / requests_per_minute
  let now = now_ms()
  let elapsed = now - last_request_at_ms
  case elapsed < min_interval {
    True -> {
      sleep_ms(min_interval - elapsed)
      now_ms()
    }
    False -> now
  }
}
```

Retry model:

- Retry only `RetryableTaskError`.
- Use `backoff_intervals_ms` exactly as provided.
- If retry list is exhausted, emit the contained error and continue queue execution.
- `FatalTaskError` never retries.

Testing strategy:

- Unit: `enqueue_bounded` covers both modes and overflow sizes.
- Unit: RPM gate waits only when needed and honors interval.
- Unit: retry sequence consumes exact fixed intervals.
- Unit: retryable-then-success returns result once.
- Unit: retryable-exhausted emits one error and continues with next task.
- Unit: fatal error emits immediately and continues.
- Integration: partial success flow (`results` + `errors`) remains deterministic FIFO.
