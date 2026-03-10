# rememberthename - Adapters Spec

It's easy to get lost. We knowingly contract the scope to an extreme.
NO media fetching
NO searching
Just the minimal track metadata as a list - smallest common denominator.
More metadata later

Just profiles that give you track, artist and a backlink

## 1) Scope

Each provider runs as an independent long-running adapter:
- `bandcamp_adapter`
- `soundcloud_adapter`
- `youtube_adapter`
- `spotify_adapter`

Adapters resolve only their own provider data and publish progress updates while running.

## 2) Input

- Only service-specific collection-level `SourceIdentity` inputs are accepted.
- Track URLs are not valid inputs.
- `SourceIdentity` is defined in `SPEC.md` and used unchanged here:
  - `service`
  - `source_type`
  - `source_id`
- accepted source shapes are defined per service in `SPEC.md`:
  - bandcamp album source
  - soundcloud profile source
  - youtube playlist source
  - spotify collection sources (`collection/tracks`, `collection/albums`)

## 3) Resolution Modes

- `shallow`: first fetch pass; return immediately available collections/items.
- `step`: iterative mode; each step can accept prior step output and continue resolution.
- `deep`: run step-wise resolution until required detail is complete. Flat items and deep tree of source

Required output detail:
- collection metadata
- item metadata (currently only track) (`title`, `artist`, `service`, `source_type`, `source_id`)
- list metadata (`title`, `track_ids`, `list_ids`, `service`, `source_type`, `source_id`)
- no media bytes, no artwork bytes

## 3.1 Adapter Interface Contract

Each adapter module must expose:
- an internal traversal union type (module-owned)
- a profile entry constructor for traversal start
- an expand function that maps one traversal node to emitted payload + child nodes

Reference shape (spec-level):

- internal union:
  - `AdapterNode`
  - constructors must include at least:
    - `ProfileEntry(SourceIdentity)` (entry point)
    - additional internal constructors as needed (`CategoryNode`, `ListNode`, `PageNode`, ...)
- higher-kinded/effect shape:
  - `expand: AdapterNode -> m(ExpandResult)`
  - where `m(_)` is adapter-selected effect context (sync/async/task), hidden behind module API
- expand result:
  - `items: List(UnifiedItem)`
  - `lists: List(UnifiedCollection)` (only fully resolved lists)
  - `next_nodes: List(AdapterNode)`
  - `unresolved: List(UnresolvedNode)` (optional incremental unresolved emission)

Design rules:
- `AdapterNode` is internal to each adapter module (not shared globally).
- callers can only construct traversal via `ProfileEntry(...)`.
- node identity key must be deterministic for visited-set dedupe.
- emitted `next_nodes` must preserve deterministic order.
- partial list state is internal only; externally emitted lists must be complete.

## 4) Update Stream

Per-job event stream is minimal and ordered:
- `started` (debug/context message)
- `progress` (status text + optional payload: item only)
- `completed` (final stats + full list payloads)

## 5) Internally

Structural recursion, in-order, no parallelism beyond adapter level.

Recursive runtime model:
- `resolve_profile(profile)` initializes queue with `ProfileEntry(profile)`.
- `loop(queue, visited, acc, ...)` is tail-recursive.
- loop terminates only when queue is empty.

## 6) Testing & Evolution

test methods in progressive depth
Build resolution methods on top of test harness.

Test data required before starting:

- input source: URL/profile mapped to service-specific collection `SourceIdentity`
