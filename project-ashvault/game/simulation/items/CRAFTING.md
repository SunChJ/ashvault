# Crafting contracts

InventoryState owns material balances and executes crafting only against the
current immutable ItemInstance reference in the owner's exact bag slot.
Authority, owner, slot, and reference checks precede recipe planning. Stale,
stashed, equipped, vendor-owned, ground, and consumed targets reject.

`craft(creator, owner, bag_slot, expected_item, recipe, streams, target)` returns
an error or a receipt with UID, costs, yields, consumed flag, and active runeword
ID. Costs and yields are published material IDs with bounded integer counts.
`grant_materials` is a trusted reward/setup operation that validates the entire
grant before changing any balance. Counts are limited to 2147483647; known IDs
are `material.shard` and runes published in the item's crafting catalog.

## Recipe policy

CraftingPolicy is a frozen native Resource. Its default rates are below; these
are initial deterministic rules, not a completed economy balance gate.

| Recipe | Target | Default cost or yield | Rule |
| --- | --- | --- | --- |
| `salvage` | Empty | Yield 1 shard white, 2 blue, 4 other rarities | Retire UID; socketed runes are not refunded |
| `quality` | Empty | 2 × resulting quality shards | Increase by one, cap 20 |
| `socket` | Empty | 5 × resulting socket count shards | White only, bounded by base capacity; active word cannot gain sockets |
| `insert_rune` | Published rune ID | One rune plus one shard | Fill first empty socket in index order |
| `reroll` | Attached non-fixed affix ID | 10 shards blue, 20 other eligible rarities | Red/set fixed effects and constant ranges reject |

Only existing non-fixed numeric roll values are rerolled. Affix identity, tier,
level, other rolls, quality, sockets, metadata, and UID remain unchanged. The
selected tier uses the existing generator's integer draw `[0,1000000]`, linear
interpolation and six-decimal snapping/clamping. A new roll may equal the old
one; no guaranteed improvement is promised. Blue retains its higher tier ceiling
and always pays half the cost of another eligible rarity under the same policy.

Every recipe plans against staged RNG. Only reroll advances loot RNG; combat and
dungeon RNG never advance. Material shortages, overflow, illegal targets, and
record replacement errors publish nothing, including the staged RNG state.

## Records and ownership

ItemWorld.replace_item compares the expected current ItemInstance reference,
validates the full replacement record, and forbids UID/definition changes. It
publishes a new immutable object under the original UID without consuming an
allocator sequence. Old references remain immutable and become stale for future
craft commands. Composed gameplay uses the inventory craft wrapper rather than
calling the world record primitive directly, especially for equipped items.

Salvage leaves its immutable record in ItemWorld as evidence and marks the UID
location `consumed`; it cannot be reclaimed by setup, moved, equipped, sold, or
salvaged again. Materials and item location commit together. This is a tombstone,
not an inventory slot. Inventory observation schema 2 adds owner material
wallets; [SaveGameV1](../../infrastructure/save/README.md) validates and restores
these wallets and consumed locations.

## Runes, words, and stats

RuneDefinition and RunewordDefinition are native Resources with stable IDs and
ItemStatEffect arrays. CraftingCatalog publishes them and the recipe policy
atomically. ItemCatalog accepts this published catalog as its optional fourth
argument; omission publishes an empty rune/word catalog with default policy.
Item creation, replacement and restore validate quality <=20 and every occupied
socket against published rune IDs. Existing sockets may contain runes on any
rarity; only white items gain new sockets through crafting.

Words declare 2–32 ordered rune IDs and explicit eligible base IDs. Item catalog
publication verifies those bases exist, allow white rarity, and have sufficient
socket capacity. Overlapping recipes with identical sequence/base reject.
A word activates only when the item is white and the **entire** socket array
exactly equals the sequence. Reversed order, partial/extra sockets, nonwhite
rarity, and an ineligible base yield no word. Individual rune effects still work.
Activation is derived rather than serialized as a separately mutable flag.

EquipmentState scales only item base BASE/FLAT contributions by
`1 + quality / 100`; it does not scale affixes, individual rune effects, or word
effects. Each socket and the active word then contributes through StatResolver
with distinct source IDs and item/rune/word provenance. Existing conditional,
conversion, override and cap behavior remains in that shared resolver.
Crafting cannot mutate equipped records; unequip, craft, and re-equip to refresh.

## Validation

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project-ashvault --script res://tests/production/test_crafting.gd
python3 tools/ci/run_tests.py
```

The fixture covers every recipe, shortage/overflow rollback, stale/foreign/
equipped targets, immutable old references, quality/socket limits, blue costs,
fixed-affix protection, seeded rerolls, native rune loading, order/base/rarity
eligibility, crafted record restore, and equipment aggregation. Seed 929 yields
`3.550166` after 20 blue rerolls. Final six-rune/three-word content, economy tuning,
crafting UI, rune extraction, and affix replacement are downstream.
