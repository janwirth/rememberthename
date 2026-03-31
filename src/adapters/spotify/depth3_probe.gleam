import adapters/cache
import adapters/core
import adapters/spotify/live_expander as spotify_live_expander
import gleam/int
import gleam/io
import gleam/list

pub fn main() {
  let client_id =
    spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_ID")
  let client_secret =
    spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_SECRET")
  let access_token =
    spotify_live_expander.read_access_token_file(".spotify_oauth_session.json")
  assert client_id != ""
  assert client_secret != ""
  assert access_token != ""

  let config =
    spotify_live_expander.spotify_config(
      access_token: access_token,
      session_file: ".spotify_oauth_session.json",
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: "https://127.0.0.1:8080/spotify-oauth-success",
      scopes: "playlist-read-private playlist-read-collaborative user-library-read",
    )

  let profile =
    spotify_live_expander.spotify_user(
      "https://open.spotify.com/user/franzskuffka",
    )
  let result =
    spotify_live_expander.resolve_profile(
      profile,
      core.Depth3,
      config,
      cache.CacheUpsert,
    )
  let core.ResolveResult(items, lists, unresolved) = result

  io.println("depth=3")
  io.println("items=" <> int.to_string(list.length(items)))
  io.println("lists=" <> int.to_string(list.length(lists)))
  io.println("unresolved=" <> int.to_string(list.length(unresolved)))
  io.println("")
  io.println("lists:")
  print_lists(lists)
  io.println("")
  io.println("items preview:")
  print_item_preview(items)
}

fn print_lists(lists: List(core.UnifiedCollection)) {
  case lists {
    [] -> io.println("  - (none)")
    _ ->
      list.each(lists, fn(collection) {
        let core.UnifiedCollection(id, title, track_ids, _, _, _, _) =
          collection
        io.println(
          "  - "
          <> id
          <> " | "
          <> title
          <> " | tracks="
          <> int.to_string(list.length(track_ids)),
        )
      })
  }
}

fn print_item_preview(items: List(core.UnifiedItem)) {
  let count = list.length(items)
  case count == 0 {
    True -> io.println("  - (none)")
    False ->
      case count > 6 {
        True -> {
          let first = list.take(items, 3)
          let last = list.drop(items, count - 3)
          print_items(first)
          io.println("  ...")
          print_items(last)
        }
        False -> print_items(items)
      }
  }
}

fn print_items(items: List(core.UnifiedItem)) {
  list.each(items, fn(item) {
    let core.UnifiedItem(id, title, artist, _, _, _, _, _) = item
    io.println("  - " <> id <> " | " <> title <> " | " <> artist)
  })
}
