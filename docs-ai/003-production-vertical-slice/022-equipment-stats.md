# 003.022 — Equipment Transactions and Stat Contributions

## Plan

Status: Implemented.

M3-03 adds one scene-independent eight-slot equipment state backed by existing
ItemWorld identities. Explicit slot IDs: weapon, off_hand, head, body, hands,
feet, neck, ring (all under `slot.*`). Names are the initial implementation
choice because the task specifies eight slots without enumerating them.

- Batch slot changes validate the final arrangement, including known compatible
  UIDs, no repeated UID, and two-handed weapon/off-hand exclusion. Replacements
  return displaced UIDs; no item is deleted or moved into an invented inventory.
- Resolve all staged contributions before committing equipment or its immutable
  StatSnapshot. Failures preserve slots, stats, and ItemWorld state.
- Add frozen authored base-stat effects and affix operation/condition/priority/
  conversion-target fields. Map rolled values to existing StatModifier contracts.
  Preserve all shared resolver semantics rather than adding arithmetic here.
- Add numeric set bonuses at 2/3/4 distinct pieces through the same modifier
  path. Carry equipped interaction/rule IDs as explicit read-only output for
  later ability-effect composition; IDs alone do not execute a rule.
- Use stable source IDs derived from item UID plus local effect/affix ID, and
  set ID plus threshold. Plain equipment snapshots store only slot-to-UID data.

Reviewed installed GLoot ItemSlot and the
[Asset Library listing](https://godotengine.org/asset-library/asset/1368).
ItemSlot is a Node-based inventory-facing adapter; the project needs final-state
batch validation and stat rollback without a scene tree. Keep that UI/inventory
integration for M3-05. Authored Resources and the existing StatResolver fit the
current boundary; add no plugin or generic transaction framework.

## Validation plan

Focused headless tests cover all eight slots, incompatible and foreign UIDs,
replacement/displaced IDs, atomic two-handed swaps in either dictionary order,
rollback on resolver errors, base/affix/conditional/set explanations, duplicate
sources, immutable old snapshots, and JSON restore. Run the unified desktop
suite and auto-merge after macOS/Windows CI passes.

## Outcome

Implemented EquipmentState, ItemStatEffect, and EquipmentSetBonus. Extended
ItemDefinition with two-handed/base effects and AffixDefinition with the existing
modifier operation/condition/priority/conversion-target fields. Current contracts
and limitations live in the
[equipment guide](../../project-ashvault/game/simulation/items/EQUIPMENT.md).

Verification on Godot 4.7.2:

- Eight-slot fixture resolves power 123 from defaults, eight base effects, five
  affix rolls, and three set thresholds; all 16 contributions have provenance.
- Atomic two-hand swap resolves 129 while preserving the old 123 snapshot;
  activating conditional MORE resolves 258. Set removal returns 123/118/114
  as thresholds disappear. INCREASED then 50% CONVERSION resolves 110
  power plus 110 lightning through the shared resolver.
- Rejected incompatible/duplicate/foreign UIDs, unknown stats, duplicate stat
  sources, stale ticks, malformed equipment snapshots, invalid two-handed
  definitions, duplicate base effects, and invalid conversion roll bounds.
- Verified same result for reversed batch-key order, JSON restore, immutable
  nested contributions/provenance, and special-effect declaration removal.
- `python3 tools/ci/run_tests.py` passed: 49 Python tests, production/prototype
  fixtures, report/kernel gates, performance baseline, and main-scene smoke.
  Final additional special-effect lifetime assertions passed the focused test.
  Successful logs contained no errors or warnings; the 7,000-item affix replay
  digest remained unchanged.

## Scope

Inventory capacity/ownership across actors, crafting/socket/quality semantics,
UI, and actual named ability-rule implementations remain downstream. Equipment
produces the shared StatSnapshot contract; it does not replace the fixed M2
showcase's combat defaults in this task. No additional dependency or generic
transaction framework was introduced.
