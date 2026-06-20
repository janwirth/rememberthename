import gleam/list
import gleeunit
import gleeunit/should
import rememberthename

pub fn main() {
  gleeunit.main()
}

pub fn decode_gel_tag_catalog_accepts_null_emoji_test() {
  let raw =
    "[{\"label\": \"Genre/Breakbeat\", \"emoji\": null}, {\"label\": \"genre:house\", \"emoji\": \"🏢\"}]"
  let assert Ok(decoded) = rememberthename.decode_tuna_tag_catalog_from_gel(raw)
  should.equal(list.length(decoded), 2)
  let assert Ok(first) = list.first(decoded)
  let rememberthename.TunaCatalogTag(label:, emoji:, ..) = first
  should.equal(label, "Genre/Breakbeat")
  should.equal(emoji, "")
}

pub fn encode_decode_stored_catalog_roundtrip_test() {
  let tags = [
    rememberthename.TunaCatalogTag(
      export_key: "tag/genre/🏢:house",
      label: "genre:house",
      emoji: "🏢",
    ),
  ]
  let text = rememberthename.encode_tuna_tag_catalog(tags)
  let assert Ok(decoded) = rememberthename.decode_tuna_tag_catalog(text)
  should.equal(decoded, tags)
}
