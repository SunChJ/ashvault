# 003.008 — Ability Definitions and Effect Execution

## Context

M1-05 connects immutable authored ability content to stats, damage, and combat
events without introducing entity mutation or SceneTree dependencies. The
boundary must support later item transforms without item-name branches and must
prevent damage conversion from being consumed by both stat and hit resolution.

## Change

`AbilityDefinition` extends the production content definition and declares a
resource cost, cooldown ticks, cast/recovery ticks, targeting mode, delivery
mode, an ordered effect graph, and rank milestones. Effect definitions are
immutable Resources with stable IDs, tags, dependency IDs, and one of six
explicit schemas:

1. Damage: authored/scaled damage components, hit modifiers, and critical stat
   IDs.
2. Status: status definition, duration ticks, and stack count.
3. Movement: movement mode, distance, and duration ticks.
4. Projectile: projectile definition, speed, and lifetime ticks.
5. Persistent entity: entity definition and duration ticks.
6. Event: event type and a validated JSON-compatible payload.

Dependencies form a directed acyclic graph. Independent effects retain authored
order; dependencies execute first. Missing dependencies, duplicate IDs, cycles,
and delivery modes without their required effect kind reject the entire
definition.

Rank milestones contain stable replacement transforms. A replacement retains
the target effect ID but may change its typed fields or dependencies. Milestones
apply cumulatively by ascending minimum rank. Every cumulative graph is
validated during ability configuration, so runtime rank resolution cannot
publish an invalid graph.

`AbilityExecutor` is scene-independent and transactional. It resolves the rank
graph against an immutable execution context and returns no outputs if any
effect fails. Damage effects build a `DamageContext` and invoke
`DamagePipeline`; event effects build a `CombatEventRequest`; status, movement,
projectile, and persistent effects produce typed simulation commands. The
caller commits successful commands or enqueues event requests afterward, so a
late validation failure cannot partially mutate simulation state.

Damage-type conversion has one owner: modifiers that convert hit components
enter `DamageContext` and are consumed only by `DamagePipeline`. Ability damage
components may read scalar values from `StatSnapshot`, but the executor never
pre-applies a conversion and never translates the same source into both stat
and damage conversion stages.

## Alternatives and decisions

| Alternative | Decision |
| --- | --- |
| Let each ability script execute custom logic | Rejected because damage, event safety, and item interactions would diverge. |
| Use arbitrary dictionaries for every effect | Rejected because invalid fields would cross the simulation boundary undetected. |
| Mutate entities directly during effect execution | Rejected because #12 owns entity state and transactional command application. |
| Enqueue events while resolving effects | Rejected because a later invalid effect could leave a partially committed execution. |
| Branch on item IDs in the executor | Rejected; items and passives may supply validated transforms and modifiers only. |
| Support general insert/remove transforms now | Rejected; stable replacement transforms cover rank milestones without premature graph-editing complexity. |

## Validation

- Validate definitions expose cost, cooldown, cast timing, targeting, delivery,
  and stable ordered effects.
- Execute a synthetic ability containing all six effect kinds headlessly.
- Verify damage uses the stat snapshot and unified damage pipeline exactly once.
- Verify event outputs are configured queue requests rather than recursive calls.
- Test missing dependencies, duplicate IDs, cycles, and delivery constraints.
- Test cumulative milestone replacement and invalid milestone graphs.
- Test execution failure publishes no partial outputs.
- Enforce that the ability executor contains no item-ID branches.
- Run the unified local suite and macOS/Windows CI matrix.

## Current state

Implementation and local validation are complete for M1-05. The unified suite
passes with 34 Python tests, nine production GDScript contract suites,
performance report validation, prototype regressions, and the main-scene smoke
test. The editor scan confirms complete unique UID coverage for all 51
GDScript files. The linked PR and #11 remain the authoritative delivery state.
