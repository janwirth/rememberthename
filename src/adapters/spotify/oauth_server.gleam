import gleam/bytes_tree
import gleam/erlang/process
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/list
import gleam/result
import simplifile
import adapters/spotify/live_expander as spotify_live_expander
import mist

fn open_url(url: String) -> Nil {
  io.println("[spotify-oauth] Open manually in your browser:")
  io.println(url)
}

pub fn main() {
  let client_id = spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_ID")
  let client_secret = spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_SECRET")
  let cert_file = spotify_live_expander.read_env_value(".env", "SPOTIFY_OAUTH_CERT_FILE")
  let key_file = spotify_live_expander.read_env_value(".env", "SPOTIFY_OAUTH_KEY_FILE")
  assert client_id != ""
  assert client_secret != ""
  assert client_id != client_secret
  assert cert_file != ""
  assert key_file != ""

  let redirect_uri = "https://127.0.0.1:8080/spotify-oauth-success"
  let code_file = ".spotify_oauth_code.txt"
  let session_file = ".spotify_oauth_session.json"

  let authorize_url =
    "https://accounts.spotify.com/authorize?client_id="
    <> client_id
    <> "&response_type=code&redirect_uri=https%3A%2F%2F127.0.0.1%3A8080%2Fspotify-oauth-success&scope=playlist-read-private%20playlist-read-collaborative%20user-library-read&show_dialog=true"

  io.println("[spotify-oauth] Open:")
  io.println(authorize_url)
  open_url(authorize_url)
  io.println("[spotify-oauth] Waiting for callback on 127.0.0.1:8080 ...")
  let handler = make_handler(client_id, client_secret, redirect_uri, code_file, session_file)
  let assert Ok(_) =
    handler
    |> mist.new
    |> mist.bind("127.0.0.1")
    |> mist.port(8080)
    |> mist.with_tls(certfile: cert_file, keyfile: key_file)
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
        let _ = simplifile.write(code, to: code_file)
        let token_json = redeem_code(client_id, client_secret, redirect_uri, code)
        let _ = simplifile.write(token_json, to: session_file)
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

fn redeem_code(
  client_id: String,
  client_secret: String,
  redirect_uri: String,
  code: String,
) -> String {
  let body =
    "grant_type=authorization_code&code="
    <> code
    <> "&redirect_uri="
    <> redirect_uri
    <> "&client_id="
    <> client_id
    <> "&client_secret="
    <> client_secret
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host("accounts.spotify.com")
    |> request.set_method(http.Post)
    |> request.set_path("/api/token")
    |> request.set_header("content-type", "application/x-www-form-urlencoded")
    |> request.set_body(body)
  case hackney.send(req) {
    Ok(res) -> res.body
    Error(_) -> ""
  }
}
