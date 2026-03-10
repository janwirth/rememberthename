import gleam/list
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

  assert items != []
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

  assert items != []
  assert contains_title(items, "Premiere: KAIPE - Batie")
  assert unresolved == []
}

pub fn live_full_includes_spec_list_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/tungstenselects",
    )
  let result =
    soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Full, soundcloud_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert contains_list_title(lists, "Mahal")
  assert contains_any_track_id(lists, "Glass Beams")
  assert items != []
  assert unresolved == []
}

fn contains_title(items: List(soundcloud_adapter.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let soundcloud_adapter.UnifiedItem(_, title, _, _, _, _) = item
    title == wanted
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
