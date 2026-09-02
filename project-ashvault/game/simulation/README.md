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

`abilities/AbilityLoadout` binds definitions and cast policies to actor slots.
Cast start validates without spending; a ready release atomically spends cost
and starts cooldown. Integer ready/recovery/cooldown ticks, movement policy,
manual cancellation, external interruptions, and cancel-into behavior are
owned by `EntityWorld`. Scene timers and animation state may mirror snapshots
but never advance this runtime.

## Spatial delivery

`delivery/DeliveryWorld` owns projectile movement, area selection, chain
ordering, persistent pulses, and authoritative hit publication at 60 Hz. It
consumes immutable target snapshots and delivery requests, then advances compact
`RefCounted` state without Nodes or physics-server callbacks.

Requests use globally increasing IDs. The world retains one request watermark,
one runtime-object allocator, and only active projectile/persistent state, so
deduplication does not grow with session length. Projectile collision uses swept
segment-circle tests ordered by contact time and target ID. Area and chain
selection use distance and target ID. Boundary contact is inclusive.

Presentation may consume active-state values and hit records. Godot State Charts
may mirror their phases, but presentation never selects targets, resolves
collision, advances pulses, or expires runtime objects. Ability composition
derives projectile speed and lifetime from its effect command when it creates a
delivery definition; those values must not become a second authored balance
source.

## Statuses

`statuses/StatusWorld` owns active status identity, stacks, expiry, immunity,
cleanse, and forced removal at the fixed-tick boundary. Immutable definitions
declare application-duration bounds and additive/replace/maximum stacking,
keep/reset/extend refresh, and cleansable/protected removal policies. Mutations
are globally increasing and transactional; the world retains one mutation
watermark rather than an unbounded history.

Active status IDs are published as damage conditions. Status damage templates
materialize ordinary `DamageModifier` values, so Shock and later ailments pass
through `DamagePipeline` instead of adding status-specific arithmetic. Applied
statuses publish `event.status_applied` requests for `CombatEventQueue`; status
code never invokes proc handlers recursively. State Charts may mirror status
state for UI or animation but cannot own simulation timing or mutation.

## Entity state, commands, and snapshots

`entities/EntityWorld` owns compact runtime entity state and advances through
explicit 60 Hz command batches. Commands are immutable DTOs. Each batch uses
copy-on-write staging, orders work by actor ID and client sequence, and commits
the entire tick only when every transition is valid. Rejection leaves tick,
entity state, and sequence state unchanged.

`movement/MovementEnvironment` owns optional arena bounds, static rectangular
obstacles, actor radius, and speed. It integrates living player movement once
per accepted 60 Hz tick using continuous X-then-Y axis sweeps. Inflated
obstacles prevent tunneling and allow deterministic wall sliding without scenes
or a physics server.

`snapshots/PresentationSnapshot` publishes runtime-ID-sorted immutable entity
views. Its SHA-256 state hash uses a versioned canonical array schema and is
identical whether presentation snapshots are requested or disabled. Worlds
without movement or loadouts retain the M1 hash schema; movement-only worlds
include canonical collision configuration in schema version 2. Loadout-enabled
worlds use schema version 3 and expose resource, cast/recovery progress, and
per-slot cooldowns for presentation. Effect execution remains a downstream
consumer of the observable released phase.
