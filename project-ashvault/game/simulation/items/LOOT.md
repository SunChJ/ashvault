# Loot and pickup ownership

`LootEntry` and `LootTable` are native authored Resources. `LootState` owns a
run's occurrence receipts, reserved ground drops, and bounded pickup bags.
Configure it with the existing ItemWorld, initialized RngStreams, a stable
creator ID, and validated tables. Tables and nested entries freeze together
only after all tables validate. Reconfiguration is rejected.

## Selection

A table has a `loot.*` ID and `drop_source.*` source ID. Entries have unique
`entry.*` IDs, positive integer weights, and an item definition/rarity pair.
Omitting both definition and rarity explicitly means no drop. Empty tables are
valid. Up to 1024 entries and total weight 2147483647 are supported. Green
items must match their definition's dedicated drop source.

`drop(creator_id, occurrence_id, source_id, table_id, owner_id, item_level)`
selects zero or one item. A caller supplies a stable unique occurrence ID per
reward attempt (including per-roll identity for a multi-item reward), a
registered reserved owner, and a positive 32-bit level. All completed
occurrences, including empty/no-drop results, reject reuse. Failed operations
remain retryable and reserve neither occurrence nor UID.

Entries sort by ID before publication. Nonempty tables draw one loot integer
in `[0, total_weight - 1]`, then use ItemGenerator for the selected item's
rarity and affixes. Empty tables draw nothing. Selection and generation use
staged RNG; generation or UID allocation failure changes neither live RNG nor
ItemWorld nor ownership. Combat and dungeon streams remain untouched.

The returned defensive receipt includes occurrence, creator, reserved owner,
source, table, entry, requested level, draw (`-1` for empty tables), total
weight, and the complete immutable generated item record (including rarity,
affixes, tiers, values, and UID). No-drop receipts contain an empty item record.
Receipts describe the original drop; live ground/bag state records its current
location. Snapshots contain plain JSON-compatible data and defensive copies.
Numeric normalization and validated save restore belong to SaveGameV1.

## Pickup

Only the configured creator may register owners, resize bags, create drops,
or execute pickup. Bags have capacity 0–10000 and count one slot per UID.
`pickup(creator_id, owner_id, uid)` checks a live ground UID, matching creator
and reserved owner, and available capacity before moving that same UID into
the owner's bag. Full bags leave the drop untouched for retry. Duplicate or
foreign pickups fail. Capacity cannot shrink below current contents.

The simulation composition must use one authoritative LootState per ItemWorld;
these trusted in-process identity arguments are authority checks, not network
authentication. A future authority adapter must obtain creator/owner/occurrence
from validated actor and source events rather than accepting client claims.
Snapshots are inspectable evidence, not a live rollback or save import API.
GLoot presentation may mirror this state but cannot grant item ownership.
Stash/vendor/equipment transfers, save restore, and combat/presentation wiring
are downstream work. Ground drops are not automatically expired or discarded.

## Reproduction

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project-ashvault --script res://tests/production/test_loot.gd
```

The fixture uses a native `.tres` table and 200 seeded mixed-table occurrences,
checks the pinned item hash, reordered publication, explicit no-drop and empty
outcomes, generation/UID failure rollback, source provenance, ownership,
capacity retry, immutable publication, and JSON identity evidence.
