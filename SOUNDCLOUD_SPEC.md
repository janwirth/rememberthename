# rememberthename - SoundCloud Spec (Factored)

## Reference
Input: https://soundcloud.com/tungstenselects
Track


shallow
 A Horse with no Name (Edit) Kolter

deeper:
Premiere: KAIPE - Batie
links:

full:
List:
Mahal
Glass Beams
+ 700 more items



## 1) Scope

Supported SoundCloud input:
- profile URLs

Out of scope for SoundCloud input:
- Individual track URLs (`/artist/track`).
- Search.
- Any untestable behavior.

## 2) Source Contract

- `service`: `soundcloud`
- `source_type`: `collection` for profile roots, `item | collection` for resolved entries
- contract type: `SourceIdentity` from `SPEC.md`

Accepted profile shape:
- `SourceIdentity { service: soundcloud, source_type: collection, source_id: <profile_url> }`

## 3) URL Parsing Rules

Accepted:
- `https://soundcloud.com/<profile_slug>`
- `http://soundcloud.com/<profile_slug>`
- Optional query params allowed and ignored for canonicalization.

Canonical parse result:
- `service = soundcloud`
- `source_type = collection`
- `source_id = <normalized_profile_url>`

Rejected as parse failures:
- `https://soundcloud.com/<artist>/<track>`
- URLs with missing or empty profile slug
- Non-SoundCloud domains

## 4) Intermediary Model
Derived as unit tests go on
profileResult
trackResult...

{likedTracks, reposts, likedLists}



## 8) Integration Fixture Inputs (Developer-provided)

Developer provides stable reference URLs for SoundCloud profiles that cover:
- profile feed with tracks
- nested collection behavior if available
- edge cases (empty/near-empty profile feed, duplicate-like entries if possible)

These fixtures are part of the integration test set referenced by `SPEC.md`.
