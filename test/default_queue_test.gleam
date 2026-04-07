import adapters/core
import gleam/option.{None}
import default_queue
import gleam/erlang/process
import gleam/list
import gleam/time/timestamp
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn rate_limit_requests_per_second_test() {
  let policy =
    default_queue.QueuePolicy(max_concurrency: 4, requests_per_second: 2)
  let report =
    default_queue.run_default_queue([1, 2, 3], policy, fn(_task) {
      default_queue.TaskPlan(
        duration_ms: 0,
        outcome: default_queue.TaskOutcome(
          recurse: [],
          results: [1],
          errors: [],
        ),
      )
    })
  let default_queue.QueueReport(_, _, starts, elapsed_ms, max_active) = report
  starts |> should.equal([0, 500, 1000])
  elapsed_ms |> should.equal(1000)
  max_active |> should.equal(1)
}

pub fn concurrency_limit_test() {
  let policy =
    default_queue.QueuePolicy(max_concurrency: 2, requests_per_second: 1000)
  let report =
    default_queue.run_default_queue([1, 2, 3, 4], policy, fn(task) {
      default_queue.TaskPlan(
        duration_ms: 100,
        outcome: default_queue.TaskOutcome(
          recurse: [],
          results: [task],
          errors: [],
        ),
      )
    })
  let default_queue.QueueReport(results, _, starts, elapsed_ms, max_active) =
    report
  results |> should.equal([1, 2, 3, 4])
  max_active |> should.equal(2)
  starts |> should.equal([0, 1, 100, 101])
  elapsed_ms |> should.equal(201)
}

pub fn recurse_tasks_appended_fifo_test() {
  let policy =
    default_queue.QueuePolicy(max_concurrency: 1, requests_per_second: 1000)
  let report =
    default_queue.run_default_queue([1], policy, fn(task) {
      case task {
        1 ->
          default_queue.TaskPlan(
            duration_ms: 0,
            outcome: default_queue.TaskOutcome(
              recurse: [2, 3],
              results: [1],
              errors: [],
            ),
          )
        _ ->
          default_queue.TaskPlan(
            duration_ms: 0,
            outcome: default_queue.TaskOutcome(
              recurse: [],
              results: [task],
              errors: [],
            ),
          )
      }
    })
  let default_queue.QueueReport(results, _, starts, _, _) = report
  results |> should.equal([1, 2, 3])
  starts |> should.equal([0, 1, 2])
}

pub fn depth_all_debug_logs_order_and_content_test() {
  let profile_url = "https://example.test/profile"
  let compact_profile = "example.test/.../profile"
  let debug_subject = process.new_subject()
  let _ =
    core.resolve_profile_url_with_debug(
      profile_url,
      core.All,
      fn(_node) {
        core.ExpandResult(
          items: [
            core.UnifiedItem(
              id: "demo:item:1",
              title: "Demo Song",
              artist: "Demo Artist",
              service: "demo",
              source_type: "item",
              source_id: "1",
              external_source_url: None,
              file_path: None,
              added_at: timestamp.unix_epoch,
            ),
          ],
          lists: [],
          next_nodes: [],
          unresolved: [],
          cache_hits: 0,
          cache_fetches: 0,
        )
      },
      fn(line) { process.send(debug_subject, line) },
    )
  collect_debug_lines(debug_subject, 6, [])
  |> should.equal([
    "[queue] enabled mode=concurrent req_per_sec=3 concurrency=3",
    "[queue] start node=profile:" <> compact_profile <> " level=0",
    "[fetch] start node=profile:" <> compact_profile <> " level=0",
    "[fetch] complete node=profile:"
      <> compact_profile
      <> " items=1 lists=0 next=0",
    "[queue] complete node=profile:"
      <> compact_profile
      <> " pushed=0 unresolved=0",
    "[queue] complete",
  ])
}

fn collect_debug_lines(
  subject: process.Subject(String),
  remaining: Int,
  acc: List(String),
) -> List(String) {
  case remaining <= 0 {
    True -> list.reverse(acc)
    False -> {
      let line = process.receive_forever(subject)
      collect_debug_lines(subject, remaining - 1, [line, ..acc])
    }
  }
}
