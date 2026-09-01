# Ashvault ARPG Kernel Specification

| | |
| --- | --- |
| **Status** | M0 contracts frozen |
| **Version** | 1.0 |
| **Runtime** | Godot 4.7.2 |
| **Targets** | Windows and macOS |

## 1. Purpose

This document defines the production boundary for Ashvault's first vertical
slice. The existing `project-ashvault/prototype/` scene remains a numerical
experiment and is not a production API.

The kernel must support long-lived ARPG content without duplicating rules in
skills, items, enemies, UI, saves, or scenes. Simulation is deterministic for a
fixed version, seed set, initial state, and command stream.

## M0 contract freeze

This specification contains both implemented foundations and normative design
for later milestones. Their status is explicit:

| Scope | Status |
| --- | --- |
| Sections 2–3 | Implemented and frozen in M0 |
| M0 performance report contract in section 12 | Implemented and frozen in M0 |
| Sections 5–6 | Implemented in M1-01/M1-02 and compatibility-controlled |
| Section 4, sections 7–11, production simulator behavior in section 12, and section 13 | Accepted for downstream implementation |

The frozen public surface is:

| Contract | Authoritative implementation | Compatibility key |
| --- | --- | --- |
| Production roots and dependency direction | `project-ashvault/game/README.md` | Kernel specification version |
| Stable IDs and registered tags | `project-ashvault/game/content/stable_id.gd`, `tag_registry.gd` | `content_version` |
| Transactional immutable catalog publication | `project-ashvault/game/content/content_definition.gd`, `content_catalog.gd` | `content_version` |
| Content, simulation, and save version fields | `project-ashvault/game/infrastructure/version_info.gd` | Individual version field |
| Performance aggregation and report shape | `project-ashvault/game/infrastructure/performance_metrics.gd`, `performance/performance-report.schema.json` | Report `schema_version` |
| Headless macOS and Windows validation entrypoint | `tools/ci/run_tests.py`, `.github/workflows/ci.yml` | CI workflow contract |

Breaking changes to a frozen contract require its compatibility key to change,
together with updated tests and an explicit migration or compatibility policy.
Compatible additions may retain the current version. Downstream sections become
implemented only through their taskbook gates; specification text alone is not
an implementation claim.

## 2. Architectural boundary

```mermaid
flowchart LR
    I[Input Adapter] --> C[Player Commands]
    C --> S[Simulation]
    D[Content Definitions] --> S
    S --> E[Combat Events]
    S --> P[Presentation Snapshots]
    E --> V[VFX / Audio / UI]
    P --> V
    S <--> G[Versioned Save DTO]
    S --> H[Headless Simulator]
```

- `Simulation` owns authoritative gameplay state.
- `Presentation` may interpolate and decorate state but cannot mutate it.
- Godot scenes compose lifecycle and visuals; they do not define combat rules.
- Godot Resources are immutable authored definitions.
- Runtime instances are plain simulation objects identified by stable IDs.
- Save DTOs contain data, not Nodes, Resources, callables, or scene paths.

## 3. Identity, tags, and versions

Stable content IDs use lowercase dotted names, for example
`ability.stormweaver.arc_bolt`. IDs are never derived from localized names or
filesystem locations.

An ID contains at least two dot-separated segments. Each segment starts with a
lowercase ASCII letter and may then contain lowercase ASCII letters, digits, or
underscores. Leading/trailing dots, empty segments, hyphens, whitespace, and
uppercase characters are invalid; values are rejected rather than normalized.

Tags use a validated registry and lowercase dotted names, such as
`damage.lightning`, `delivery.projectile`, and `event.kill`. Unknown IDs or tags
fail content validation before a run starts.

Tag registration is atomic for a batch: any invalid or duplicate tag rejects
the entire batch. The registry is frozen before a validated catalog is
published, and later registration attempts fail rather than mutate live rules.

The following versions are independent:

- `content_version`: authored definition compatibility.
- `simulation_version`: deterministic rules and replay compatibility.
- `save_schema_version`: serialized DTO layout and migration compatibility.

External research IDs never become canonical content IDs.

### Catalog publication

Catalog loading is transactional. Definitions are staged, then the complete
set is validated for ID syntax, duplicate IDs, registered tags, dependency
existence, duplicate dependencies, and dependency cycles. Any error rejects the
entire catalog without freezing inputs or publishing partial lookup state.

