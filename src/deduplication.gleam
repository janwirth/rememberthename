import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile
import source_id_normalizer

pub type AssetType {
  Cover
  Audio
}

pub type LocationType {
  Local
  Remote
}

pub type AssetRef {
  AssetRef(
    asset_type: AssetType,
    location_type: LocationType,
    uri: String,
    provider: String,
    content_hash: Option(String),
    metadata: Dict(String, String),
  )
}

pub type SourceLink {
  SourceLink(
    adapter: String,
    source_id: String,
    raw_source_id: Option(String),
    track_title: String,
    track_artist: String,
    inserted_at: String,
  )
}

pub type Bucket {
  Bucket(
    bucket_id: String,
    title: String,
    artist: String,
    source_links: List(SourceLink),
    assets: List(AssetRef),
    created_at: String,
    updated_at: String,
  )
}

pub type TrackItem {
  TrackItem(
    title: String,
    artist: String,
    adapter: String,
    source_id: String,
    raw_source_id: Option(String),
    assets: List(AssetRef),
  )
}

pub type AmbiguityRecord {
  AmbiguityRecord(
    adapter: String,
    source_id: String,
    title: String,
    artist: String,
    candidate_bucket_ids: List(String),
    reason: String,
  )
}

pub type DeduplicationResult {
  DeduplicationResult(buckets: List(Bucket), ambiguities: List(AmbiguityRecord))
}

type State {
  State(
    buckets: List(Bucket),
    ambiguities: List(AmbiguityRecord),
    next_bucket_number: Int,
    next_time: Int,
  )
}

pub fn deduplicate(items: List(TrackItem)) -> DeduplicationResult {
  let State(buckets, ambiguities, _, _) =
    list.fold(
      items,
      State([], [], 1, 1),
      fn(state, item) { insert_item(state, item) },
    )
  DeduplicationResult(buckets, ambiguities)
}

pub fn deduplicate_csv_file(path: String) -> Result(DeduplicationResult, String) {
  case simplifile.read(from: path) {
    Ok(content) -> deduplicate_csv(content)
    Error(_) -> Error("Unable to read CSV file: " <> path)
  }
}

pub fn one_bucket_per_track_csv_file(path: String) -> Result(DeduplicationResult, String) {
  case simplifile.read(from: path) {
    Ok(content) -> one_bucket_per_track_csv(content)
    Error(_) -> Error("Unable to read CSV file: " <> path)
  }
}

pub fn deduplicate_csv(content: String) -> Result(DeduplicationResult, String) {
  case parse_csv_rows(content) {
    Error(msg) -> Error(msg)
    Ok(rows) ->
      case rows {
        [] -> Error("CSV is empty")
        [header, ..body] ->
          case header == ["title", "artist", "service", "source_id", "tags"]
            || header == ["title", "artist", "service", "source_id"] {
            False -> Error("Unexpected CSV header")
            True -> {
              let items = list.map(body, row_to_track_item)
              Ok(deduplicate(items))
            }
          }
      }
  }
}

pub fn one_bucket_per_track_csv(content: String) -> Result(DeduplicationResult, String) {
  case parse_csv_rows(content) {
    Error(msg) -> Error(msg)
    Ok(rows) ->
      case rows {
        [] -> Error("CSV is empty")
        [header, ..body] ->
          case header == ["title", "artist", "service", "source_id", "tags"]
            || header == ["title", "artist", "service", "source_id"] {
            False -> Error("Unexpected CSV header")
            True -> {
              let items = list.map(body, row_to_track_item)
              let buckets = one_bucket_per_track_buckets(items, 1, 1, [])
              Ok(DeduplicationResult(buckets, []))
            }
          }
      }
  }
}

pub fn buckets_csv(result: DeduplicationResult) -> String {
  let DeduplicationResult(buckets, _) = result
  let header =
    "bucket_id,title,artist,source_links_count,assets_count,created_at,updated_at"
  let rows =
    list.map(buckets, fn(bucket) {
      let Bucket(bucket_id, title, artist, source_links, assets, created_at, updated_at) =
        bucket
      [
        bucket_id,
        title,
        artist,
        int.to_string(list.length(source_links)),
        int.to_string(list.length(assets)),
        created_at,
        updated_at,
      ]
      |> list.map(csv_cell)
      |> string.join(",")
    })
  string.join([header, ..rows], "\n") <> "\n"
}

