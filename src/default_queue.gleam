//// Default generic queue runtime.
////
//// This module is the canonical queue spec in code.
////
//// Guarantees:
//// - Deterministic FIFO task execution.
//// - Rate limiting by `requests_per_second`.
//// - Concurrency cap by `max_concurrency`.
//// - Recursive task emission (`TaskOutcome.recurse`) appended to queue tail.
//// - No backpressure behavior in this default implementation.
////
//// Scheduling model:
//// - Virtual-time event loop (no wall clock sleep).
//// - A task can start only when:
////   1) active count < `max_concurrency`
////   2) now >= next_start_at_ms (req/s gate)
//// - Completed tasks contribute:
////   - `results`
////   - `errors`
////   - `recurse` (new tasks appended FIFO)
////
//// Test contract (see `test/default_queue_test.gleam`):
//// - req/s spacing is reflected by `QueueReport.start_times_ms`
//// - max concurrency is reflected by `QueueReport.max_active`
//// - recurse tasks preserve FIFO order in final `results`

import gleam/list

pub type QueuePolicy {
  QueuePolicy(max_concurrency: Int, requests_per_second: Int)
}

pub type TaskOutcome(task, result, error) {
  TaskOutcome(recurse: List(task), results: List(result), errors: List(error))
}

pub type TaskPlan(task, result, error) {
  TaskPlan(duration_ms: Int, outcome: TaskOutcome(task, result, error))
}

type ActiveTask(task, result, error) {
  ActiveTask(
    started_at_ms: Int,
    finishes_at_ms: Int,
    plan: TaskPlan(task, result, error),
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

pub fn run_default_queue(
  initial_tasks: List(task),
  policy: QueuePolicy,
  execute_task: fn(task) -> TaskPlan(task, result, error),
) -> QueueReport(result, error) {
  let #(report, _) =
    run_default_queue_with_state(initial_tasks, policy, Nil, fn(task, state) {
      #(state, execute_task(task))
    })
  report
}

pub fn run_default_queue_with_state(
  initial_tasks: List(task),
  policy: QueuePolicy,
  initial_state: state,
  execute_task: fn(task, state) -> #(state, TaskPlan(task, result, error)),
) -> #(QueueReport(result, error), state) {
  let QueuePolicy(max_concurrency, requests_per_second) =
    normalize_policy(policy)
  loop(
    pending: initial_tasks,
    active: [],
    now_ms: 0,
    next_start_at_ms: 0,
    min_start_interval_ms: 1000 / requests_per_second,
    max_concurrency: max_concurrency,
    results: [],
    errors: [],
    starts: [],
    max_active: 0,
    state: initial_state,
    execute_task_with_state: execute_task,
  )
}

fn loop(
  pending pending: List(task),
  active active: List(ActiveTask(task, result, error)),
  now_ms now_ms: Int,
  next_start_at_ms next_start_at_ms: Int,
  min_start_interval_ms min_start_interval_ms: Int,
  max_concurrency max_concurrency: Int,
  results results: List(result),
  errors errors: List(error),
  starts starts: List(Int),
  max_active max_active: Int,
  state state: state,
  execute_task_with_state execute_task_with_state: fn(task, state) ->
    #(state, TaskPlan(task, result, error)),
) -> #(QueueReport(result, error), state) {
  let #(active, pending, next_start_at_ms, starts, max_active, state) =
    start_ready_tasks(
      active,
      pending,
      now_ms,
      next_start_at_ms,
      min_start_interval_ms,
      max_concurrency,
      starts,
      max_active,
      state,
      execute_task_with_state,
    )
  case pending == [] && active == [] {
    True -> #(
      QueueReport(
        results: list.reverse(results),
        errors: list.reverse(errors),
        start_times_ms: list.reverse(starts),
        elapsed_ms: now_ms,
        max_active: max_active,
      ),
      state,
    )
    False -> {
      let next_finish_at_ms = earliest_finish(active)
      let can_start_later =
        pending != [] && list.length(active) < max_concurrency
      let next_event_at_ms = case active == [] {
        True -> next_start_at_ms
        False ->
          case can_start_later {
            True -> min_int(next_finish_at_ms, next_start_at_ms)
            False -> next_finish_at_ms
          }
      }
      let #(active, pending, results, errors) =
        complete_ready_tasks(active, pending, results, errors, next_event_at_ms)
      loop(
        pending: pending,
        active: active,
        now_ms: next_event_at_ms,
        next_start_at_ms: next_start_at_ms,
        min_start_interval_ms: min_start_interval_ms,
        max_concurrency: max_concurrency,
        results: results,
        errors: errors,
        starts: starts,
        max_active: max_active,
        state: state,
        execute_task_with_state: execute_task_with_state,
      )
    }
  }
}

