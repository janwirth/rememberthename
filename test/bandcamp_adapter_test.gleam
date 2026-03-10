import gleam/list
import soundcloud_adapter
import bandcamp_live_expander

pub fn bandcamp_depth_1_fetches_initial_items_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "bandcamp",
      source_type: "collection",
      source_id: "https://bandcamp.com/janwirth",
    )

  let result =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth1, bandcamp_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert items != []
  assert lists == []
  assert unresolved == []
}

pub fn bandcamp_depths_keep_increasing_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "bandcamp",
      source_type: "collection",
      source_id: "https://bandcamp.com/janwirth",
    )

  let soundcloud_adapter.ResolveResult(items_3, _, _) =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth3, bandcamp_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items_10, _, _) =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth10, bandcamp_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items_20, _, _) =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth20, bandcamp_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items_all, _, unresolved_all) =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.All, bandcamp_live_expander.expand)

  assert list.length(items_10) > list.length(items_3)
  assert list.length(items_20) > list.length(items_10)
  assert list.length(items_all) >= list.length(items_20)
  assert list.length(items_all) >= 700
  assert unresolved_all == []
}
