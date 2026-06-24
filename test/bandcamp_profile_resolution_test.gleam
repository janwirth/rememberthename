import adapters/bandcamp/live_expander as bandcamp
import adapters/cache
import adapters/core
import gleam/list
import gleam/string
import gleeunit/should
import gleam/option

const profile_url = "https://bandcamp.com/rntestfan"

fn collection_post_body(fan_id: String, token: String) -> String {
  "{\"fan_id\":"
  <> fan_id
  <> ",\"older_than_token\":\""
  <> token
  <> "\",\"count\":50}"
}

// data-blob attribute uses &quot; for internal quotes; first literal " closes the attribute.
// data-token on the first <li> provides the pagination token for the fancollection API.
fn seed_profile_html(fan_id: String, col_tok: String, wish_tok: String) -> String {
  "<div data-blob=\"{&quot;fan_id&quot;:"
  <> fan_id
  <> ",&quot;collection_data&quot;:{&quot;redownload_urls&quot;:{},&quot;last_token&quot;:&quot;"
  <> col_tok
  <> "&quot;},&quot;wishlist_data&quot;:{&quot;last_token&quot;:&quot;"
  <> wish_tok
  <> "&quot;}}\"></div><li data-token=\""
  <> col_tok
  <> "\"></li>"
}

fn seed_collection_items_json() -> String {
  "{\"last_token\":\"\",\"more_available\":false,\"items\":[{\"item_id\":9001,\"item_type\":\"album\",\"item_title\":\"Digi Spa EP\",\"band_name\":\"Artist\",\"item_url\":\"https://digi.bandcamp.com/album/ep\",\"added\":\"\"},{\"item_id\":9100,\"item_type\":\"track\",\"item_title\":\"Loose track\",\"band_name\":\"X\",\"item_url\":\"https://x.bandcamp.com/track/t\",\"added\":\"\"}]}"
}

fn seed_wishlist_items_json() -> String {
  "{\"last_token\":\"\",\"more_available\":false,\"items\":[{\"item_id\":9002,\"item_type\":\"album\",\"item_title\":\"The Frightnrs - Nothing More To Say\",\"band_name\":\"The Frightnrs\",\"item_url\":\"https://frightnrs.bandcamp.com/album/nms\",\"added\":\"\"}]}"
}

fn album_html_digi_spa() -> String {
  "<html><head><meta property=\"og:image\" content=\"https://f4.bcbits.com/img/a0000000000_16.jpg\" /></head><body>\"album_title\":\"Digi Spa EP\",\"trackinfo\":[{\"title\":\"Nord dab\",\"track_id\":5001,\"duration\":180.0,\"artist\":\"Digi\",\"title_link\":\"https://digi.bandcamp.com/track/nord\",\"added\":\"01 Jan 2020 00:00:00 GMT\"}],</body></html>"
}

fn album_html_frightnrs() -> String {
  "<html><body>\"album_title\":\"Nothing More To Say\",\"trackinfo\":[{\"title\":\"All My Tears\",\"track_id\":5002,\"duration\":210.0,\"artist\":\"The Frightnrs\",\"title_link\":\"https://frightnrs.bandcamp.com/track/tears\",\"added\":\"01 Jan 2020 00:00:00 GMT\"}],</body></html>"
}

fn seed_bandcamp_resolution_cache() -> Nil {
  let fan = "4242"
  let col_tok = "coltok"
  let wish_tok = "wishtok"
  let col_url = "https://bandcamp.com/api/fancollection/1/collection_items"
  let wish_url = "https://bandcamp.com/api/fancollection/1/wishlist_items"
  cache.seed_adapter_cache("bandcamp_fetch", profile_url, seed_profile_html(
    fan,
    col_tok,
    wish_tok,
  ))
  cache.seed_adapter_cache(
    "bandcamp_post_json",
    col_url <> "|" <> collection_post_body(fan, col_tok),
    seed_collection_items_json(),
  )
  cache.seed_adapter_cache(
    "bandcamp_post_json",
    wish_url <> "|" <> collection_post_body(fan, wish_tok),
    seed_wishlist_items_json(),
  )
  cache.seed_adapter_cache(
    "bandcamp_fetch",
    "https://digi.bandcamp.com/album/ep",
    album_html_digi_spa(),
  )
  cache.seed_adapter_cache(
    "bandcamp_fetch",
    "https://frightnrs.bandcamp.com/album/nms",
    album_html_frightnrs(),
  )
  Nil
}