pub fn ambiguities_csv(result: DeduplicationResult) -> String {
  let DeduplicationResult(_, ambiguities) = result
  let header = "adapter,source_id,title,artist,candidate_bucket_ids,reason"
  let rows =
    list.map(ambiguities, fn(record) {
      let AmbiguityRecord(adapter, source_id, title, artist, candidate_bucket_ids, reason) =
        record
      [
        adapter,
        source_id,
        title,
        artist,
        string.join(candidate_bucket_ids, "|"),
        reason,
      ]
      |> list.map(csv_cell)
      |> string.join(",")
    })
  string.join([header, ..rows], "\n") <> "\n"
}

pub fn local_asset(
  asset_type: AssetType,
  device_id: String,
  path: String,
  metadata: Dict(String, String),
) -> AssetRef {
  let scoped_path = strip_leading_slashes(string.trim(path))
  AssetRef(
    asset_type: asset_type,
    location_type: Local,
    uri: "device://" <> string.trim(device_id) <> "/" <> scoped_path,
    provider: "device",
    content_hash: None,
    metadata: metadata,
  )
}

pub fn remote_asset(
  asset_type: AssetType,
  uri: String,
  provider: String,
  metadata: Dict(String, String),
) -> AssetRef {
  AssetRef(
    asset_type: asset_type,
    location_type: Remote,
    uri: uri,
    provider: provider,
    content_hash: None,
    metadata: metadata,
  )
}

fn insert_item(state: State, item: TrackItem) -> State {
  let State(buckets, ambiguities, next_bucket_number, next_time) = state
  let TrackItem(title, artist, adapter, source_id, _, _) = item
  let normalized_source_id = source_id_normalizer.normalize(adapter, source_id)
  case match_by_source_id(buckets, adapter, normalized_source_id) {
    Some(bucket) ->
      merge_into_bucket(state, bucket, item, "exact_source_id")
    None -> {
      let strong_matches = match_by_strong_metadata(buckets, title, artist)
      case strong_matches {
        [bucket] -> merge_into_bucket(state, bucket, item, "strong_metadata")
        [] -> {
          let weak_matches =
            match_by_weak_metadata(
              buckets,
              title,
              artist,
              adapter,
              normalized_source_id,
            )
          case weak_matches {
            [bucket] -> merge_into_bucket(state, bucket, item, "weak_metadata")
            [] ->
              create_bucket(
                state,
                item,
              )
            _ -> {
              let candidate_ids =
                list.map(weak_matches, fn(candidate) {
                  let Bucket(bucket_id, _, _, _, _, _, _) = candidate
                  bucket_id
                })
              let reason =
                "ambiguous_weak_metadata_candidates="
                <> int.to_string(list.length(weak_matches))
              let ambiguity =
                AmbiguityRecord(
                  adapter: adapter,
                  source_id: normalized_source_id,
                  title: title,
                  artist: artist,
                  candidate_bucket_ids: candidate_ids,
                  reason: reason,
                )
              State(
                buckets: buckets,
                ambiguities: list.append(ambiguities, [ambiguity]),
                next_bucket_number: next_bucket_number,
                next_time: next_time,
              )
            }
          }
        }
        _ -> {
          let candidate_ids =
            list.map(strong_matches, fn(candidate) {
              let Bucket(bucket_id, _, _, _, _, _, _) = candidate
              bucket_id
            })
          let reason =
            "ambiguous_strong_metadata_candidates="
            <> int.to_string(list.length(strong_matches))
          let ambiguity =
            AmbiguityRecord(
              adapter: adapter,
              source_id: normalized_source_id,
              title: title,
              artist: artist,
              candidate_bucket_ids: candidate_ids,
              reason: reason,
            )
          State(
            buckets: buckets,
            ambiguities: list.append(ambiguities, [ambiguity]),
            next_bucket_number: next_bucket_number,
            next_time: next_time,
          )
        }
      }
    }
  }
}

