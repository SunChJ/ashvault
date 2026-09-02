# 003.016 — Deterministic Ordinary Enemy Runtime

## Context

M2-05 needs ordinary enemies to acquire live players, navigate within arena
bounds, publish attack intent at an exact cadence, receive authoritative damage,
and die once. The density target requires compact simulation values rather than
one behavior tree, navigation agent, or complex Node per enemy.

## Planned change

Extend `EntityWorld` rather than creating a second owner for enemy position and
health. Immutable `EnemyDefinition` resources configure acquisition range,
movement speed, collision radius, attack range/cadence, and stable attack ID.
Each configured enemy receives a compact runtime value containing only actor ID,
current target ID, and next attack tick.

At each accepted 60 Hz tick:

1. validate and order player commands, cast interruptions, and damage results;
2. advance player state and commit damage through existing `DamageResult` values;
3. publish exactly one `event.kill` request for each alive-to-dead transition;
4. retain a valid target or reacquire the nearest live player by distance and ID;
5. move out-of-range enemies with the shared movement environment;
6. publish immutable attack intents when range and cooldown allow.

Damage results are ordered by target ID, origin event ID, and source ID. This
makes kill credit independent of caller collection order. Damage against an
already dead entity cannot publish another kill event. Enemy attacks remain
intent: M2-06/content composition converts an attack ID into the same
`DamageContext`/`DamagePipeline` path used by player abilities.

`MovementEnvironment` gains a parameterized resolver for actor-specific radius
and speed. Its existing resolver delegates to the parameterized form, preserving
the frozen player movement contract. Enemy movement stops at attack range and
uses the same continuous bounds/obstacle sweeps.
Enemy positions are quantized to `0.000001` world units at their authoritative
commit boundary so platform-specific vector normalization tails cannot enter or
accumulate in replay state.

`CommandBatchResult` gains immutable attack-intent and combat-event collections.
The original fields and call shape remain compatible. Entity hashes use a new
schema only when enemy profiles are configured, preserving all M1/M2 hashes for
worlds without enemy runtime state.

## Ecosystem decision

Godot's `NavigationServer2D`/`NavigationAgent2D` and LimboAI were evaluated.
Navigation maps and callback-driven avoidance are appropriate when M4 introduces
authored room topology, but would broaden the deterministic server boundary for
the current arena seek behavior. LimboAI v1.8.1 is actively maintained and MIT
licensed, but a behavior tree/HSM per ordinary enemy conflicts with the compact
120-enemy path. It remains a candidate for low-count elites and bosses that emit
high-level intents into the simulation kernel.

Godot State Charts may mirror enemy phases for animation. It does not own target
selection, movement, cooldowns, health, or death. Gloot has no M2 enemy role.

## Alternatives

| Alternative | Decision |
| --- | --- |
| Separate enemy world with duplicated position/health | Rejected: two authoritative owners would require fragile reconciliation. |
| NavigationAgent2D per enemy | Rejected for M2: Node/callback lifetime and avoidance ordering do not fit the compact deterministic path. |
| LimboAI behavior tree per ordinary enemy | Rejected for density; reserve it for low-count high-level decision makers. |
| Enemy code subtracts health directly | Rejected: all hit arithmetic and commit must remain `DamagePipeline` → `DamageResult` → `EntityWorld`. |
| Emit kill on every zero-health damage result | Rejected: only the alive-to-dead transition owns one kill event. |

## Validation

- Test bounded movement and attack-range stopping.
- Test inclusive contact range and exact attack cadence.
- Test target retention, target loss, and deterministic reacquisition.
- Test overkill, same-tick hit ordering, and duplicate-death suppression.
- Test attack intents and kill events are immutable typed values.
- Exercise 120 enemies without enemy Nodes and compare replay hashes across
  profile/entity/damage input order.
- Run the editor scan, unified local suite, and macOS/Windows CI matrix.

## Current state

Implemented for #19. `EntityWorld` now commits ordered damage, emits one kill
request per alive-to-dead transition, advances compact enemy target/cadence
state, and publishes immutable attack intents. `MovementEnvironment` supports
actor-specific speed/radius without changing its existing player resolver.

The focused suite covers bounds, range, cadence, target loss, overkill,
duplicate death, damage-order-independent kill credit, and an order-independent
120-enemy replay hash. The unified local suite and CI matrix remain the release
gate before merge.
