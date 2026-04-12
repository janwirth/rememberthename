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

import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/list
import sqlight

/// Stable 32-bit FNV-1a over UTF-8 bytes (replaces `erlang:phash2`; invalidates old cache rows).
fn phash(value: String) -> String {
  let bits = bit_array.from_string(value)
  let h = fnv1a_u32_loop(bits, 0, 2_166_136_261)
  int.to_string(int.bitwise_and(h, 4_294_967_295))
}

const fnv_prime: Int = 16_777_619

const fnv_mask: Int = 4_294_967_295

fn fnv1a_u32_loop(bits: BitArray, offset: Int, hash: Int) -> Int {
  let len = bit_array.byte_size(bits)
  case offset >= len {
    True -> int.bitwise_and(hash, fnv_mask)
    False ->
      case bit_array.slice(bits, offset, 1) {
        Ok(<<b>>) -> {
          let x = int.bitwise_and(int.bitwise_exclusive_or(hash, b), fnv_mask)
          let x = int.bitwise_and(int.multiply(x, fnv_prime), fnv_mask)
          fnv1a_u32_loop(bits, offset + 1, x)
        }
        _ -> int.bitwise_and(hash, fnv_mask)
      }
  }
}

pub type CacheMode {
  CacheUpsert
  CacheIgnore
  CacheOverride
  CacheReadOnly
}

/// Pair is `(cache_hits, cache_fetches)` for this call: hit = value from DB without
/// running `fetch`; fetch = `fetch` closure ran (network / live read).
pub fn merge_rollups(a: #(Int, Int), b: #(Int, Int)) -> #(Int, Int) {
  let #(ha, fa) = a
  let #(hb, fb) = b
  #(ha + hb, fa + fb)
}

pub fn read_or_fetch(
  namespace: String,
  key: String,
  cache_mode: CacheMode,
  fetch: fn() -> String,
) -> #(String, #(Int, Int)) {
  let key_hash = phash(key)
  case cache_mode {
    CacheIgnore -> #(fetch(), #(0, 1))
    CacheOverride -> compute_and_store(namespace, key_hash, fetch)
    CacheReadOnly -> readonly_result(namespace, key_hash)
    CacheUpsert -> upsert_mode(namespace, key_hash, fetch)
  }
}

fn readonly_result(namespace: String, key_hash: String) -> #(String, #(Int, Int)) {
  let v = read_cached(namespace, key_hash)
  case v != "" {
    True -> #(v, #(1, 0))
    False -> #("", #(0, 0))
  }
}

fn upsert_mode(
  namespace: String,
  key_hash: String,
  fetch: fn() -> String,
) -> #(String, #(Int, Int)) {
  case read_cached(namespace, key_hash) {
    "" -> compute_and_store(namespace, key_hash, fetch)
    cached -> #(cached, #(1, 0))
  }
}

fn compute_and_store(
  namespace: String,
  key_hash: String,
  fetch: fn() -> String,
) -> #(String, #(Int, Int)) {
  let value = fetch()
  case value != "" {
    True -> {
      let _ = write_cached(namespace, key_hash, value)
      #(value, #(0, 1))
    }
    False -> #("", #(0, 1))
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

/// Insert or replace a cache row so `CacheReadOnly` / `CacheUpsert` can hit without network (tests).
pub fn seed_adapter_cache(namespace: String, cache_key: String, value: String) -> Nil {
  write_cached(namespace, phash(cache_key), value)
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
