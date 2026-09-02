# 003.014 — Deterministic Spatial Delivery Runtime

## Context

M2-03 must turn authored projectile and persistent-entity commands into compact
simulation state, while also resolving point areas and target chains. Collision,
target selection, lifetimes, and chain exclusion must not depend on scenes,
physics callbacks, rendering, or plugin state.

## Planned change

Add an independent `DeliveryWorld` that advances at the kernel's fixed 60 Hz
rate. Each tick receives immutable target snapshots and delivery requests. It
validates the complete batch before committing, sorts requests by stable request
ID, advances active runtime objects by runtime ID, and returns ordered immutable
hit records.

The four delivery definitions are data-driven:

| Kind | Authored behavior | Runtime behavior |
| --- | --- | --- |
| Projectile | speed, radius, lifetime, hit count | Swept segment-circle collision; earliest contact then target ID. |
| Area | radius, target limit | Resolves immediately by distance then target ID. |
| Chain | acquisition range, jump range, target count | Falls back from a lost initial target and excludes prior targets. |
| Persistent | pulse radius, lifetime, interval, target limit | Compact timed state that emits deterministic area pulses. |

Targets carry runtime ID, team ID, position, collision radius, and alive state.
Friendly targets and the source are excluded. Boundary contact is inclusive.
Requests and active states store stable definition IDs and scalar runtime data;
they never retain scene nodes.

Projectile and persistent runtime IDs come from one monotonic allocator owned by
the delivery world. Areas and chains are instantaneous and do not allocate an
active runtime object. A single request-ID watermark prevents replay without an
unbounded accepted-ID set. Presentation reads immutable active-state snapshots
and hit records; it does not perform collision queries.

## Integration boundary

`AbilityEffectCommand` remains the typed bridge from authored ability effects.
M2-06 composition will translate projectile/persistent commands plus their
ability delivery metadata into requests. A hit retains request, definition,
source, and target IDs so downstream effect execution can build the final
damage/status context without reselecting a target.

Godot State Charts may mirror delivery phases for animation and feedback. It
must not own target selection, collision, lifetime expiry, chain ordering, or
pulse timing. Gloot has no M2 delivery responsibility.

## Alternatives

| Alternative | Decision |
| --- | --- |
| `Area2D`, `CharacterBody2D`, or physics callbacks per delivery | Rejected: callback order and SceneTree lifetime would own authoritative results and scale with Node count. |
| Godot State Charts as delivery authority | Rejected: it is Node/signal based and belongs at the presentation boundary. |
| Add delivery state directly to `EntityWorld` | Rejected: player/entity command ownership and spatial delivery have different lifecycles and would create a growing aggregate. |
| Store full ability Resources in each runtime projectile | Rejected: runtime state needs compact, canonical IDs and independently versioned content lookup. |

## Validation

- Test inclusive collision boundaries and swept collision against tunneling.
- Test earliest-contact and target-ID tie-breaking.
- Test target loss, chain exclusion, jump range, and target limits.
- Test projectile/persistent lifetime and pulse boundaries.
- Test invalid batches and duplicate request IDs without partial state changes.
- Test canonical state equality across request and target input order.
- Exercise at least 120 live targets without one Node per delivery.
- Run the editor scan, unified local suite, and macOS/Windows CI matrix.

## Current state

Implemented for #17. `DeliveryWorld` and its immutable contracts cover all four
delivery types with transactional batches, compact active state, monotonic IDs,
swept collision, deterministic selection, exact tick lifetimes, and canonical
SHA-256 state hashing.

Focused delivery tests cover boundary contact, tunneling, target loss, chain
exclusion, lifetime/pulse boundaries, rollback, input-order invariance, and 120
targets. The repository architecture gate also rejects physics-server and
scene-collision types from production simulation code. Full local and CI results
are recorded in the delivery PR.
