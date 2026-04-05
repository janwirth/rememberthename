//// Manual Spotify OAuth: print authorize URL, then exchange pasted `code` for session JSON.

import adapters/spotify/oauth_flow
import cli/config_paths
import cli/spotify_credentials
import cli/terminal
import gleam/io
import gleam/list
import gleam/string
import simplifile

pub fn oauth_start() -> Nil {
  case spotify_credentials.first_spotify_oauth_env_bundle() {
    Error(Nil) ->
      io.println(
        terminal.color(
          "[spotify-oauth] No .env with SPOTIFY_CLIENT_ID found.",
          terminal.ansi_red(),
        ),
      )
    Ok(#(_, env_file)) -> {
      let client_id =
        spotify_credentials.read_env_value(env_file, "SPOTIFY_CLIENT_ID")
        |> string.trim
      let redirect = spotify_credentials.spotify_redirect_uri(env_file)
      io.println(
        terminal.color(
          "[spotify-oauth] Open this URL, approve access, then copy the `code` from the redirect URL (address bar):",
          terminal.ansi_yellow(),
        ),
      )
      io.println(oauth_flow.authorize_url(client_id, redirect))
      io.println("")
      io.println(
        terminal.color(
          "Then: gleam run -m cli -- spotify-oauth-exchange \"<code-or-full-url>\"",
          terminal.ansi_bright_cyan(),
        ),
      )
    }
  }
}

pub fn oauth_exchange(code_args: List(String)) -> Nil {
  case code_args |> list.filter(fn(s) { string.trim(s) != "" }) {
    [] ->
      io.println(
        terminal.color(
          "[spotify-oauth] Usage: spotify-oauth-exchange <code>",
          terminal.ansi_red(),
        ),
      )
    parts -> {
      let raw = string.join(parts, " ")
      let code = oauth_flow.normalize_pasted_code(raw)
      case code == "" {
        True ->
          io.println(
            terminal.color("[spotify-oauth] Empty code.", terminal.ansi_red()),
          )
        False -> do_exchange(code)
      }
    }
  }
}

fn do_exchange(code: String) -> Nil {
  case spotify_credentials.first_spotify_oauth_env_bundle() {
    Error(Nil) ->
      io.println(
        terminal.color(
          "[spotify-oauth] No .env with SPOTIFY_CLIENT_ID found.",
          terminal.ansi_red(),
        ),
      )
    Ok(#(root, env_file)) -> {
      let client_id =
        spotify_credentials.read_env_value(env_file, "SPOTIFY_CLIENT_ID")
        |> string.trim
      let client_secret =
        spotify_credentials.read_env_value(env_file, "SPOTIFY_CLIENT_SECRET")
        |> string.trim
      let redirect = spotify_credentials.spotify_redirect_uri(env_file)
      let session_file =
        config_paths.join_under(root, ".spotify_oauth_session.json")
      case client_id == "" || client_secret == "" {
        True ->
          io.println(
            terminal.color(
              "[spotify-oauth] Missing SPOTIFY_CLIENT_ID or SPOTIFY_CLIENT_SECRET.",
              terminal.ansi_red(),
            ),
          )
        False -> {
          let body =
            oauth_flow.exchange_authorization_code(
              client_id,
              client_secret,
              redirect,
              code,
            )
          case string.contains(body, "\"access_token\"") {
            False -> {
              io.println(
                terminal.color(
                  "[spotify-oauth] Token exchange failed. Response:",
                  terminal.ansi_red(),
                ),
              )
              io.println(body)
            }
            True -> {
              case simplifile.write(body, to: session_file) {
                Ok(_) -> {
                  io.println(
                    terminal.color(
                      "[spotify-oauth] Wrote session to "
                        <> session_file,
                      terminal.ansi_green(),
                    ),
                  )
                }
                Error(_) ->
                  io.println(
                    terminal.color(
                      "[spotify-oauth] Could not write "
                        <> session_file,
                      terminal.ansi_red(),
                    ),
                  )
              }
            }
          }
        }
      }
    }
  }
}
