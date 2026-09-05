# Rarity and affix generation

`ItemGenerator.generate(world, streams, definition_id, level, rarity)` creates a
validated item with simulation-owned identity. The caller selects rarity and
base; M3-04 loot tables own drop probabilities and source selection. Generation
uses only `RngStreams.LOOT`, never combat/dungeon RNG or global random calls.

## Rarity policy

Larger tier numbers indicate higher tiers. These initial numeric choices
implement the relative roles in the kernel specification; final build-value
balance remains the M3-09 gate.

| Rarity | Fixed affixes | Generated random affixes | Tier ceiling | Definition requirement |
| --- | --- | --- | --- | --- |
| White | 0 | 0 | None | Ordinary base; retains quality/socket crafting fields |
| Blue | 0 | 1–2 | T5 | Ordinary base |
| Gold | 0 | 1–4 | T4 | Ordinary base |
| Green | 1 | 2–3 | T4 | Stable `drop_source.*` ID for target farming |
| Purple | 1–2 | 1–2 | T4 | Stable `interaction.*` ID |
| Red | 1–4 | 0 | T4 | Stable `rule.*` ID |
| Set | 1–4 | 0 | T4 | Stable `set.*` ID |

Special definitions permit exactly one rarity; ordinary bases can permit any
nonempty subset of white/blue/gold. No item exceeds four total affixes, and no
rarity grants an automatic stat multiplier. Blue/gold records with zero affixes
remain structurally legal (the specification sets upper limits); generation
always adds at least one. Every attached affix has exactly one numeric roll.

`targeted_reroll_weight()` returns 1 for blue, 2 for other affixed rarities, and
-1 for white/unknown. M3-06 owns actual crafting eligibility, currency cost, and
transactions. Source/interaction/rule/set IDs are authored contracts; actual
drop tables, named ability effects belong to later milestones. Numeric
equipment effects and set activation at 2/3/4 pieces are implemented in
[EquipmentState](EQUIPMENT.md). Metadata never supplies these mechanics.

## Authored resources and publication

`AffixDefinition` extends `GameContentDefinition` with a stable group and stat
ID, allowed slots, optional allowed bases, excluded affix IDs, and ordered
`AffixTier` Resources. Empty allowed bases means any matching slot. Exclusion
is symmetric at validation/selection time even when only one affix declares it.
A group may occur only once on an item.

A tier contains number (1–5), minimum item level, and minimum/maximum value.
Numbers increase strictly; minimum levels are non-decreasing positive 32-bit
integers. Numeric bounds are finite, ordered, and within ±1,000,000. A tier's
level gate and rarity ceiling must both allow a roll. Fixed affixes use their
highest eligible tier; random affixes select uniformly among eligible tiers.
Numeric values use one integer draw over 1,000,001 interpolation positions,
round to 1e-6, and clamp to authored bounds. Constant bounds consume no value
draw. Affix operation/condition/priority/conversion-target fields now map these
values into shared StatModifiers; see the [equipment guide](EQUIPMENT.md).

`AffixCatalog` validates at most 128 definitions (the slice budget is 36),
including exclusion references and nested tiers, before shared ContentCatalog
publication freezes them. It adds no tags of its own; generic content tags on
affix Resources therefore remain empty. ItemCatalog accepts the published
AffixCatalog as its third load argument. It validates fixed-affix compatibility,
special IDs, and allowed-base references before publishing item definitions.
Omitting the affix catalog supplies an empty catalog, suitable for plain bases;
it never bypasses record validation. Native `.tres` examples are in
`tests/fixtures/items/power_affix.tres` and `training_wand.tres`.

## Determinism and failures

1. Filter candidates in sorted stable-ID order by base, slot, level, ceiling,
   and compatibility with mandatory fixed affixes.
2. Clone the RNG snapshot and shuffle candidates using only its loot stream.
3. Draw a count, then search for compatible groups/exclusions. Backtracking
   avoids greedy dead ends; if the chosen count is infeasible, try lower counts
   down to the rarity minimum. This is not uniform sampling over combinations.
4. Roll tiers/values, validate the completed record, and allocate its UID.
5. Commit the staged RNG snapshot only after item creation succeeds.

Search is capped at 100,000 recursive visits per request. Exhausted search,
insufficient compatible affixes, invalid requests, and exhausted UID allocation
return an error without advancing RNG or changing ItemWorld. This bounded
failure is explicit rather than an unbounded rejection-sampling loop.

ItemCatalog's record validation is shared by creation, copies, generation, and
snapshot restore. It rejects unknown affixes, wrong slots/bases, duplicate groups,
exclusions, missing mandatory affixes or rolls, invalid rarity counts, illegal
tiers/levels, and out-of-bounds values. M3-01 snapshots with previously unchecked
illegal combinations are now rejected; the DTO shape/version is unchanged.

## Verification

```sh
"$ASHVAULT_GODOT" --headless --path project-ashvault \
  --script res://tests/production/test_affix_generation.gd
python3 tools/ci/run_tests.py
```

The fixture checks 7,000 generated items over seven rarities, five levels,
multiple bases/slots, independent rarity/count/group/bounds assertions,
publication immutability, invalid combinations, and atomic failures. It also
checks catalog-order independence, world/RNG JSON continuation, unrelated RNG
stream isolation, and a shared macOS/Windows digest:

```text
2f5c65bf791cb5ac06fb0df9ef0e2a3f1ed9c08c5e6a287d6d3babe82df0aa55
```

These fixture items/affixes are deterministic tests, not the final content budget.
The installed GLoot stays behind inventory adapters; its generic prototype
properties do not own generation rules, loot RNG, or authoritative DTOs.