A successful load freezes every definition and the tag registry before making
the catalog available to a composition root. Definition array properties return
copies, and later scalar assignment or reconfiguration cannot mutate published
content. Gameplay may start only with a successfully loaded catalog.

## 4. Commands and simulation clock

Simulation advances on a fixed tick. Presentation frame rate does not determine
combat results. Input adapters emit commands containing:

```text
tick
actor_id
command_type
aim_vector
ability_slot
client_sequence
```

The slice supports movement, aim, cast start, cast release, and cancel. Unknown,
late, impossible, or duplicate commands are rejected with a diagnostic result;
they do not partially mutate state.

The `client_sequence` field is reserved for future authority validation. It does
not imply networking in the slice.

## 5. Deterministic RNG

Every run owns named RNG streams:

- `combat`: crits, proc rolls, and combat variance.
- `loot`: rarity, affix, and roll generation.
- `dungeon`: room graph and encounter selection.

Each stream exposes seed and serializable state. Adding a loot roll must not
change dungeon generation. Gameplay code may not use global random functions.

`RngStreams` owns all production randomness. It derives each stream seed from
the first 56 bits of SHA-256 over
`ashvault.rng.v1|<root_seed>|<stream_name>`, then owns one wrapped Godot
`RandomNumberGenerator` per stream. Production code outside that wrapper may
not instantiate `RandomNumberGenerator`; consumers acquire streams by their
registered names and unknown names return no stream.

Snapshot schema version 1 is JSON-safe and exact:

```text
schema_version
root_seed: canonical signed decimal string
streams:
  combat|loot|dungeon:
    name
    seed: canonical signed decimal string
    state: canonical signed decimal string
```

Restore requires exactly the registered streams and fields, validates derived
seeds, and rejects the complete snapshot before mutation on any error. It sets
each generator's seed before restoring its state and preserves already-acquired
stream handles. Decimal strings avoid precision loss in JSON implementations
that represent numbers with fewer than 64 integer bits.

Determinism is guaranteed only within the same `simulation_version` and
`content_version`. The derivation domain, names, snapshot shape, golden
sequences, and underlying Godot RNG behavior are simulation compatibility
contracts.

## 6. Stats and modifiers

A modifier contains:

```text
stat_id
operation
value
source_id
condition_id?
priority
target_stat_id? # CONVERSION only
```

Supported operations resolve in this order:

1. `BASE`
2. `FLAT`
3. `INCREASED`
4. `MORE`
5. `CONVERSION`
6. `OVERRIDE`
7. `CAP`

The registered default value is an implicit base. Explicit `BASE` and `FLAT`
values add in their respective stages. `INCREASED` values add within one bucket
and multiply once by `1 + bucket`; each `MORE` value multiplies by `1 + value`.

Modifiers resolve by descending numeric priority then ascending `source_id`.
A source may contribute at most one modifier for the same stat, operation, and
condition. Duplicate identities are validation errors rather than insertion
order tie-breaks.

Conversion values are fractions from 0 through 1 and require a distinct target
stat. A source stat allocates at most 100% in stable modifier order. All
converted amounts use the pre-conversion snapshot and apply simultaneously, so
incoming conversion cannot cascade during the same stage. The highest
precedence active `OVERRIDE` wins; remaining overrides are recorded as
shadowed. Every `CAP` is a maximum constraint and applies after the override.

Condition evaluation is external to stat resolution. The resolver receives the
active stable condition IDs and records inactive conditional modifiers rather
than silently discarding them.

Stat aggregation produces an immutable snapshot for one simulation tick.
Definitions contribute modifiers but never write final values directly. A
snapshot owns copies of final values and per-stat explanations containing
applied sources, skipped sources with reasons, conversion allocation, and
incoming conversion. Callers receive deep copies and cannot mutate the
published tick state.

Operation ordinals, ordering, conversion semantics, priority direction, and
snapshot fields are `simulation_version` compatibility contracts.

## 7. Damage pipeline

All attacks create a `DamageContext`; only the pipeline creates a
`DamageResult`.

```text
source_entity
target_entity
ability_id
origin_event_id
tags
base_components[]
modifiers[]
```

Resolution order is:

```text
base + flat
-> increased
-> more
-> conversion
-> critical
-> defense
-> resistance and penetration
-> conditional modifiers
-> final clamps and rounding
```

Damage is stored as floating point during resolution and rounded once when
committed to health. Negative final damage is forbidden; healing is a distinct
effect type. A result records component breakdown, mitigated amount, critical
state, and contributing source IDs for debugging and simulation reports.

