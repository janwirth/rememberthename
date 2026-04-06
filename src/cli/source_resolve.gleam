//// Limited resolve for validation / interactive UI: `SourceRoot` + depth + item cap.

import adapters/api_keys
import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/normalized_source as tuna_normalized_source
import adapters/youtube/live_expander as youtube_live_expander
import cli/resolve_adapter
import gleam/io
import gleam/option.{None, Some}
import source_root

pub fn resolve_limited(
  root: source_root.SourceRoot,
  depth: core.DepthMode,
  source_limit: Int,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let r = source_root.with_depth(root, depth)
  case r {
    source_root.BandcampRoot(url, d, timing) -> {
      let source_root.SourceTimingSpec(max_concurrency, requests_per_second) =
        timing
      let queue_policy =
        resolve_adapter.queue_policy_for_cache_mode(
          cache_mode,
          max_concurrency,
          requests_per_second,
        )
      let profile = bandcamp_live_expander.bandcamp_profile(url)
      bandcamp_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        d,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
    source_root.SoundcloudRoot(ep, d, timing) -> {
      let source_root.SourceTimingSpec(max_concurrency, requests_per_second) =
        timing
      let queue_policy =
        resolve_adapter.queue_policy_for_cache_mode(
          cache_mode,
          max_concurrency,
          requests_per_second,
        )
      let profile = soundcloud_live_expander.soundcloud_profile(ep)
      soundcloud_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        d,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
    source_root.SpotifyRoot(creds, d) -> {
      let queue_policy =
        resolve_adapter.queue_policy_for_cache_mode(cache_mode, 3, 3)
      case
        api_keys.require_spotify_credentials(api_keys.ApiKeys(
          spotify: Some(creds),
          google_cloud: None,
        ))
      {
        Error(_) ->
          core.ResolveResult(items: [], lists: [], unresolved: [])
        Ok(spotify_creds) -> {
          let config = spotify_live_expander.spotify_config(spotify_creds)
          let profile =
            spotify_live_expander.spotify_user(
              "https://open.spotify.com/user/liked",
            )
          spotify_live_expander.resolve_profile_with_debug_limited_timed(
            profile,
            d,
            config,
            cache_mode,
            source_limit,
            queue_policy,
            on_debug,
            fn(_) { Nil },
          )
        }
      }
    }
    source_root.YoutubeRoot(playlist_url, api_key) -> {
      let queue_policy =
        resolve_adapter.queue_policy_for_cache_mode(cache_mode, 3, 3)
      let keys =
        api_keys.ApiKeys(spotify: None, google_cloud: Some(api_key))
      let profile = youtube_live_expander.youtube_playlist(playlist_url)
      case
        youtube_live_expander.resolve_profile_with_debug_limited_timed(
          profile,
          depth,
          cache_mode,
          keys,
          source_limit,
          queue_policy,
          on_debug,
          fn(_) { Nil },
        )
      {
        Ok(result) -> result
        Error(err) -> {
          io.println(api_keys.format_resolve_adapter_error(err))
          core.ResolveResult(items: [], lists: [], unresolved: [])
        }
      }
    }
    source_root.TunaRoot ->
      tuna_normalized_source.resolve(depth, cache_mode, on_debug)
  }
}
