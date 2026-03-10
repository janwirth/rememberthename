import simplifile

@external(erlang, "cache_hash", "phash")
fn phash(value: String) -> String

pub fn read_or_fetch(
  namespace: String,
  key: String,
  use_cache: Bool,
  fetch: fn() -> String,
) -> String {
  case use_cache {
    False -> fetch()
    True -> {
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
  "/tmp/rememberthename_adapter_cache_" <> namespace <> "_" <> phash(key) <> ".txt"
}