fn one_bucket_per_track_buckets(
  items: List(TrackItem),
  next_bucket_number: Int,
  next_time: Int,
  acc: List(Bucket),
) -> List(Bucket) {
  case items {
    [] -> list.reverse(acc)
    [item, ..rest] -> {
      let TrackItem(title, artist, _, source_id, _, assets) = item
      let canonical_title =
        case string.trim(title) == "" {
          True ->
            case string.trim(source_id) == "" {
              True -> "unknown"
              False -> source_id
            }
          False -> title
        }
      let inserted_at = time_token(next_time)
      let source_link = source_link_from_item(item, inserted_at)
      let bucket =
        Bucket(
          bucket_id: "bucket-" <> int.to_string(next_bucket_number),
          title: canonical_title,
          artist: artist,
          source_links: [source_link],
          assets: dedupe_assets(assets),
          created_at: inserted_at,
          updated_at: inserted_at,
        )
      one_bucket_per_track_buckets(
        rest,
        next_bucket_number + 1,
        next_time + 1,
        [bucket, ..acc],
      )
    }
  }
}

fn create_bucket(state: State, item: TrackItem) -> State {
  let State(buckets, ambiguities, next_bucket_number, next_time) = state
  let TrackItem(title, artist, _, _, _, assets) = item
  let inserted_at = time_token(next_time)
  let source_link = source_link_from_item(item, inserted_at)
  let bucket =
    Bucket(
      bucket_id: "bucket-" <> int.to_string(next_bucket_number),
      title: title,
      artist: artist,
      source_links: [source_link],
      assets: dedupe_assets(assets),
      created_at: inserted_at,
      updated_at: inserted_at,
    )
  State(
    buckets: list.append(buckets, [bucket]),
    ambiguities: ambiguities,
    next_bucket_number: next_bucket_number + 1,
    next_time: next_time + 1,
  )
}

fn merge_into_bucket(
  state: State,
  matched_bucket: Bucket,
  item: TrackItem,
  _rule: String,
) -> State {
  let State(buckets, ambiguities, next_bucket_number, next_time) = state
  let Bucket(bucket_id, title, artist, source_links, assets, created_at, _) = matched_bucket
  let inserted_at = time_token(next_time)
  let incoming_link = source_link_from_item(item, inserted_at)
  let merged_links = merge_source_links(source_links, incoming_link)
  let TrackItem(_, _, _, _, _, incoming_assets) = item
  let merged_assets = merge_assets(assets, incoming_assets)
  let updated_bucket =
    Bucket(
      bucket_id: bucket_id,
      title: title,
      artist: artist,
      source_links: merged_links,
      assets: merged_assets,
      created_at: created_at,
      updated_at: inserted_at,
    )
  let next_buckets =
    list.map(buckets, fn(bucket) {
      let Bucket(id, _, _, _, _, _, _) = bucket
      case id == bucket_id {
        True -> updated_bucket
        False -> bucket
      }
    })
  State(
    buckets: next_buckets,
    ambiguities: ambiguities,
    next_bucket_number: next_bucket_number,
    next_time: next_time + 1,
  )
}

fn source_link_from_item(item: TrackItem, inserted_at: String) -> SourceLink {
  let TrackItem(title, artist, adapter, source_id, raw_source_id, _) = item
  SourceLink(
    adapter: adapter,
    source_id: source_id_normalizer.normalize(adapter, source_id),
    raw_source_id: source_link_raw_source_id(source_id, raw_source_id),
    track_title: title,
    track_artist: artist,
    inserted_at: inserted_at,
  )
}

fn source_link_raw_source_id(source_id: String, raw_source_id: Option(String)) -> Option(String) {
  case raw_source_id {
    Some(value) -> Some(value)
    None ->
      case source_id == "" {
        True -> None
        False -> Some(source_id)
      }
  }
}

fn merge_source_links(existing: List(SourceLink), incoming: SourceLink) -> List(SourceLink) {
  let SourceLink(adapter, source_id, _, _, _, _) = incoming
  case list.any(existing, fn(link) {
    let SourceLink(current_adapter, current_source_id, _, _, _, _) = link
    current_adapter == adapter && current_source_id == source_id
  }) {
    True -> existing
    False -> list.append(existing, [incoming])
  }
}

fn merge_assets(existing: List(AssetRef), incoming: List(AssetRef)) -> List(AssetRef) {
  dedupe_assets(list.append(existing, incoming))
}

fn dedupe_assets(items: List(AssetRef)) -> List(AssetRef) {
  list.fold(items, [], fn(acc, asset) {
    case list.any(acc, fn(existing) { asset_key(existing) == asset_key(asset) }) {
      True -> acc
      False -> list.append(acc, [asset])
    }
  })
}

