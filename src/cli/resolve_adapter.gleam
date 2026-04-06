import adapters/api_keys
import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/normalized_source as tuna_normalized_source
import adapters/youtube/live_expander as youtube_live_expander
import cli/config_paths
import cli/spotify_credentials
import source_root

/// Short string for logging cache behavior.
pub fn cache_mode_text(value: cache.CacheMode) -> String {
  case value {
    cache.CacheUpsert -> "upsert"
    cache.CacheIgnore -> "ignore"
    cache.CacheOverride -> "override"
    cache.CacheReadOnly -> "readonly"
  }
}

/// Relaxes rate limits when hitting cache only so cold-cache policy applies to network runs.
pub fn queue_policy_for_cache_mode(
  cache_mode: cache.CacheMode,
  max_concurrency: Int,
  requests_per_second: Int,
) -> core.QueuePolicy {
  case cache_mode {
    // Cache-only runs should not pay network rate-limit sleeps.
    cache.CacheReadOnly ->
      core.QueuePolicy(max_concurrency: 1000, requests_per_second: 10000)
    _ ->
      core.QueuePolicy(
        max_concurrency: max_concurrency,
        requests_per_second: requests_per_second,
      )
  }
}

/// Dispatches to Bandcamp, SoundCloud, Spotify, Tuna, or YouTube expander from `key`.
pub fn resolve_source(
  key: String,
  entry_point: String,
  depth: core.DepthMode,
  source_limit: Int,
  timing_spec: source_root.SourceTimingSpec,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
  on_progress: fn(core.ResolveProgress) -> Nil,
  keys: api_keys.ApiKeys,
) -> Result(core.ResolveResult, api_keys.ResolveAdapterError) {
  let source_root.SourceTimingSpec(max_concurrency, requests_per_second) =
    timing_spec
  let queue_policy = queue_policy_for_cache_mode(
    cache_mode,
    max_concurrency,
    requests_per_second,
  )
  case key {
    "bandcamp" -> {
      let profile = bandcamp_live_expander.bandcamp_profile(entry_point)
      Ok(
        bandcamp_live_expander.resolve_profile_with_debug_limited_timed(
          profile,
          depth,
          cache_mode,
          source_limit,
          queue_policy,
          on_debug,
          on_progress,
        ),
      )
    }
    "soundcloud" -> {
      let profile = soundcloud_live_expander.soundcloud_profile(entry_point)
      Ok(
        soundcloud_live_expander.resolve_profile_with_debug_limited_timed(
          profile,
          depth,
          cache_mode,
          source_limit,
          queue_policy,
          on_debug,
          on_progress,
        ),
      )
    }
    "spotify" -> {
      let spotify_root = config_paths.spotify_config_root()
      let session_file =
        config_paths.join_under(spotify_root, ".spotify_oauth_session.json")
      let env_file = config_paths.join_under(spotify_root, ".env")
      let redirect = spotify_credentials.spotify_redirect_uri(env_file)
      let keys_with_spotify =
        spotify_credentials.with_spotify_from_disk(
          keys,
          session_file,
          env_file,
          redirect,
        )
      case api_keys.require_spotify_credentials(keys_with_spotify) {
        Error(e) -> Error(e)
        Ok(creds) -> {
          let config = spotify_live_expander.spotify_config(creds)
          let profile = spotify_live_expander.spotify_user(entry_point)
          Ok(
            spotify_live_expander.resolve_profile_with_debug_limited_timed(
              profile,
              depth,
              config,
              cache_mode,
              source_limit,
              queue_policy,
              on_debug,
              on_progress,
            ),
          )
        }
      }
    }
    "tuna" -> Ok(tuna_normalized_source.resolve(depth, cache_mode, on_debug))
    _ -> {
      let profile = youtube_live_expander.youtube_playlist(entry_point)
      youtube_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        keys,
        source_limit,
        queue_policy,
        on_debug,
        on_progress,
      )
    }
  }
}
