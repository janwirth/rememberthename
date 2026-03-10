import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/list
import gleam/result
import adapters/spotify/live_expander as spotify_live_expander
import mist

@external(erlang, "spotify_oauth_http", "open_url")
fn open_url(url: String) -> String

@external(erlang, "spotify_oauth_http", "redeem_code")
fn redeem_code(
  client_id: String,
  client_secret: String,
  redirect_uri: String,
  code: String,
) -> String

@external(erlang, "spotify_oauth_http", "write_file")
fn write_file(path: String, contents: String) -> String

pub fn main() {
  let client_id = spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_ID")
  let client_secret = spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_SECRET")
  assert client_id != ""
  assert client_secret != ""
  assert client_id != client_secret

  let redirect_uri = "https://127.0.0.1:8080/spotify-oauth-success"
  let code_file = ".spotify_oauth_code.txt"
  let session_file = ".spotify_oauth_session.json"

  let authorize_url =
    "https://accounts.spotify.com/authorize?client_id="
    <> client_id
    <> "&response_type=code&redirect_uri=https%3A%2F%2F127.0.0.1%3A8080%2Fspotify-oauth-success&scope=playlist-read-private%20playlist-read-collaborative%20user-library-read&show_dialog=true"

  io.println("[spotify-oauth] Open:")
  io.println(authorize_url)
  let _ = open_url(authorize_url)
  io.println("[spotify-oauth] Waiting for callback on 127.0.0.1:8080 ...")
  let handler = make_handler(client_id, client_secret, redirect_uri, code_file, session_file)
  let assert Ok(_) =
    handler
    |> mist.new
    |> mist.bind("127.0.0.1")
    |> mist.port(8080)
    |> mist.start
  process.sleep_forever()
}

fn make_handler(
  client_id: String,
  client_secret: String,
  redirect_uri: String,
  code_file: String,
  session_file: String,
) {
  fn(req: request.Request(mist.Connection)) -> response.Response(mist.ResponseData) {
    let query = request.get_query(req) |> result.unwrap([])
    let code = list.key_find(query, "code") |> result.unwrap("")
    case code == "" {
      True ->
        response.new(400)
        |> response.set_body(mist.Bytes(bytes_tree.from_string("Missing code query param")))
      False -> {
        let _ = write_file(code_file, code)
        let token_json = redeem_code(client_id, client_secret, redirect_uri, code)
        let _ = write_file(session_file, token_json)
        io.println("[spotify-oauth] OAuth complete. Code and token files updated.")
        io.println("[spotify-oauth] You can close the server when done.")
        response.new(200)
        |> response.set_body(
          mist.Bytes(
            bytes_tree.from_string(
              "Spotify OAuth success. Code and token saved. You can close the server.",
            ),
          ),
        )
      }
    }
  }
}
