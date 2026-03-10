import gleam/list
import adapters/core
import adapters/bandcamp/live_expander as bandcamp_live_expander

pub fn bandcamp_depth_1_fetches_initial_items_test() {
  let profile = bandcamp_live_expander.bandcamp_profile("https://bandcamp.com/janwirth")

  let result = bandcamp_live_expander.resolve_profile(profile, core.Depth1)
  let core.ResolveResult(items, lists, unresolved) = result

  assert items != []
  assert lists == []
  assert unresolved == []
}

pub fn bandcamp_depths_keep_increasing_test() {
  let profile = bandcamp_live_expander.bandcamp_profile("https://bandcamp.com/janwirth")

  let core.ResolveResult(items_3, _, _) =
    bandcamp_live_expander.resolve_profile(profile, core.Depth3)
  let core.ResolveResult(items_10, _, _) =
    bandcamp_live_expander.resolve_profile(profile, core.Depth10)
  let core.ResolveResult(items_20, _, _) =
    bandcamp_live_expander.resolve_profile(profile, core.Depth20)
  let core.ResolveResult(items_all, _, unresolved_all) =
    bandcamp_live_expander.resolve_profile(profile, core.All)

  assert list.length(items_10) > list.length(items_3)
  assert list.length(items_20) > list.length(items_10)
  assert list.length(items_all) >= list.length(items_20)
  assert list.length(items_all) >= 700
  assert unresolved_all == []
}
