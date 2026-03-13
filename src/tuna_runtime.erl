-module(tuna_runtime).
-export([tracks_source_ids_json/0]).

tracks_source_ids_json() ->
    try
        Cmd =
            "gel -I tuna -b main query --output-format=json "
            "\"select (for t in default::Track union {"
            " title := t.title,"
            " normalized_title := t.title_any_ascii_fixed,"
            " date_added := <str>t.date_added,"
            " artist := (select t.artist_label limit 1),"
            " tags := (select t.tags { label, emoji } order by .label),"
            " rating := t.rating,"
            " file_path := (select ("
            "   t.dropped_source.path"
            "   ?? t.spotify_download.path"
            "   ?? t.soulseek_download.path"
            "   ?? t.itunes_source.path"
            "   ?? t.integrity_checked_path_audio"
            "   ?? (select t.sources[is default::FileSource].path limit 1)"
            "   ?? (select t.sources[is default::ItunesSource2].path limit 1)"
            " ) limit 1),"
            " spotify_id := (select ("
            "   t.spotify_source.spotify_id"
            "   ?? (select t.sources[is default::SpotifySource].spotify_id limit 1)"
            " ) limit 1),"
            " youtube_id := (select ("
            "   t.youtube_source.youtube_id"
            "   ?? (select t.sources[is default::YoutubeSource].youtube_id limit 1)"
            " ) limit 1),"
            " soundcloud_id := (select ("
            "   <str>t.soundcloud_source.soundcloud_id"
            "   ?? (select <str>t.sources[is default::SoundcloudSource].soundcloud_id limit 1)"
            " ) limit 1),"
            " bandcamp_track_id := (select ("
            "   <str>t.bandcamp_source.bandcamp_track_id"
            "   ?? (select <str>t.sources[is default::BandcampSource].bandcamp_track_id limit 1)"
            " ) limit 1),"
            " itunes_track_id := (select ("
            "   t.itunes_source[is default::ItunesSource2].itunes_track_id"
            "   ?? (select t.sources[is default::ItunesSource2].itunes_track_id limit 1)"
            " ) limit 1),"
            " itunes_persistent_track_id := (select ("
            "   t.itunes_source[is default::ItunesSource2].itunes_persistent_track_id"
            "   ?? (select t.sources[is default::ItunesSource2].itunes_persistent_track_id limit 1)"
            " ) limit 1),"
            " fishbone_source_platform := (select t.fishbone_source.source_platform limit 1),"
            " fishbone_source_id := (select t.fishbone_source.id_on_source_platform limit 1)"
            " });\"",
        unicode:characters_to_binary(os:cmd(Cmd))
    catch
        _:_ -> <<>>
    end.
