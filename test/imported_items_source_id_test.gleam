import adapters/api_keys
import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/normalized_source as tuna_normalized_source
import adapters/youtube/live_expander as youtube_live_expander
import cli/api_credentials
import cli/spotify_credentials
import gleam/list
import sources
import test_env

pub fn every_imported_item_has_valid_source_id_constructor_ok_test() {
  case test_env.run_live_perf_tests() {
    False -> Nil
    True -> {
      let all_items = all_imported_items()
      assert all_items != []
      assert list.all(all_items, fn(item) { item_source_id_ok(item) })
    }
  }
}

fn all_imported_items() -> List(core.UnifiedItem) {
  let bandcamp_items =
    resolve_bandcamp_all()
    |> result_items
  let soundcloud_items =
    resolve_soundcloud_all()
    |> result_items
  let spotify_items =
    resolve_spotify_all()
    |> result_items
  let youtube_items =
    resolve_youtube_all()
    |> result_items
  let tuna_items =
    tuna_normalized_source.resolve(core.All, cache.CacheUpsert, fn(_) { Nil })
    |> result_items
  []
  |> list.append(bandcamp_items)
  |> list.append(soundcloud_items)
  |> list.append(spotify_items)
  |> list.append(youtube_items)
  |> list.append(tuna_items)
}

fn resolve_bandcamp_all() -> core.ResolveResult {
  let source = sources.bandcamp()
  let profile =
    bandcamp_live_expander.bandcamp_profile(sources.entry_point(source))
  bandcamp_live_expander.resolve_profile(profile, core.All, cache.CacheUpsert)
}

fn resolve_soundcloud_all() -> core.ResolveResult {
  let source = sources.soundcloud()
  let profile =
    soundcloud_live_expander.soundcloud_profile(sources.entry_point(source))
  soundcloud_live_expander.resolve_profile(profile, core.All, cache.CacheUpsert)
}

fn resolve_spotify_all() -> core.ResolveResult {
  let source = sources.spotify()
  let session = ".spotify_oauth_session.json"
  let access_token = spotify_credentials.read_access_token_file(session)
  assert access_token != ""
  let creds =
    api_keys.SpotifyCredentials(
      access_token: access_token,
      refresh_token: spotify_credentials.read_refresh_token_file(session),
      client_id: spotify_credentials.read_env_value(
        ".env",
        "SPOTIFY_CLIENT_ID",
      ),
      client_secret: spotify_credentials.read_env_value(
        ".env",
        "SPOTIFY_CLIENT_SECRET",
      ),
      redirect_uri: "https://127.0.0.1:8080/spotify-oauth-success",
    )
  let config = spotify_live_expander.spotify_config(creds)
  let profile = spotify_live_expander.spotify_user(sources.entry_point(source))
  spotify_live_expander.resolve_profile(
    profile,
    core.All,
    config,
    cache.CacheUpsert,
  )
}

fn resolve_youtube_all() -> core.ResolveResult {
  let source = sources.youtube()
  let profile =
    youtube_live_expander.youtube_playlist(sources.entry_point(source))
  let assert Ok(result) =
    youtube_live_expander.resolve_profile(
      profile,
      core.All,
      cache.CacheUpsert,
      api_credentials.load_api_keys(),
    )
  result
}

fn result_items(result: core.ResolveResult) -> List(core.UnifiedItem) {
  let core.ResolveResult(items, _, _) = result
  items
}

fn item_source_id_ok(item: core.UnifiedItem) -> Bool {
  let core.UnifiedItem(_, title, artist, service, _, source_id, _, _) = item
  case core.track_item(service, source_id, title, artist, "") {
    Ok(_) -> True
    Error(_) -> False
  }
}
