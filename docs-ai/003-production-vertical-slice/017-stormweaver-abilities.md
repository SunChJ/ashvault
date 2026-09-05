# 003.017 — Stormweaver Active Abilities

## Context

M2-06 composes the existing cast, delivery, status, damage, and enemy runtimes.
The six abilities need executable content, not a second combat authority.

## Planned change

- Author six fixed-slot activation definitions and separate on-hit definitions.
  Delivery resolves targets before the shared executor evaluates hit effects.
- Keep all costs, cooldowns, cancellation, and health in EntityWorld. Compose
  accepted commands, swept movement, delivery, status, and damage at 60 Hz.
- Stage independent world copies and publish only after the complete tick
  succeeds. Rejected input must preserve resource, cooldown, RNG, and hashes.
- Dash replaces ordinary movement for its authored duration and uses the same
  swept collision resolver. Ward and dash protection use conditional damage
  modifiers through StatusWorld and DamagePipeline, including expiry boundaries.
- Define rank milestones through AbilityEffectTransform. Validate item effect
  replacements before building the loadout; do not allow an alternate damage path.
- Publish structured tick evidence and deterministic replay hashes. Keep HUD,
  final VFX, audio, and item ownership outside this issue.

## Ecosystem decision

Godot Resources and RefCounted values fit the existing immutable definitions and
scene-independent simulation. The Asset Library's
[godot-gameplay-abilities](https://godotengine.org/asset-library/asset/3847)
uses an AbilityContainer Node to manage activation. Adopting a second ability
lifecycle would duplicate the already tested cast authority. Keep the local
composition explicit; installed State Charts remains presentation-only.

## Validation

One headless fixture per skill, combination/expiry cases, cancellation, invalid
batch rollback, item/rank transforms, collision, and reordered seeded replay.
Run `tools/ci/run_tests.py` after focused validation. Structured fixture output
captures behavior without introducing a presentation dependency.

## Current state

Implemented for #20. `StormweaverCatalog` authors six activation definitions,
four on-hit definitions, rank-5 transforms, and status/delivery parameters.
`StormweaverCombat` stages the entity, delivery, status, and RNG worlds before
publishing one accepted tick. EntityWorld gains optional swept forced movement
and internal copy-on-write staging support; older call sites and hashes remain
unchanged.

The focused suite covers every skill, critical hits, Shock stacking/expiry,
Ward/Dash composition, configured damage types, interruption, obstacle collision,
item/rank transforms, lethal-hit attack suppression, presentation independence,
command/entity ordering, and late-execution rollback. JSON captures include
combined and 120-enemy fixtures with pinned replay hashes shared by desktop CI.
The unified local suite passed, including 49 Python tests, project import,
production/prototype headless suites, CLI/schema checks, and the M1 kernel gate.

## Decisions refined during implementation

- Rank transforms are resolved before item damage replacements, then the final
  graph is validated by AbilityDefinition. Context-dependent errors such as a
  missing scaling stat remain actionable execution failures and roll back the
  full tick.
- Enemy intents are previewed after player damage so an enemy killed in the
  current tick cannot still attack. Enemy damage then commits through the same
  DamageResult boundary.
- Dash interruption removes its protection through a forced StatusRemoval in
  the same tick. Damage immunity remains a conditional modifier, including for
  non-default damage types referenced by configured content.
- Hit events expand to damage/critical events through bounded queue emissions.
  No external reaction callback or unbounded event history is introduced.
- The optional presentation deliverable is structured simulation capture for
  this issue; visual/audio feedback remains in M2-07/M2-08 as agreed.

## Remaining boundary

This is the M2 simulation composition, not the M2 readability/performance gate.
HUD wiring, final combat visuals, audio, and configurable build stat aggregation
remain downstream tasks. The 120-enemy fixture proves deterministic behavior;
it does not claim the final rendered frame-time target.
