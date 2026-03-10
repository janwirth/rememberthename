pub type SourceAssertSpec {
  SourceAssertSpec(
    min_depth_1_items: Int,
    min_full_items: Int,
    first_items_to_preserve: Int,
    anchor_fragments: List(String),
    required_full_fragments: List(String),
  )
}

pub type SourceSpec {
  SourceSpec(
    key: String,
    name: String,
    entry_point: String,
    assert_spec: SourceAssertSpec,
  )
}

pub fn all() -> List(SourceSpec) {
  [bandcamp(), soundcloud(), spotify(), youtube()]
}

pub fn bandcamp() -> SourceSpec {
  SourceSpec(
    key: "bandcamp",
    name: "Bandcamp",
    entry_point: "https://bandcamp.com/janwirth",
    assert_spec:
      SourceAssertSpec(
        min_depth_1_items: 1,
        min_full_items: 700,
        first_items_to_preserve: 3,
        anchor_fragments: ["Spore Spreader"],
        required_full_fragments: [
          "Badlands",
          "Dimebag",
          "Redshift 7",
          "World, Hold On",
          "Buttercup",
          "Ghost Radio",
        ],
      ),
  )
}

pub fn soundcloud() -> SourceSpec {
  SourceSpec(
    key: "soundcloud",
    name: "Soundcloud",
    entry_point: "https://soundcloud.com/tungstenselects",
    assert_spec:
      SourceAssertSpec(
        min_depth_1_items: 10,
        min_full_items: 1000,
        first_items_to_preserve: 3,
        anchor_fragments: [
          "A Horse with no Name (Edit)",
          "Nyxtape: Vol.12 - Harley D",
          "PREMIERE| Rebecca Delle Piane - Genomica [FIDESX4]",
          "Premiere: KAIPE - Batie",
        ],
        required_full_fragments: [],
      ),
  )
}

pub fn spotify() -> SourceSpec {
  SourceSpec(
    key: "spotify",
    name: "Spotify",
    entry_point: "https://open.spotify.com/user/franzskuffka",
    assert_spec:
      SourceAssertSpec(
        min_depth_1_items: 50,
        min_full_items: 1000,
        first_items_to_preserve: 3,
        anchor_fragments: ["Blask", "SOLD MY SOUL"],
        required_full_fragments: [],
      ),
  )
}

pub fn youtube() -> SourceSpec {
  SourceSpec(
    key: "youtube",
    name: "Youtube",
    entry_point: "https://www.youtube.com/playlist?list=PLK7cxKkqBmwmpPoWznuEF-xEljswMRR3V",
    assert_spec:
      SourceAssertSpec(
        min_depth_1_items: 5,
        min_full_items: 1000,
        first_items_to_preserve: 3,
        anchor_fragments: [
          "Angine de poitrine - Sahardnieh",
          "Nimo - BITTER",
          "Vengaboys - Up & Down",
          "Dendemann - Wo ich wech bin",
          "BHZ - SCHLIESSE DIE AUGEN",
        ],
        required_full_fragments: [],
      ),
  )
}
