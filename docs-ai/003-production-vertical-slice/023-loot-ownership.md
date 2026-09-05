# 003.023 — Deterministic loot and pickup ownership

## Context

M3-04 needs traceable source/table selection and exactly-once pickup without
moving deterministic state into presentation. Existing ItemGenerator already
stages loot RNG and publishes an immutable item only after validation.

## Change

Publish frozen native loot entry/table Resources, with canonical entry-ID order,
positive integer weights, explicit no-drop entries, and source-specific tables.
Each unique occurrence selects zero or one item. Stage selection RNG before
calling ItemGenerator; failed generation changes neither world nor live RNG.
Keep occurrence receipts (including empty results), creator, reserved owner,
source, selected entry, selection draw, and complete generated item evidence.
A single run-owned ledger registers bounded owner bags and atomically transfers
one ground UID into its reserved owner's bag. Reject duplicate pickup, foreign
creator/owner, and full destinations without mutation.

One authoritative ledger per ItemWorld is a composition invariant. Caller
identities are trusted simulation inputs, not network authentication. Multi-item
rewards use separate occurrence IDs; save restore, stash/vendor/equipment
transfers, and combat/presentation wiring belong to downstream tasks.

## Alternatives and decisions

Reviewed installed GLoot inventory Node and the official Asset Library listing
(https://godotengine.org/asset-library/asset/1368). Keep GLoot as a presentation
adapter: mutable Node inventory does not own simulation UIDs or deterministic
RNG. Native Resources plus a focused RefCounted ledger preserve existing
boundaries without a generic transaction framework or new dependency.

## Validation

Passed the focused headless `test_loot.gd` fixture and the complete
`python3 tools/ci/run_tests.py` suite (49 Python tests plus Godot contracts,
replay, performance gates, and scene smoke). The 200-occurrence fixture produced
58 explicit no-drops and pinned item hash
`c3b67efdff6217a00a1b70fe10ec78a0e5a3028467fef97650367a179a735744`.
Coverage includes reordered tables, loot-only RNG, empty/no-drop receipts,
generation and exhausted-UID rollback, native `.tres` loading, source provenance,
duplicate occurrences/pickups, creator/owner checks, full inventory retry,
frozen definitions, defensive snapshots, and JSON ownership identity evidence.

## Current state

M3-04 is implemented. Current contracts are documented in
[LOOT.md](../../project-ashvault/game/simulation/items/LOOT.md).
No scope deviations; save import and downstream inventory transfers remain
explicitly deferred.
