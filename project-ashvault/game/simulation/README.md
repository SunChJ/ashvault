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
