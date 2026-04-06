import adapters/cache
import fetch_ops
import source_specs
import source_root

pub fn all_sources() {
    source_specs.all()
}

pub fn fetch_source(source_root: source_root.SourceRoot, on_log_line: fn(String) -> Nil) -> Result(fetch_ops.FetchResult, String) {
    fetch_ops.fetch(source_root, cache.CacheUpsert, on_log_line)
}