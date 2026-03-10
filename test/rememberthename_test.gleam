import spotify_adapter_test

pub fn main() {
  // Manual test selection:
  // Uncomment groups you want to run.

  // bandcamp_adapter_test.live_bandcamp_follows_unified_depth_spec_test()
  // soundcloud_adapter_test.live_soundcloud_follows_unified_depth_spec_test()
  // youtube_adapter_test.live_youtube_follows_unified_depth_spec_test()

  // Spotify-only run
  spotify_adapter_test.live_spotify_user_follows_unified_depth_spec_test()
}