fn item_titles(items: List(core.UnifiedItem)) -> List(String) {
  list.map(items, fn(i) {
    let core.UnifiedItem(_, title, _, _, _, _, _, _, _, _, _, _, _, _) = i
    title
  })
}

fn list_nodes(nodes: List(core.AdapterNode)) -> List(core.AdapterNode) {
  list.filter(nodes, fn(n) {
    case n {
      core.ListNode(_) -> True
      _ -> False
    }
  })
}

pub fn bandcamp_purchased_album_collection_and_wishlist_tracks_resolve_test() {
  seed_bandcamp_resolution_cache()
  let result =
    core.resolve_profile_url(profile_url, core.All, fn(node) {
      bandcamp.expand(node, cache.CacheReadOnly)
    })
  let core.ResolveResult(items, lists, unresolved) = result
  unresolved |> should.equal([])

  item_titles(items)
  |> list.any(fn(t) { string.contains(t, "Nord dab") })
  |> should.equal(True)
  // Wishlist is a separate source root; wishlist album tracks do NOT appear from collection URL.
  item_titles(items)
  |> list.any(fn(t) { string.contains(t, "All My Tears") })
  |> should.equal(False)
  // Album-level items must not appear directly — only tracks from album expansion.
  item_titles(items)
  |> list.any(fn(t) { string.contains(t, "Digi Spa EP") })
  |> should.equal(False)

  let purchased =
    list.filter(lists, fn(c) {
      let core.UnifiedCollection(_, _, _, _, service, source_type, _) = c
      service == "bandcamp" && source_type == "collection"
    })
  list.length(purchased) |> should.equal(1)
  let assert Ok(col) = list.first(purchased)
  let core.UnifiedCollection(_, title, track_ids, _, _, _, _) = col
  title |> should.equal("Digi Spa EP")
  let nord =
    list.find(items, fn(i) {
      let core.UnifiedItem(_, t, _, _, _, _, _, _, _, _, _, _, _, _) = i
      string.contains(t, "Nord dab")
    })
  let assert Ok(nord_item) = nord
  let core.UnifiedItem(nord_id, _, _, _, _, _, _, cover, _, _, _, _, _, _) = nord_item
  list.contains(track_ids, nord_id) |> should.equal(True)
  case cover {
    option.Some(cover_url) -> {
      string.starts_with(cover_url, "https://f4.bcbits.com/")
      |> should.equal(True)
    }
    option.None -> {
      assert False
      // should.fail("cover_url should be Some")
    }
  }

  list.any(lists, fn(c) {
    let core.UnifiedCollection(_, title, _, _, _, _, _) = c
    string.contains(title, "Nothing More To Say")
  })
  |> should.equal(False)
}

fn seed_item_cache_html(
  fan_id: String,
  col_tok: String,
  wish_tok: String,
) -> String {
  // data-blob must be a single attribute value; item_cache lives inside the JSON blob.
  "<div data-blob=\"{&quot;fan_id&quot;:"
  <> fan_id
  <> ",&quot;collection_data&quot;:{&quot;last_token&quot;:&quot;"
  <> col_tok
  <> "&quot;},&quot;wishlist_data&quot;:{&quot;last_token&quot;:&quot;"
  <> wish_tok
  <> "&quot;},&quot;item_cache&quot;:{&quot;collection&quot;:{&quot;t9001&quot;:{&quot;item_id&quot;:9001,&quot;item_type&quot;:&quot;track&quot;,&quot;item_title&quot;:&quot;Purchased bootstrap&quot;,&quot;band_name&quot;:&quot;Buyer&quot;,&quot;item_url&quot;:&quot;https://buy.bandcamp.com/track/purchased&quot;,&quot;added&quot;:&quot;&quot;}},&quot;wishlist&quot;:{&quot;a9002&quot;:{&quot;item_id&quot;:9002,&quot;item_type&quot;:&quot;track&quot;,&quot;item_title&quot;:&quot;Wishlist bootstrap&quot;,&quot;band_name&quot;:&quot;Saver&quot;,&quot;item_url&quot;:&quot;https://save.bandcamp.com/track/wishlist&quot;,&quot;added&quot;:&quot;&quot;}},&quot;gifts_given&quot;:{},&quot;hidden&quot;:{},&quot;follower&quot;:{}}}\"</div>"
  // No data-token: empty first_data_token skips the API call, so only item_cache items appear.
}

