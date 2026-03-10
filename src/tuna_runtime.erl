-module(tuna_runtime).
-export([tracks_source_ids_json/0]).

tracks_source_ids_json() ->
    try
        Cmd =
            "gel -I tuna -b main query --output-format=json "
            "\"select (for t in default::Track union {"
            " spotify_id := (select t.spotify_source.spotify_id limit 1),"
            " youtube_id := (select t.youtube_source.youtube_id limit 1),"
            " soundcloud_id := (select <str>t.soundcloud_source.soundcloud_id limit 1),"
            " bandcamp_track_id := (select <str>t.bandcamp_source.bandcamp_track_id limit 1),"
            " dropped_path := (select t.dropped_source.path limit 1),"
            " itunes_track_id := (select t.itunes_source[is default::ItunesSource2].itunes_track_id limit 1),"
            " itunes_persistent_track_id := (select t.itunes_source[is default::ItunesSource2].itunes_persistent_track_id limit 1)"
            " });\"",
        unicode:characters_to_binary(os:cmd(Cmd))
    catch
        _:_ -> <<>>
    end.
