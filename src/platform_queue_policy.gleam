//// Platform queue policy + item error contract.
////
//// This module documents the adapter/platform integration contract that sits
//// on top of `default_queue`.
////
//// Rules:
//// - Queue reuse key is adapter type, not source URL.
//// - Item-level errors only (`track` / `list`); no source-wide fatal surface.
//// - Prefer `resource_id` when available, otherwise keep `source_id` fallback.
//// - Tuna is out of scope for queue/retry policy.
import default_queue
import gleam/option.{type Option}

pub type AdapterType {
  BandcampAdapter
  SoundcloudAdapter
  SpotifyAdapter
  YoutubeAdapter
}

pub type ItemError {
  ItemError(
    entity_type: String,
    service: String,
    title: Option(String),
    resource_id: Option(String),
    source_id: String,
    task_key: String,
    reason: String,
  )
}

pub type PlatformPolicy {
  PlatformPolicy(
    adapter_type: AdapterType,
    queue: default_queue.QueuePolicy,
    backoff_intervals_ms: List(Int),
  )
}
