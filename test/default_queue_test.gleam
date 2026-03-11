import default_queue
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn rate_limit_requests_per_second_test() {
  let policy = default_queue.QueuePolicy(max_concurrency: 4, requests_per_second: 2)
  let report =
    default_queue.run_default_queue([1, 2, 3], policy, fn(_task) {
      default_queue.TaskPlan(
        duration_ms: 0,
        outcome: default_queue.TaskOutcome(recurse: [], results: [1], errors: []),
      )
    })
  let default_queue.QueueReport(_, _, starts, elapsed_ms, max_active) = report
  starts |> should.equal([0, 500, 1000])
  elapsed_ms |> should.equal(1000)
  max_active |> should.equal(1)
}

pub fn concurrency_limit_test() {
  let policy = default_queue.QueuePolicy(max_concurrency: 2, requests_per_second: 1000)
  let report =
    default_queue.run_default_queue([1, 2, 3, 4], policy, fn(task) {
      default_queue.TaskPlan(
        duration_ms: 100,
        outcome: default_queue.TaskOutcome(recurse: [], results: [task], errors: []),
      )
    })
  let default_queue.QueueReport(results, _, starts, elapsed_ms, max_active) = report
  results |> should.equal([1, 2, 3, 4])
  max_active |> should.equal(2)
  starts |> should.equal([0, 1, 100, 101])
  elapsed_ms |> should.equal(201)
}

pub fn recurse_tasks_appended_fifo_test() {
  let policy = default_queue.QueuePolicy(max_concurrency: 1, requests_per_second: 1000)
  let report =
    default_queue.run_default_queue([1], policy, fn(task) {
      case task {
        1 ->
          default_queue.TaskPlan(
            duration_ms: 0,
            outcome: default_queue.TaskOutcome(recurse: [2, 3], results: [1], errors: []),
          )
        _ ->
          default_queue.TaskPlan(
            duration_ms: 0,
            outcome: default_queue.TaskOutcome(recurse: [], results: [task], errors: []),
          )
      }
    })
  let default_queue.QueueReport(results, _, starts, _, _) = report
  results |> should.equal([1, 2, 3])
  starts |> should.equal([0, 1, 2])
}