fn start_ready_tasks(
  active: List(ActiveTask(task, result, error)),
  pending: List(task),
  now_ms: Int,
  next_start_at_ms: Int,
  min_start_interval_ms: Int,
  max_concurrency: Int,
  starts: List(Int),
  max_active: Int,
  state: state,
  execute_task_with_state: fn(task, state) ->
    #(state, TaskPlan(task, result, error)),
) -> #(
  List(ActiveTask(task, result, error)),
  List(task),
  Int,
  List(Int),
  Int,
  state,
) {
  case
    pending,
    list.length(active) < max_concurrency && now_ms >= next_start_at_ms
  {
    [task, ..rest], True -> {
      let #(state, plan) = execute_task_with_state(task, state)
      let TaskPlan(duration_ms, _) = plan
      let active = [
        ActiveTask(
          started_at_ms: now_ms,
          finishes_at_ms: now_ms + non_negative(duration_ms),
          plan: plan,
        ),
        ..active
      ]
      start_ready_tasks(
        active,
        rest,
        now_ms,
        now_ms + min_start_interval_ms,
        min_start_interval_ms,
        max_concurrency,
        [now_ms, ..starts],
        max_int(max_active, list.length(active)),
        state,
        execute_task_with_state,
      )
    }
    _, _ -> #(active, pending, next_start_at_ms, starts, max_active, state)
  }
}

fn complete_ready_tasks(
  active: List(ActiveTask(task, result, error)),
  pending: List(task),
  results: List(result),
  errors: List(error),
  now_ms: Int,
) -> #(
  List(ActiveTask(task, result, error)),
  List(task),
  List(result),
  List(error),
) {
  case active {
    [] -> #([], pending, results, errors)
    [first, ..rest] -> {
      let ActiveTask(_, finishes_at_ms, TaskPlan(_, outcome)) = first
      case finishes_at_ms <= now_ms {
        True -> {
          let TaskOutcome(recurse, new_results, new_errors) = outcome
          complete_ready_tasks(
            rest,
            list.append(pending, recurse),
            list.append(list.reverse(new_results), results),
            list.append(list.reverse(new_errors), errors),
            now_ms,
          )
        }
        False -> {
          let #(remaining, pending, results, errors) =
            complete_ready_tasks(rest, pending, results, errors, now_ms)
          #([first, ..remaining], pending, results, errors)
        }
      }
    }
  }
}

fn earliest_finish(active: List(ActiveTask(task, result, error))) -> Int {
  case active {
    [] -> 0
    [ActiveTask(_, first, _), ..rest] ->
      list.fold(rest, first, fn(acc, task) {
        let ActiveTask(_, finishes_at_ms, _) = task
        min_int(acc, finishes_at_ms)
      })
  }
}

fn normalize_policy(policy: QueuePolicy) -> QueuePolicy {
  let QueuePolicy(max_concurrency, requests_per_second) = policy
  QueuePolicy(
    max_concurrency: max_int(1, max_concurrency),
    requests_per_second: max_int(1, requests_per_second),
  )
}

fn non_negative(value: Int) -> Int {
  max_int(0, value)
}

fn min_int(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}

fn max_int(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}
