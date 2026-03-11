import gleam/float
import gleam/list
import gleam/order
import gleam/string

//// Source limit + validation processing.
////
//// Processing sequence:
//// 1) normalize/validate canonical rows
//// 2) deterministic ordering (`order`, `service`, `source_id`)
//// 3) per-service source limits
pub type Validation {
  Valid
  MissingArtist
}

pub type RawTrack {
  RawTrack(
    title: String,
    artist: String,
    service: String,
    source_id: String,
    order: Float,
  )
}

pub type CanonicalTrack {
  CanonicalTrack(
    title: String,
    artist: String,
    service: String,
    source_id: String,
    order: Float,
    validation: Validation,
  )
}

pub type SourceLimit {
  SourceLimit(service: String, limit: Int)
}

pub fn process(
  raw_tracks: List(RawTrack),
  source_limits: List(SourceLimit),
) -> List(CanonicalTrack) {
  raw_tracks
  |> list.map(validate_track)
  |> stable_sort
  |> apply_source_limits(source_limits)
}

pub fn is_missing_artist(track: CanonicalTrack) -> Bool {
  let CanonicalTrack(_, _, _, _, _, validation) = track
  case validation {
    MissingArtist -> True
    Valid -> False
  }
}

fn validate_track(track: RawTrack) -> CanonicalTrack {
  let RawTrack(title, artist, service, source_id, order) = track
  let validation =
    case string.trim(artist) == "" {
      True -> MissingArtist
      False -> Valid
    }
  CanonicalTrack(
    title: title,
    artist: artist,
    service: service,
    source_id: source_id,
    order: order,
    validation: validation,
  )
}

fn stable_sort(tracks: List(CanonicalTrack)) -> List(CanonicalTrack) {
  list.fold(tracks, [], insert_sorted)
}

fn insert_sorted(
  sorted: List(CanonicalTrack),
  track: CanonicalTrack,
) -> List(CanonicalTrack) {
  case sorted {
    [] -> [track]
    [first, ..rest] ->
      case compare_track(track, first) <= 0 {
        True -> [track, ..sorted]
        False -> [first, ..insert_sorted(rest, track)]
      }
  }
}

// -1 => a < b
//  0 => a == b
//  1 => a > b
fn compare_track(a: CanonicalTrack, b: CanonicalTrack) -> Int {
  let CanonicalTrack(_, _, a_service, a_source_id, a_order, _) = a
  let CanonicalTrack(_, _, b_service, b_source_id, b_order, _) = b
  float.compare(a_order, with: b_order)
  |> order.break_tie(with: string.compare(a_service, b_service))
  |> order.break_tie(with: string.compare(a_source_id, b_source_id))
  |> order.to_int
}

fn apply_source_limits(
  tracks: List(CanonicalTrack),
  source_limits: List(SourceLimit),
) -> List(CanonicalTrack) {
  tracks
  |> list.fold(#([], []), fn(acc, track) {
    let #(kept, counts) = acc
    let CanonicalTrack(_, _, service, _, _, _) = track
    let current = lookup_count(counts, service)
    case allow_for_service(service, current, source_limits) {
      True ->
        #(
          list.append(kept, [track]),
          set_count(counts, service, current + 1),
        )
      False -> #(kept, counts)
    }
  })
  |> first
}

fn allow_for_service(
  service: String,
  current: Int,
  source_limits: List(SourceLimit),
) -> Bool {
  case lookup_limit(source_limits, service) {
    NoLimit -> True
    Limit(limit) ->
      case limit <= 0 {
        True -> False
        False -> current < limit
      }
  }
}

type MaybeLimit {
  NoLimit
  Limit(Int)
}

fn lookup_limit(source_limits: List(SourceLimit), wanted: String) -> MaybeLimit {
  case source_limits {
    [] -> NoLimit
    [SourceLimit(service, limit), ..rest] ->
      case service == wanted {
        True -> Limit(limit)
        False -> lookup_limit(rest, wanted)
      }
  }
}

fn lookup_count(counts: List(#(String, Int)), wanted: String) -> Int {
  case counts {
    [] -> 0
    [#(service, count), ..rest] ->
      case service == wanted {
        True -> count
        False -> lookup_count(rest, wanted)
      }
  }
}

fn set_count(counts: List(#(String, Int)), wanted: String, value: Int) -> List(#(String, Int)) {
  case counts {
    [] -> [#(wanted, value)]
    [#(service, count), ..rest] ->
      case service == wanted {
        True -> [#(service, value), ..rest]
        False -> [#(service, count), ..set_count(rest, wanted, value)]
      }
  }
}

fn first(tuple: #(a, b)) -> a {
  let #(value, _) = tuple
  value
}
