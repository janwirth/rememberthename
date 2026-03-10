import gleam/list
import gleam/string
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander

pub fn live_depth_1_includes_shallow_spec_track_test() {
  let payload = soundcloud_live_expander.fetch_likes_payload("https://soundcloud.com/tungstenselects")
  assert payload != ""

  let profile = soundcloud_live_expander.soundcloud_profile("https://soundcloud.com/tungstenselects")
  let result =
    soundcloud_live_expander.resolve_profile(profile, core.Depth1)
  let core.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 10
  assert contains_title(items, "A Horse with no Name (Edit)")
  assert lists == []
  assert unresolved == []
}

pub fn live_depth_2_includes_deeper_spec_track_test() {
  let profile = soundcloud_live_expander.soundcloud_profile("https://soundcloud.com/tungstenselects")
  let result =
    soundcloud_live_expander.resolve_profile(profile, core.Depth2)
  let core.ResolveResult(items, _lists, unresolved) = result

  assert list.length(items) >= 30
  assert contains_title_fragment(items, "Premiere: KAIPE - Batie")
  assert unresolved == []
}

pub fn live_depth_3_includes_spec_list_test() {
  let profile = soundcloud_live_expander.soundcloud_profile("https://soundcloud.com/tungstenselects")
  let result =
    soundcloud_live_expander.resolve_profile(profile, core.Depth3)
  let core.ResolveResult(items, _lists, unresolved) = result

  assert list.length(items) > 30
  assert unresolved == []
}

pub fn live_depth_10_is_deeper_than_depth_3_test() {
  let profile = soundcloud_live_expander.soundcloud_profile("https://soundcloud.com/tungstenselects")

  let result_10 =
    soundcloud_live_expander.resolve_profile(profile, core.Depth10)
  let result_3 =
    soundcloud_live_expander.resolve_profile(profile, core.Depth3)

  let core.ResolveResult(items_10, lists_10, unresolved_10) = result_10
  let core.ResolveResult(items_3, lists_3, unresolved_3) = result_3

  assert list.length(items_10) >= 30
  assert list.length(items_10) >= list.length(items_3)
  assert list.length(lists_10) >= list.length(lists_3)
  assert unresolved_10 == unresolved_3
}

pub fn live_depth_20_is_deeper_than_depth_10_test() {
  let profile = soundcloud_live_expander.soundcloud_profile("https://soundcloud.com/tungstenselects")

  let result_10 =
    soundcloud_live_expander.resolve_profile(profile, core.Depth10)
  let result_20 =
    soundcloud_live_expander.resolve_profile(profile, core.Depth20)

  let core.ResolveResult(items_10, _lists_10, unresolved_10) = result_10
  let core.ResolveResult(items_20, _lists_20, unresolved_20) = result_20

  assert list.length(items_20) > list.length(items_10)
  assert unresolved_20 == unresolved_10
}

pub fn live_all_full_recursion_collects_expected_shape_test() {
  let profile = soundcloud_live_expander.soundcloud_profile("https://soundcloud.com/tungstenselects")

  let result =
    soundcloud_live_expander.resolve_profile(profile, core.All)
  let core.ResolveResult(items, _lists, unresolved) = result

  assert list.length(items) >= 40
  assert contains_title(items, "A Horse with no Name (Edit)")
  assert contains_title_fragment(items, "Premiere: KAIPE - Batie")
  assert unresolved == []
}

pub fn live_depths_increase_through_recursive_pages_test() {
  let profile = soundcloud_live_expander.soundcloud_profile("https://soundcloud.com/tungstenselects")

  let core.ResolveResult(items_1, _, _) =
    soundcloud_live_expander.resolve_profile(profile, core.Depth1)
  let core.ResolveResult(items_2, _, _) =
    soundcloud_live_expander.resolve_profile(profile, core.Depth2)
  let core.ResolveResult(items_3, _, _) =
    soundcloud_live_expander.resolve_profile(profile, core.Depth3)

  assert items_1 != []
  assert list.length(items_2) > list.length(items_1)
  assert list.length(items_3) > list.length(items_2)
}

fn contains_title(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _) = item
    title == wanted
  })
}

fn contains_title_fragment(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _) = item
    string.contains(title, wanted)
  })
}

