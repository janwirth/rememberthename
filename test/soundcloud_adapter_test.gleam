import gleam/list
import gleam/string
import soundcloud_adapter
import soundcloud_live_expander

pub fn live_depth_1_includes_shallow_spec_track_test() {
  let payload = soundcloud_live_expander.fetch_likes_payload("https://soundcloud.com/tungstenselects")
  assert payload != ""

  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/tungstenselects",
    )
  let result =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth1, soundcloud_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 10
  assert contains_title(items, "A Horse with no Name (Edit)")
  assert lists == []
  assert unresolved == []
}

pub fn live_depth_2_includes_deeper_spec_track_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/tungstenselects",
    )
  let result =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth2, soundcloud_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items, _lists, unresolved) = result

  assert list.length(items) >= 30
  assert contains_title_fragment(items, "Premiere: KAIPE - Batie")
  assert unresolved == []
}

pub fn live_depth_3_includes_spec_list_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/tungstenselects",
    )
  let result =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth3, soundcloud_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert contains_list_title(lists, "Mahal")
  assert contains_any_track_id(lists, "Glass Beams")
  assert items != []
  assert unresolved == []
}

pub fn live_all_matches_depth_3_for_current_live_graph_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/tungstenselects",
    )
  let result =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.All, soundcloud_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert contains_list_title(lists, "Mahal")
  assert contains_any_track_id(lists, "Glass Beams")
  assert items != []
  assert unresolved == []
}

pub fn live_depth_10_matches_all_for_current_live_graph_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/tungstenselects",
    )

  let result_10 =
    soundcloud_adapter.resolve_profile(
      profile,
      soundcloud_adapter.Depth10,
      soundcloud_live_expander.expand,
    )
  let result_all =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.All, soundcloud_live_expander.expand)

  let soundcloud_adapter.ResolveResult(items_10, lists_10, unresolved_10) = result_10
  let soundcloud_adapter.ResolveResult(items_all, lists_all, unresolved_all) = result_all

  assert list.length(items_10) >= 30
  assert list.length(items_10) == list.length(items_all)
  assert list.length(lists_10) == list.length(lists_all)
  assert unresolved_10 == unresolved_all
}

pub fn live_all_full_recursion_collects_expected_shape_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/tungstenselects",
    )

  let result =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.All, soundcloud_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 40
  assert contains_title(items, "A Horse with no Name (Edit)")
  assert contains_title_fragment(items, "Premiere: KAIPE - Batie")
  assert contains_list_title(lists, "Mahal")
  assert contains_any_track_id(lists, "Glass Beams")
  assert unresolved == []
}

fn contains_title(items: List(soundcloud_adapter.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let soundcloud_adapter.UnifiedItem(_, title, _, _, _, _) = item
    title == wanted
  })
}

fn contains_title_fragment(items: List(soundcloud_adapter.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let soundcloud_adapter.UnifiedItem(_, title, _, _, _, _) = item
    string.contains(title, wanted)
  })
}

fn contains_list_title(lists: List(soundcloud_adapter.UnifiedCollection), wanted: String) -> Bool {
  list.any(lists, fn(collection) {
    let soundcloud_adapter.UnifiedCollection(_, title, _, _, _, _, _) = collection
    title == wanted
  })
}

fn contains_any_track_id(
  lists: List(soundcloud_adapter.UnifiedCollection),
  wanted: String,
) -> Bool {
  list.any(lists, fn(collection) {
    let soundcloud_adapter.UnifiedCollection(_, _, track_ids, _, _, _, _) = collection
    list.any(track_ids, fn(track_id) { track_id == wanted })
  })
}