fn asset_key(asset: AssetRef) -> String {
  let AssetRef(asset_type, location_type, uri, provider, _, _) = asset
  asset_type_text(asset_type)
  <> "|"
  <> location_type_text(location_type)
  <> "|"
  <> uri
  <> "|"
  <> provider
}

fn match_by_source_id(
  buckets: List(Bucket),
  adapter: String,
  normalized_source_id: String,
) -> Option(Bucket) {
  case list.find(buckets, fn(bucket) {
    let Bucket(_, _, _, source_links, _, _, _) = bucket
    list.any(source_links, fn(link) {
      let SourceLink(current_adapter, current_source_id, _, _, _, _) = link
      current_adapter == adapter && current_source_id == normalized_source_id
    })
  }) {
    Ok(bucket) -> Some(bucket)
    Error(_) -> None
  }
}

fn match_by_strong_metadata(
  buckets: List(Bucket),
  title: String,
  artist: String,
) -> List(Bucket) {
  let normalized_title = normalize_text(title)
  let normalized_artist = normalize_text(artist)
  list.filter(buckets, fn(bucket) {
    let Bucket(_, bucket_title, bucket_artist, _, _, _, _) = bucket
    normalize_text(bucket_title) == normalized_title
    && normalize_text(bucket_artist) == normalized_artist
  })
}

fn match_by_weak_metadata(
  buckets: List(Bucket),
  title: String,
  artist: String,
  adapter: String,
  normalized_source_id: String,
) -> List(Bucket) {
  let normalized_title = normalize_text(title)
  let normalized_artist = normalize_text(artist)
  list.filter(buckets, fn(bucket) {
    let Bucket(_, bucket_title, bucket_artist, source_links, _, _, _) = bucket
    let bucket_title_norm = normalize_text(bucket_title)
    let bucket_artist_norm = normalize_text(bucket_artist)
    let title_matches = bucket_title_norm == normalized_title
    let artist_matches =
      normalized_artist == ""
      || bucket_artist_norm == ""
      || string.starts_with(normalized_artist, bucket_artist_norm)
      || string.starts_with(bucket_artist_norm, normalized_artist)
    let guardrail_ok =
      weak_guardrail_allows_merge(source_links, adapter, normalized_source_id)
    title_matches && artist_matches && guardrail_ok
  })
}

fn weak_guardrail_allows_merge(
  source_links: List(SourceLink),
  adapter: String,
  normalized_source_id: String,
) -> Bool {
  let same_adapter_links =
    list.filter(source_links, fn(link) {
      let SourceLink(current_adapter, _, _, _, _, _) = link
      current_adapter == adapter
    })
  case same_adapter_links {
    [] -> True
    _ ->
      list.any(same_adapter_links, fn(link) {
        let SourceLink(_, current_source_id, _, _, _, _) = link
        current_source_id == normalized_source_id
      })
  }
}

fn normalize_text(value: String) -> String {
  value
  |> string.lowercase
  |> strip_common_punctuation
  |> string.split(" ")
  |> list.filter(fn(part) { string.trim(part) != "" })
  |> string.join(" ")
}

fn strip_common_punctuation(value: String) -> String {
  [
    ".",
    ",",
    "!",
    "?",
    ":",
    ";",
    "-",
    "_",
    "(",
    ")",
    "[",
    "]",
    "{",
    "}",
    "/",
    "\\",
    "'",
    "\"",
    "&",
  ]
  |> list.fold(value, fn(acc, token) { string.replace(acc, token, " ") })
  |> string.trim
}

fn row_to_track_item(row: List(String)) -> TrackItem {
  case row {
    [title, artist, adapter, source_id, _tags] ->
      TrackItem(
        title: title,
        artist: artist,
        adapter: adapter,
        source_id: source_id,
        raw_source_id: Some(source_id),
        assets: [],
      )
    [title, artist, adapter, source_id] ->
      TrackItem(
        title: title,
        artist: artist,
        adapter: adapter,
        source_id: source_id,
        raw_source_id: Some(source_id),
        assets: [],
      )
    _ ->
      TrackItem(
        title: "",
        artist: "",
        adapter: "",
        source_id: "",
        raw_source_id: None,
        assets: [],
      )
  }
}

