# 003.025 — Deterministic crafting transactions

## Context and plan

M3-06 adds salvage, quality, targeted rerolls, socket creation, rune insertion,
and ordered white-base runewords. Keep one inventory-owned material wallet and
restrict crafting to a UID in the owner's bag, avoiding equipped-stat mutation.
Publish replacement immutable ItemInstance records under the same UID through
ItemWorld; keep old references unchanged. Salvage retires the UID location so
trusted setup cannot reclaim it, while retaining its record as evidence.

Frozen native rune/runeword Resources and a focused crafting catalog validate
item socket IDs and exact ordered/base-eligible word activation. White items
alone gain new sockets and activate runewords; existing sockets may accept runes
on other rarities. Quality scales base additive effects by 1% per point, capped
at 20. Rune and active word numeric effects use the shared stat resolver.

A small frozen recipe policy authors shard costs and salvage yields. Materials
are bounded integer counts of material.shard and published rune IDs. Targeted
reroll changes only the selected non-fixed affix's value within its existing
tier, consuming staged loot RNG; blue costs one unit of the policy rate, other
eligible rarities two. Constant rolls reject rather than consume materials.
Runewords activate automatically when the exact socket sequence and white base
match, without a separate mutable activation field.

Reuse native Resources, ItemStatEffect, RngStreams and existing inventory commit
boundaries. GLoot remains a detached view adapter; its mutable inventory model
does not replace deterministic recipe validation. No new dependency, crafting
DSL, UI, save import, final six-rune/three-word content, or balance gate is added.

## Validation plan

Focused seeded fixtures cover every operation, material shortage/overflow,
foreign/stale/equipped targets, quality/socket limits, fixed affix protection,
blue cost advantage, ordered/base-specific words, record/RNG rollback, immutable
old references, restored record validation, and equipment effect aggregation.
Then run the complete local suite and both platform CI checks.

## Outcome and validation

Implemented all planned recipes, frozen rune/word/policy Resources, material
wallets, same-UID immutable replacement, salvage tombstones, and shared equipment
effects. Updated [CRAFTING.md](../../project-ashvault/game/simulation/items/CRAFTING.md)
and related current contracts. Item record creation/restore now rejects unknown
runes and quality above 20; inventory observation schema 2 adds material wallets.
No released save schema migration is involved.

Passed focused crafting/item fixtures and the full
`python3 tools/ci/run_tests.py` suite: 49 Python tests, all Godot contracts,
replay/performance gates, and main-scene smoke. The crafting fixture pins seed
929's twentieth blue roll at 3.550166, checks 120.1 aggregate power for quality
plus rune/word contributions, and validates old-reference immutability and
crafted-record JSON restore. Local output is retained in ignored
`.artifacts/crafting-validation.log`.

No scope deviations. The policy values are initial rules; final content and
balance remain M5. Runeword activation is derived from exact ordered sockets,
not a separately stored flag or additional activation transaction.