Skills, items, status effects, enemies, and UI cannot implement alternative
damage math.

## 8. Combat events and proc safety

Events are queued rather than recursively executed. Every event contains:

```text
event_id
chain_id
depth
event_type
source_entity
target_entity?
source_definition
tags
payload
```

The default maximum proc depth is 8. A trigger cannot react to another event
created by the same trigger in the same chain unless its definition explicitly
sets `allow_self_reentry`. The queue has a per-tick budget; budget exhaustion
fails the simulation test and emits a diagnostic in development builds.

Core event types include cast, hit, critical, damage, status applied, death,
kill, block, dodge, item dropped, and item picked up.

## 9. Abilities and effects

An `AbilityDefinition` declares tags, cost, cooldown, cast timing, targeting,
delivery, and an ordered effect list. Effects may deal damage, apply a status,
move an entity, spawn a projectile or persistent entity, or emit an event.

Ability ranks select data values or milestone behaviors. They do not branch on
item names. Items and passives modify abilities through tags, modifiers, or
validated effect transforms.

The Stormweaver slice binds:

| Input | Ability | Required kernel coverage |
| --- | --- | --- |
| LMB | Arc Bolt | Aimed projectile and critical hit |
| RMB | Chain Lightning | Target chain and shock |
| Q | Thunder Nova | Player-centered area |
| E | Static Ward | Timed defensive status |
| R | Storm Totem | Persistent casting entity |
| Space | Tempest Dash | Movement, invulnerability window, cancel rules |

## 10. Items and rarity semantics

`ItemDefinition` is immutable authored content. `ItemInstance` contains:

```text
uid
definition_id
item_level
rarity
affixes[]
rolls[]
sockets[]
quality
metadata
```

UID creation belongs to the simulation boundary. Copies retain definition IDs
but never reuse UIDs.

The slice uses these generation rules:

| Rarity | Role |
| --- | --- |
| White | Base, quality, sockets, runeword eligibility, crafting potential |
| Blue | At most two affixes, higher individual tier ceiling, cheapest targeted reroll |
| Gold | At most four affixes and broad emergent combinations |
| Green | Target-farmable fixed implicit plus two or three random affixes |
| Purple | Narrow reliable interaction plus bounded random rolls |
| Red | Rule-changing unique with no universal stat budget advantage |
| Set | Individual competitive pieces with useful 2/3/4-piece thresholds |

The authored slice contains 24 ordinary bases, 6 green items, 8 purple items, 8
red items, and 4 set pieces. Generated white, blue, and gold items reuse the 24
bases. It also contains 36 affixes, 6 runes, and 3 runewords.

## 11. Save contract

`SaveGameV1` contains character, inventory, progression, world-run, settings,
RNG, and version DTOs. Saves use atomic temporary write plus rename and retain
one last-known-good backup.

Loading follows:

```text
read -> structural validation -> checksum validation -> migration chain
-> content reference validation -> simulation reconstruction
```

A failed primary save attempts the backup and reports recovery. Missing content
references are errors during development; release policy must be explicit before
content removal. Migrations are forward-only and individually tested.

## 12. Headless simulator and observability

The simulator accepts a build definition, encounter definition, seeds,
simulation version, and duration. Output is machine-readable and includes DPS,
damage mix, critical rate, proc rate, kills per second, damage taken, event
depth, entity counts, and tick-time percentiles.

Every damage result and generated item must be explainable by source IDs. Debug
traces are opt-in so production-density tests do not pay their allocation cost.

Performance reports use a versioned machine-readable contract with runtime and
workload metadata, sample count, entity-count statistics, and nearest-rank P50,
P95, and P99 tick times. The harness advances simulation directly under a
headless `SceneTree`; loading or awaiting rendered frames is forbidden. The M0
synthetic fixed-tick workload validates this reporting path and is replaced by
the production headless combat simulation in M1 without changing the report
contract.

## 13. Performance and compatibility targets

The slice target is 1080p at 60 FPS with 120 live enemies and 500 projectiles.
Simulation P95 must remain at or below 8 ms on an Apple M1 Pro and on the
Windows reference profile (Ryzen 5 3600, GTX 1660, 16 GB RAM). A 30-minute soak
must not show unbounded entity, event, or allocation growth.

Production code may use Nodes for low-count composition and presentation. High
count enemies, projectiles, and transient effects use compact simulation-owned
state and batched queries.

Deterministic replays and saves are not promised across a
`simulation_version` change without an explicit compatibility adapter.
