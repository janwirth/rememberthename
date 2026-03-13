//// Adapter cache helper with explicit runtime modes.
////
//// Contract used by all live expanders:
//// - deterministic cache key: `namespace + phash(key)`
//// - file-backed cache under `/tmp`
//// - empty fetch results are not persisted
////
//// Cache modes:
//// - `CacheUpsert`: read existing cache, fetch+store on miss/empty
//// - `CacheIgnore`: bypass cache, always fetch live
//// - `CacheOverride`: always fetch live and overwrite cache
//// - `CacheReadOnly`: read cache only, never fetch on miss/empty

import simplifile

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
  case cache_mode {
    CacheIgnore -> fetch()
    CacheOverride -> {
      let path = cache_path(namespace, key)
      compute_and_store(path, fetch)
    }
    CacheReadOnly -> {
      let path = cache_path(namespace, key)
      case simplifile.read(from: path) {
        Ok(cached) -> cached
        Error(_) -> ""
      }
    }
    CacheUpsert -> {
      let path = cache_path(namespace, key)
      case simplifile.read(from: path) {
        Ok(cached) ->
          case cached != "" {
            True -> cached
            False -> compute_and_store(path, fetch)
          }
        Error(_) -> compute_and_store(path, fetch)
      }
    }
  }
}

fn compute_and_store(path: String, fetch: fn() -> String) -> String {
  let value = fetch()
  case value != "" {
    True -> {
      let _ = simplifile.write(value, to: path)
      value
    }
    False -> ""
  }
}

fn cache_path(namespace: String, key: String) -> String {
  "/tmp/rememberthename_adapter_cache_"
  <> namespace
  <> "_"
  <> phash(key)
  <> ".txt"
}
