# 003.021 — Rarity and Deterministic Affix Generation

## Plan

Status: Implemented.

M3-02 builds on the existing item UID/DTO and independent loot RNG contracts.
Add frozen authored affix/tier Resources, a validated affix catalog, rarity
policies, and a deterministic generator. Apply the same legality checks to
manual item creation, copies, generation, and snapshot restoration.

Initial numeric policy (explicit implementation choices where the specification
states relative roles): larger tier numbers mean stronger tiers; blue can reach
T5, other affixed rarities T4. Blue generates 1–2 random affixes; gold 1–4;
white none. Green has one fixed implicit and 2–3 random affixes; purple has 1–2
fixed affixes, a required interaction ID, and 1–2 random affixes. Red and set
have 1–4 fixed affixes and no extra random affixes, with required rule/set IDs.
No rarity adds an automatic stat multiplier. Blue's targeted-reroll cost weight
is 1 versus 2 for other affixed rarities; M3-06 owns actual crafting costs.
Set activation thresholds remain 2/3/4 pieces in the equipment milestone.

Affixes declare groups, allowed slots/bases, exclusions, and level-gated tiers
with finite bounded values. Validate nested Resources before freezing, and
validate cross-references before catalog publication. Item definitions carry
allowed rarities, fixed affix IDs, and explicit drop-source/interaction/rule/set
IDs; metadata does not drive these mechanics.

Use stable-ID ordering, loot-stream integer draws, bounded backtracking over
compatible candidates, and quantized numeric rolls. Work on a cloned RNG
snapshot; commit RNG only after ItemWorld publishes a valid item. Failed
requests consume neither randomness nor identity. Do not introduce a parallel
inventory implementation or a generic random-content framework.

Reviewed native Resource/RNG APIs, the installed GLoot source, and its
[Asset Library listing](https://godotengine.org/asset-library/asset/1368).
GLoot's prototype/property model does not implement these affix legality or
independent-stream contracts; retain it for M3-05 inventory adapters. Reuse the
project RNG wrapper around Godot's pinned engine implementation.

## Validation plan

Property-check thousands of generated items across all rarities, bases, and
levels. Pin a seeded replay digest on macOS/Windows; verify catalog-order
independence, save/RNG continuation, combat/dungeon stream isolation, immutable
nested tiers, illegal combinations, and atomic generation/restore failures.

## Outcome

Implemented frozen AffixDefinition/AffixTier Resources, AffixCatalog, the
rarity policy, and ItemGenerator. ItemCatalog now validates mechanical records
on every ItemWorld creation/copy/restore path. Updated the earlier identity
fixture to load an actual authored affix/tier Resource instead of accepting an
unchecked affix ID. See the
[affix guide](../../project-ashvault/game/simulation/items/AFFIX_GENERATION.md)
for current fields, numeric choices, and failure semantics.

Verified with Godot 4.7.2:

- 7,000 generated records over all seven rarities, five levels, multiple bases
  and slots passed independent count/group/exclusion/tier/bounds assertions.
- Seeded digest: `2f5c65bf791cb5ac06fb0df9ef0e2a3f1ed9c08c5e6a287d6d3babe82df0aa55`.
  Reversed publication order and JSON world/RNG continuation produce exact
  matching records; combat/dungeon streams remain unchanged.
- Rejected malformed tier Resources, broken cross-references, missing special
  identities, illegal combinations, missing rolls, and mandatory-affix removal.
- Backtracking fixture recovered across 64 draws from a conflicting first
  candidate and an infeasible count. Invalid requests and post-selection UID
  exhaustion leave both world state and RNG unchanged.
- `python3 tools/ci/run_tests.py` passed: 49 Python tests, production/prototype
  fixtures, report/kernel gates, performance baseline, and main-scene smoke.
  The final added backtracking/count tests also passed the focused fixture.
  Successful validation logs contained no warnings or errors.

## Scope and tradeoffs

The numeric T5/T4 ceilings, generation count minima, reroll weights, and value
quantization are initial policy, not measured final balance. Backtracking uses
at most 100,000 visits; failure is explicit and atomic. Selection falls back to
a lower legal count when needed and is not uniform over compatible subsets.

Actual equipment effects, target-farm drop tables, crafting operations, final
item balance, and the full content budget remain downstream milestones. This
change tightens validation of existing DTO fields without changing their shape
or pretending previously unchecked illegal records are valid saves.