type CsvParseState {
  CsvParseState(
    rows: List(List(String)),
    row: List(String),
    cell_parts: List(String),
    in_quotes: Bool,
  )
}

fn parse_csv_rows(content: String) -> Result(List(List(String)), String) {
  let chars = string.to_graphemes(content)
  parse_csv_chars(chars, CsvParseState([], [], [], False))
}

fn parse_csv_chars(
  chars: List(String),
  state: CsvParseState,
) -> Result(List(List(String)), String) {
  case chars {
    [] -> finalize_csv(state)
    [current, ..rest] ->
      case state.in_quotes {
        True -> parse_csv_inside_quotes(current, rest, state)
        False -> parse_csv_outside_quotes(current, rest, state)
      }
  }
}

fn parse_csv_outside_quotes(
  current: String,
  rest: List(String),
  state: CsvParseState,
) -> Result(List(List(String)), String) {
  case current {
    "\"" -> {
      let CsvParseState(rows, row, cell_parts, _) = state
      parse_csv_chars(rest, CsvParseState(rows, row, cell_parts, True))
    }
    "," -> {
      let CsvParseState(rows, row, cell_parts, in_quotes) = state
      let cell = string.join(list.reverse(cell_parts), "")
      parse_csv_chars(rest, CsvParseState(rows, list.append(row, [cell]), [], in_quotes))
    }
    "\n" -> {
      let CsvParseState(rows, row, cell_parts, in_quotes) = state
      let cell = string.join(list.reverse(cell_parts), "")
      let next_row = list.append(row, [cell])
      parse_csv_chars(rest, CsvParseState(list.append(rows, [next_row]), [], [], in_quotes))
    }
    "\r" -> parse_csv_chars(rest, state)
    _ -> {
      let CsvParseState(rows, row, cell_parts, in_quotes) = state
      parse_csv_chars(
        rest,
        CsvParseState(rows, row, [current, ..cell_parts], in_quotes),
      )
    }
  }
}

fn parse_csv_inside_quotes(
  current: String,
  rest: List(String),
  state: CsvParseState,
) -> Result(List(List(String)), String) {
  case current {
    "\"" ->
      case rest {
        ["\"", ..tail] -> {
          let CsvParseState(rows, row, cell_parts, in_quotes) = state
          parse_csv_chars(
            tail,
            CsvParseState(rows, row, ["\"", ..cell_parts], in_quotes),
          )
        }
        _ -> {
          let CsvParseState(rows, row, cell_parts, _) = state
          parse_csv_chars(rest, CsvParseState(rows, row, cell_parts, False))
        }
      }
    _ -> {
      let CsvParseState(rows, row, cell_parts, in_quotes) = state
      parse_csv_chars(
        rest,
        CsvParseState(rows, row, [current, ..cell_parts], in_quotes),
      )
    }
  }
}

fn finalize_csv(state: CsvParseState) -> Result(List(List(String)), String) {
  let CsvParseState(rows, row, cell_parts, in_quotes) = state
  case in_quotes {
    True -> Error("CSV parse error: unclosed quote")
    False -> {
      let cell = string.join(list.reverse(cell_parts), "")
      let current_row = list.append(row, [cell])
      let combined = list.append(rows, [current_row])
      let cleaned_rows =
        list.filter(combined, fn(r) {
          case r {
            [""] -> False
            _ -> True
          }
        })
      Ok(cleaned_rows)
    }
  }
}

fn asset_type_text(value: AssetType) -> String {
  case value {
    Cover -> "cover"
    Audio -> "audio"
  }
}

fn location_type_text(value: LocationType) -> String {
  case value {
    Local -> "local"
    Remote -> "remote"
  }
}

fn csv_cell(value: String) -> String {
  let escaped = string.replace(value, "\"", "\"\"")
  case string.contains(escaped, ",")
    || string.contains(escaped, "\"")
    || string.contains(escaped, "\n")
    || string.contains(escaped, "\r")
  {
    True -> "\"" <> escaped <> "\""
    False -> escaped
  }
}

fn strip_leading_slashes(value: String) -> String {
  case string.starts_with(value, "/") {
    True -> strip_leading_slashes(string.drop_start(value, 1))
    False -> value
  }
}

fn time_token(value: Int) -> String {
  "t" <> int.to_string(value)
}
