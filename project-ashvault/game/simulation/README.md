# Simulation

Owns deterministic state transitions, fixed-tick commands, stats, combat,
events, runtime entities, RNG state, and presentation snapshots.

Simulation code must remain headless and must not depend on scenes, input
devices, VFX, audio, or `res://prototype/`.

## Randomness

`random/RngStreams` is the production randomness entrypoint. A run initializes
the fixed `combat`, `loot`, and `dungeon` streams from one root seed. Consumers
must request a named stream and use its sampling methods; global random
functions and direct `RandomNumberGenerator` instances outside the wrapper are
forbidden by architecture tests.

Snapshots use canonical decimal strings for exact JSON round-trips. Restore is
transactional and keeps acquired stream handles valid. Any change to stream
names, derivation, snapshot shape, or golden sequences requires an explicit
`simulation_version` compatibility decision.

## Stats

`stats/StatRegistry` publishes stable stat definitions and defaults.
`stats/StatResolver` is the only owner of the seven modifier stages and returns
an immutable `StatSnapshot` for a specific simulation tick. Consumers use
snapshot values and explanations; they do not calculate or cache alternative
final values.

Condition systems supply active stable IDs. Conversion is simultaneous and
non-cascading, while priority and source ordering make conflict resolution
independent of modifier input order.

## Combat damage

`combat/DamagePipeline` is the only owner of hit-damage arithmetic and the only
publisher of immutable `DamageResult` values. Callers construct a validated
`DamageContext` from resolved stats and an externally sampled combat critical
roll. Abilities, items, statuses, entities, and presentation consume contexts
or results; they must not implement alternate damage formulas.

Damage remains floating point across all stages. Health mutation uses only
`DamageResult.committed_amount()`, which rounds the summed final components
once. Conversion is simultaneous and non-cascading, and every result retains
component, mitigation, and source provenance.

## Combat events

`events/CombatEventQueue` is the only publisher and executor of combat events.
Handlers return immutable emission descriptions; they never invoke proc logic
or enqueue children recursively. The queue owns monotonic IDs, FIFO execution,
stable emission ordering, chain depth, self-reentry policy, and per-tick budget
diagnostics.

Root events start at depth zero. Depth eight is processable and depth nine is
denied. A trigger cannot appear twice in one chain trace unless its definition
explicitly allows self-reentry. Budget exhaustion fails the process result and
retains pending events instead of silently dropping them.

## Abilities and effects

`abilities/AbilityDefinition` owns cost, cooldown, cast timing, targeting,
delivery, an ordered effect DAG, and cumulative rank milestones. Effects use
six explicit schemas: damage, status, movement, projectile, persistent entity,
and event. Rank milestones replace stable effect IDs and every cumulative graph
is validated before publication.

`abilities/AbilityExecutor` is transactional and scene-independent. Damage
outputs resolve immediately through `DamagePipeline`; event outputs are
configured requests for `CombatEventQueue`; other effect kinds become typed
simulation commands for later state owners. A failed effect publishes no
partial outputs. Damage-type conversion modifiers enter only `DamageContext`
and are consumed exactly once by the damage pipeline.
