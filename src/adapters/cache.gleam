//// Adapter cache helper with explicit runtime modes.
////
//// Contract used by all live expanders:
//// - deterministic cache key: `namespace + phash(key)`
//// - sqlite-backed cache in the process current working directory
//// - empty fetch results are not persisted
////
//// Cache modes:
//// - `CacheUpsert`: read existing cache, fetch+store on miss/empty
//// - `CacheIgnore`: bypass cache, always fetch live
//// - `CacheOverride`: always fetch live and overwrite cache
//// - `CacheReadOnly`: read cache only, never fetch on miss/empty

import gleam/dynamic/decode
import gleam/list
import sqlight

@external(erlang, "cache_hash", "phash")
fn phash(value: String) -> String

pub type CacheMode {
  CacheUpsert
  CacheIgnore
  CacheOverride
  CacheReadOnly
}

pub fn read_or_fetch(
  namespace: String,
  key: String,
  cache_mode: CacheMode,
  fetch: fn() -> String,
) -> String {
  let key_hash = phash(key)
  case cache_mode {
    CacheIgnore -> fetch()
    CacheOverride -> compute_and_store(namespace, key_hash, fetch)
    CacheReadOnly -> read_cached(namespace, key_hash)
    CacheUpsert -> upsert_mode(namespace, key_hash, fetch)
  }
}

fn upsert_mode(namespace: String, key_hash: String, fetch: fn() -> String) -> String {
  case read_cached(namespace, key_hash) {
    "" -> compute_and_store(namespace, key_hash, fetch)
    cached -> cached
  }
}

fn compute_and_store(namespace: String, key_hash: String, fetch: fn() -> String) -> String {
  let value = fetch()
  case value != "" {
    True -> {
      let _ = write_cached(namespace, key_hash, value)
      value
    }
    False -> ""
  }
}

fn read_cached(namespace: String, key_hash: String) -> String {
  use conn <- with_cache_connection("")
  case sqlight.query(
    "select value from adapter_cache where namespace = ? and key_hash = ? limit 1",
    on: conn,
    with: [sqlight.text(namespace), sqlight.text(key_hash)],
    expecting: string_value_decoder(),
  ) {
    Ok(rows) ->
      case list.first(rows) {
        Ok(value) -> value
        Error(_) -> ""
      }
    Error(_) -> ""
  }
}

fn write_cached(namespace: String, key_hash: String, value: String) -> Nil {
  use conn <- with_cache_connection(Nil)
  let _ = sqlight.query(
    "insert into adapter_cache(namespace, key_hash, value, updated_at) values (?, ?, ?, unixepoch()) on conflict(namespace, key_hash) do update set value = excluded.value, updated_at = excluded.updated_at",
    on: conn,
    with: [
      sqlight.text(namespace),
      sqlight.text(key_hash),
      sqlight.text(value),
    ],
    expecting: string_value_decoder(),
  )
  Nil
}

fn with_cache_connection(default: a, f: fn(sqlight.Connection) -> a) -> a {
  case sqlight.open(cache_db_uri()) {
    Ok(conn) -> {
      case ensure_schema(conn) {
        Ok(Nil) -> {
          let output = f(conn)
          let _ = sqlight.close(conn)
          output
        }
        Error(_) -> {
          let _ = sqlight.close(conn)
          default
        }
      }
    }
    Error(_) -> default
  }
}

fn ensure_schema(conn: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  sqlight.exec(
    "create table if not exists adapter_cache (namespace text not null, key_hash text not null, value text not null, updated_at integer not null, primary key(namespace, key_hash))",
    on: conn,
  )
}

fn string_value_decoder() -> decode.Decoder(String) {
  use value <- decode.field(0, decode.string)
  decode.success(value)
}

pub fn cache_db_uri() -> String {
  "file:rememberthename_adapter_cache.sqlite3"
}
