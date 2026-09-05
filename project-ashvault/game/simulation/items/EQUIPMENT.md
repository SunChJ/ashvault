# Equipment transactions and stat aggregation

`EquipmentState` is a scene-independent loadout over existing ItemWorld UIDs.
It owns exactly eight slots: `slot.weapon`, `slot.off_hand`, `slot.head`,
`slot.body`, `slot.hands`, `slot.feet`, `slot.neck`, and `slot.ring`. These names
are the initial eight-slot contract. Items with other slot IDs may exist in a
catalog but cannot be equipped into this loadout.

## Atomic changes

Configure with an ItemWorld, a loaded StatRegistry, optional immutable character
StatModifiers, and optional EquipmentSetBonus Resources. The initial snapshot
resolves the registered defaults and character modifiers at tick zero.

```gdscript
var gear := EquipmentState.new()
var error := gear.configure(world, stat_registry, character_modifiers, set_bonuses)
assert(error.is_empty())
var result := gear.transact({
    "slot.weapon": two_handed_item.uid(),
    "slot.off_hand": "",
}, tick, active_conditions)
assert(result.error.is_empty())
var stats: RefCounted = result.stats
```

A transaction is a partial slot-to-UID map; empty string means unequip. It
validates the final arrangement, so dictionary insertion order cannot change
whether a swap succeeds. UIDs must exist in this ItemWorld, match the exact
slot, and appear at most once. `ItemDefinition.two_handed` is legal only for
`slot.weapon`; its final arrangement must leave off-hand empty. No automatic
item eviction is hidden inside compatibility checks.

All contributions then pass through StatResolver. Only success publishes slots,
the new immutable StatSnapshot, source provenance, and special-effect IDs.
Unknown stats, duplicate modifier identities, bad conditions, numeric resolution
errors, and compatibility failures leave the previous state untouched. Returned
`displaced` UIDs identify previously equipped items no longer present, in stable
slot order. They remain in ItemWorld; no inventory capacity or deletion is
implied. Failure returns an error, an empty displaced list, and null stats.

Ticks must not decrease. `transact({}, tick, active_conditions)` refreshes
conditional stats without changing equipment. Conditions are explicit input on
every call; an omitted condition list means no active conditions, not the last
call's list. Previously published stat snapshots remain immutable.

## Authored contributions

- `ItemDefinition.base_effects` contains frozen ItemStatEffect Resources with a
  unique local `item_effect.*` ID and the existing stat modifier fields.
- AffixDefinition now carries `operation` (FLAT by default), `condition_id`,
  `priority`, and `target_stat_id` alongside `stat_id`. Each rolled value becomes
  a StatModifier; publication validates both tier endpoints against operation
  constraints (for example, conversion must remain within 0–1).
- EquipmentSetBonus Resources declare a stable set ID, a 2/3/4-piece threshold,
  and nonempty stat effects. Configuration requires all three unique thresholds
  for each registered set and freezes its nested effects. Count distinct item
  definition IDs, activate every reached threshold, and remove bonuses when
  pieces are unequipped. Equipping an unregistered set fails explicitly.

Base effects, rolled affixes, set bonuses, and character modifiers all use the
existing BASE/FLAT/INCREASED/MORE/CONVERSION/OVERRIDE/CAP ordering, conditions,
priorities, validation, and explanations. Equipment does not compute final stat
values itself or introduce a rarity multiplier. Registry compatibility is
checked for the equipped arrangement, so an incompatible item can exist in the
world without being silently equipped.

## Observable output and persistence

`stats()` exposes the immutable StatSnapshot. Its applied/skipped sources and
conversion explanations use stable source IDs:

- Item: `equipment.<UID namespace>.i<sequence>.<effect or affix ID>`.
- Set: `equipment.<set ID>.p<threshold>.<effect ID>`.

`sources()` returns a defensive dictionary mapping equipment source IDs to
item UID/definition/effect or set/threshold provenance. Character modifiers
retain their own source IDs. `special_effects()` returns defensive
`{uid, interaction_id, rule_id}` records for equipped special items, removed on
unequip. Those IDs declare downstream ability composition; they do not execute
named interactions or rules by themselves.

`snapshot()` is a plain `{schema_version: 1, slots: {...}}` DTO containing all
eight slot keys. Restore resolves UIDs against the supplied ItemWorld and runs
the same complete transaction, recomputing stats for the requested tick and
conditions. Item records, stat values, and Resource references are not duplicated
into the equipment DTO.

[InventoryState](INVENTORY.md) wraps this resolver with owner and bag-capacity
validation, atomically publishing displaced items and UID locations. Composed
gameplay uses that wrapper; direct EquipmentState is a lower-level resolver.
Crafting, quality, and socket/rune mechanics remain M3-06. This module supplies shared
StatSnapshots for combat composition; the fixed M2 showcase still uses its
existing defaults. Final named ability-rule effects remain content work.

## Validation

```sh
"$ASHVAULT_GODOT" --headless --path project-ashvault \
  --script res://tests/production/test_equipment.gd
python3 tools/ci/run_tests.py
```

The fixture covers eight compatible slots, incorrect/duplicate/foreign UIDs,
replacement and two-handed swaps in both key orders, rollback on unknown stats
and duplicate modifier sources, immutable snapshots/provenance, JSON restore,
conditional MORE, INCREASED-to-CONVERSION ordering, 2/3/4-piece activation and
removal, frozen contributions, and special-effect declaration lifetime.
