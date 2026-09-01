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
