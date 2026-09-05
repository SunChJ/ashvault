# 003.020 — Item Definitions and Instance Identity

## Plan

Status: Implemented.

M3-01 establishes the item identity and plain-data boundary before affix
selection, equipment, inventory transactions, and SaveGameV1 implementation.

- Extend GameContentDefinition with an exported, freeze-guarded ItemDefinition
  Resource. A small item catalog validates item fields before delegating stable
  IDs, tags, dependencies, and publication to the existing ContentCatalog.
- Keep ItemInstance as immutable RefCounted runtime data with defensive copies.
  Store definition ID, level, rarity, affixes, rolls, sockets, quality, metadata.
- Let an ItemWorld allocate namespace/counter UIDs without RNG or wall time.
  The namespace is a persistent profile/world identity provided by composition;
  one authoritative world owns each namespace. Never derive it from a loot seed.
- New-item copies allocate fresh UIDs; snapshot restoration retains identities.
  Persist the allocation counter as a decimal string, validate all records
  before publication, and prohibit rewinding an already-used world.
- Accept bounded JSON-safe metadata only; reject objects, non-string map keys,
  non-finite/unsafe numbers, and excessive nesting. Mechanical item fields have
  explicit schemas; metadata does not drive gameplay rules.

Godot Resources and the existing catalog fit authored definitions. The installed
GLoot 3.0.2 InventoryItem is RefCounted with mutable generic properties and its own
serialization/copy semantics. Keep it behind the planned inventory adapter;
using it as authority would couple item identity to a broader property/prototype
model without the required UID allocation and strict DTO validation.
Reviewed its local source and the
[official Asset Library entry](https://godotengine.org/asset-library/asset/1368).
No dependency or editor tooling is added.

## Validation plan

Use a focused headless fixture for native Resource loading, catalog atomicity
and freezing, UID uniqueness and continuation, deep copy isolation, JSON
round-trip, malformed fields, duplicate IDs, counter exhaustion, and failed
restore atomicity. Register it in the unified macOS/Windows suite.

## Outcome

Implemented the four item contracts and a native authored fixture. The
[items guide](../../project-ashvault/game/simulation/items/README.md) is the
source of truth for fields, capacity limits, UID scope, and restore semantics.

- Catalog publication validates item fields before the shared content catalog
  freezes definitions. Runtime item snapshots contain no Resource references.
- Namespace/counter UIDs continue exactly above 2^53 and fail before signed
  64-bit overflow. The next counter is serialized as a decimal string.
- Full snapshot validation is atomic; restore cannot rewind an active world.
  New-item copies allocate fresh identities and defensively copy nested data.
- Metadata is bounded and JSON-safe; affixes, rolls, and sockets have explicit
  structural schemas. Rarity/tier/rune legality remains downstream work.

Validation: the focused headless fixture passed after starting with missing
contract implementations. It covers 1002 sequential identities, native Resource
loading/freezing, lookup, copy isolation, full-precision JSON round-trip, large
counters, exhaustion, malformed/cyclic metadata, failed-create counter stability,
and failed-restore atomicity. `python3 tools/ci/run_tests.py` passed on Godot
4.7.2, including 49 Python tests, all production/prototype fixtures, report and
kernel gates, performance baseline, and default-scene smoke. No error or warning
lines remained in the successful full-suite output.

## Deviation and remaining scope

The full suite exposed intermittent audio teardown warnings in the preceding
M2 feedback fixture. Replace its fixed delay with observable weak-reference
retirement and a bounded failure deadline; this is recorded in amendment 019
and committed separately from item implementation.

Rarity generation, inventory operations, profile namespace creation, ownership
across containers, and save-file I/O remain separate M3 tasks. No additional
plugin, generator, or generic persistence framework was introduced.
