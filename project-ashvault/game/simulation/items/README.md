# Item identity and data contracts

`ItemDefinition` is an authored Resource extending `GameContentDefinition`.
Its exported display name, stable equipment-slot ID, and socket capacity freeze
when `ItemCatalog` publishes. The catalog delegates stable-ID, tag, dependency,
and cycle validation to `ContentCatalog`; failed publication freezes nothing.
A native `.tres` example lives in `tests/fixtures/items/training_wand.tres`.
The fixture is not part of the final item-content budget.

`ItemWorld` owns immutable `ItemInstance` records. It requires a published item
catalog and a persistent namespace, such as `profile.fixture`. Composition must
provide a different namespace for independent profiles/worlds, persist it, and
maintain one authoritative world per namespace. A loot seed is not an identity.
UID allocation uses no RNG, time, Node, or engine object instance ID.

```gdscript
var world := ItemWorld.new()
var error := world.configure("profile.fixture", catalog)
assert(error.is_empty())
var result := world.create_item("item.training_wand", {"item_level": 12})
assert(result.error.is_empty())
var item: RefCounted = result.item
var copied := world.copy_item(item.uid())
assert(copied.item.uid() != item.uid())
```

New items use `<namespace>:<sequence>`, starting at one. Only the world allocates
identities; payloads cannot supply them. Copies preserve all non-identity data
and allocate another UID. Failed operations consume no UID. Sequence
`9223372036854775807` is the exhausted sentinel and is never allocated.
Instances expose identity getters and defensive `snapshot()` copies; their
underscore initializer and backing data are internal to the simulation module.
Future crafting replaces validated records through world-owned operations.

Eight-slot equipment, atomic swaps, and stat aggregation are implemented in
the [equipment guide](EQUIPMENT.md).

Rarity/affix publication and generation are implemented in the
[affix generation guide](AFFIX_GENERATION.md). ItemCatalog accepts a published
AffixCatalog as its optional third load argument; an omitted catalog is empty.

## Instance fields

| Field | Contract |
| --- | --- |
| `uid` | World-owned string identity |
| `definition_id` | Published stable `item.*` ID |
| `item_level` | Positive 32-bit integer; default 1 |
| `rarity` | `white`, `blue`, `gold`, `green`, `purple`, `red`, `set`; default white |
| `affixes` | Ordered, unique published `affix.*` IDs; at most four under rarity rules |
| `rolls` | Ordered `{affix_id, tier, value}` records; exactly one per attached affix; eligible tier and bounded numeric value |
| `sockets` | Ordered strings: empty socket `""` or stable `rune.*` ID, bounded by definition capacity (0–32) |
| `quality` | Non-negative JSON-safe integer; default 0 |
| `metadata` | Optional JSON-only descriptive provenance; does not define mechanical behavior |

Affix/roll/socket collections default to empty. The affix catalog and rarity
rules validate lookup, counts, groups, exclusions, slots/bases, tiers, levels,
and numeric bounds on creation and restoration. EquipmentState supplies eight-slot
compatibility and atomic stat aggregation; M3-06 supplies crafting rules and
rune lookup. Inventory ownership and crafting remain separate contracts.
Metadata permits null, booleans, strings, finite safe numbers, arrays, and
string-keyed dictionaries. It rejects Resources, Nodes, other engine Variants,
cycles/excessive depth, and integers outside ±(2^53−1). Limits are eight nesting
levels, 4096 visited values, and 4096 characters per key/string.

## Snapshot restoration

The world DTO contains exactly `schema_version` (1), `namespace`,
`next_sequence` (decimal string), and `items` (records in allocation order).
Strings preserve UID counters beyond JSON's exact integer range. Use
`JSON.stringify(snapshot, "", true, true)` to retain full float precision.

Restore into a newly configured, unused world. It validates the whole snapshot
before publishing: catalog references, record shapes, unique increasing UID
sequences, matching namespaces, and a next sequence greater than every item.
Successful restore retains existing identities and advances future allocation.
It marks even an empty restored world as used; an active world cannot rewind
its allocator by loading an older snapshot. Failed restore leaves it untouched.
Save-file I/O, migrations, profile namespace creation, ownership transactions,
and duplicate ownership across containers belong to later M3 composition.

The installed GLoot `InventoryItem` is RefCounted, but its mutable generic
prototype/property model and copy/serialization semantics do not implement this
identity contract. Keep GLoot behind inventory adapters; it does not own item
UIDs or authoritative save records.

## Validation

```sh
"$ASHVAULT_GODOT" --headless --path project-ashvault \
  --script res://tests/production/test_items.gd
python3 tools/ci/run_tests.py
```

The focused fixture loads an authored Resource, verifies publication/freezing,
creates 1002 distinct UIDs, checks deep copies and JSON restoration, continues
allocation beyond 2^53, and rejects duplicate UIDs, counter overflow/rewinds,
unknown definitions, malformed fields, and non-JSON metadata atomically.