fn entry_bootstrap_titles(
  profile_url: String,
) -> List(String) {
  cache.seed_adapter_cache(
    "bandcamp_fetch",
    profile_url,
    seed_item_cache_html("4242", "coltok", "wishtok"),
  )
  let r =
    bandcamp.expand(core.ProfileEntry(profile_url), cache.CacheReadOnly)
  item_titles(r.items)
}

pub fn bandcamp_profile_entry_items_use_feed_specific_item_cache_test() {
  let purchases = entry_bootstrap_titles(profile_url)
  let wishlist =
    entry_bootstrap_titles(profile_url <> "/wishlist")

  purchases |> should.equal(["Purchased bootstrap"])
  wishlist |> should.equal(["Wishlist bootstrap"])
}

// Regression: Bandcamp JSON has "track_id" before "title". Old code split on
// "title":" so part N's extract_between("track_id") found track N+1's ID.
// Album 1381157747: track "the essence" has track_id 2989522547. With the bug,
// the preceding track "Broken rib" would steal that ID.
pub fn bandcamp_album_track_ids_not_off_by_one_test() {
  let album_id = "1381157747"
  // JSON field order: track_id BEFORE title — the order that triggered the bug
  let html =
    "<html><head><meta property=\"og:image\" content=\"https://f4.bcbits.com/img/x.jpg\"/></head><body>"
    <> "\"trackinfo\":[{\"track_id\":1111111,\"track_num\":1,\"title\":\"Broken rib\",\"duration\":200.0,\"artist\":\"artist\",\"title_link\":\"https://ex.bandcamp.com/track/broken-rib\",\"added\":\"01 Jan 2020 00:00:00 GMT\"},{\"track_id\":2989522547,\"track_num\":2,\"title\":\"the essence\",\"duration\":180.0,\"artist\":\"artist\",\"title_link\":\"https://ex.bandcamp.com/track/the-essence\",\"added\":\"01 Jan 2020 00:00:00 GMT\"}],"
    <> "</body></html>"
  cache.seed_adapter_cache(
    "bandcamp_fetch",
    "https://ex.bandcamp.com/album/test",
    html,
  )
  let r =
    bandcamp.expand(
      core.ListNode(
        "album|collection|https://ex.bandcamp.com/album/test|"
        <> album_id
        <> "|2020-01-01T00:00:00Z",
      ),
      cache.CacheReadOnly,
    )
  let broken_rib =
    list.find(r.items, fn(i) { i.title == "Broken rib" })
    |> option.from_result
  let the_essence =
    list.find(r.items, fn(i) { i.title == "the essence" })
    |> option.from_result
  // "Broken rib" must NOT have "the essence"'s track_id
  case broken_rib {
    option.Some(item) -> item.source_id |> should.not_equal("2989522547")
    option.None -> should.fail()
  }
  // "the essence" must have its own track_id
  case the_essence {
    option.Some(item) -> item.source_id |> should.equal("2989522547")
    option.None -> should.fail()
  }
}

pub fn bandcamp_collection_page_enqueues_every_album_not_capped_test() {
  let fan = "9999"
  let tok = "pagetok"
  let col_url = "https://bandcamp.com/api/fancollection/1/collection_items"
  let body = collection_post_body(fan, tok)
  let json =
    "{\"last_token\":\"\",\"more_available\":false,\"items\":[{\"item_id\":1,\"item_type\":\"album\",\"item_title\":\"A1\",\"band_name\":\"B\",\"item_url\":\"https://a1.bandcamp.com/album/a\",\"added\":\"\"},{\"item_id\":2,\"item_type\":\"album\",\"item_title\":\"A2\",\"band_name\":\"B\",\"item_url\":\"https://a2.bandcamp.com/album/a\",\"added\":\"\"},{\"item_id\":3,\"item_type\":\"album\",\"item_title\":\"A3\",\"band_name\":\"B\",\"item_url\":\"https://a3.bandcamp.com/album/a\",\"added\":\"\"}]}"
  cache.seed_adapter_cache("bandcamp_post_json", col_url <> "|" <> body, json)
  let r =
    bandcamp.expand(core.CategoryNode("collection|" <> fan <> "|" <> tok), cache.CacheReadOnly)
  list.length(list_nodes(r.next_nodes)) |> should.equal(3)
}
