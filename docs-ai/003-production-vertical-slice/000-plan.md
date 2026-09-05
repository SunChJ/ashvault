# 003 — Production Vertical Slice: Plan

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-09-01 |
| **Primary refs** | [`DEVELOPMENT_TASKBOOK.md`](../../docs/DEVELOPMENT_TASKBOOK.md), [`ARPG_KERNEL_SPEC.md`](../../docs/ARPG_KERNEL_SPEC.md), GitHub Issues [#1](https://github.com/SunChJ/ashvault/issues/1)–[#48](https://github.com/SunChJ/ashvault/issues/48) |
| **Related** | [`docs/DEVELOPMENT_TASKBOOK.md`](../../docs/DEVELOPMENT_TASKBOOK.md), [`docs/ARPG_KERNEL_SPEC.md`](../../docs/ARPG_KERNEL_SPEC.md), [`002`](../002-numerical-combat-sketch/000-plan.md) |

## Background

Ashvault has a verified numerical sketch and a local Hero Siege research model,
but it does not yet have a production ARPG architecture. Extending the sketch
directly would couple simulation, presentation, content, and lifecycle state in
the same script and recreate the rule duplication identified during research.

The first production deliverable is a persistent single-player ARPG vertical
slice: Stormweaver prepares in a town, enters a seeded modular dungeon, defeats
a boss, returns with loot, changes the build, and repeats the loop in 20–30
minutes. The slice targets Windows and macOS and reserves authority boundaries
without implementing multiplayer.

## Goals

- Establish a decision-complete development taskbook and mirrored GitHub Issues.
- Define stable contracts for stats, combat, events, abilities, items, saves,
  deterministic RNG, simulation commands, and presentation snapshots.
- Build the production kernel independently from the numerical prototype.
- Validate active combat, persistent progression, rarity diversity, modular
  dungeons, combat feedback, and desktop performance in one playable loop.
- Use milestone exit gates instead of calendar promises.

### Non-goals

- Four campaign acts, additional classes, seasons, trading, online economy,
  multiplayer, gamepad, consoles, mobile, or final production art.
- Compatibility between the numerical prototype and production APIs.
- Redistribution or runtime use of third-party Hero Siege data.

## Design / Approach

Repository documentation is the design source of truth. GitHub Milestones and
Issues mirror executable work and acceptance criteria; they do not replace the
contracts. Work is sequenced through six gates:

```text
M0 Contracts -> M1 Kernel -> M2 Active Combat -----\
                              M3 Items & Save ------> M4 Dungeon Loop -> M5 Slice Release
```

The production boundary is:

```text
Commands -> Simulation -> Events/Snapshots -> Presentation
                 |
                 +-> Versioned Save DTO
```

Godot Resources define immutable content. Runtime instances and save DTOs are
not Resources that encode player ownership, and the SceneTree is never the save
schema. All damage is resolved by one pipeline. Proc effects enter a bounded
event queue. Named RNG streams make combat, loot, and dungeon generation
replayable and independently evolvable.

The slice proves item diversity with generated white, blue, and gold items;
target-farmable green items; narrow purple interactions; rule-changing red
uniques; and one partial-set experiment. High rarity is not a universal power
ceiling.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Extend the 704-line sketch | Rejected: it is intentionally disposable and combines simulation with rendering. |
| Implement co-op in the slice | Rejected: command, UID, and RNG boundaries are sufficient authority preparation. |
| Use a fixed dungeon | Rejected: modular authored rooms validate replayable content without full procedural-generation risk. |
| Build a full public demo | Rejected: representative combat feedback matters now; final environment and character art do not. |
| Track only in GitHub Issues | Rejected: protocol decisions and milestone gates need a durable repository source of truth. |
| Estimate calendar dates | Rejected: dependencies and relative S/M/L complexity are more honest before kernel throughput is known. |

## Validation

- Every executable task has one milestone, type, priority, size, dependencies,
  acceptance criteria, and validation instructions.
- All GitHub dependency references resolve to existing Issues.
- The taskbook, Kernel specification, milestone descriptions, and Issues agree.
- Product implementation is not started until M0 contracts pass review.

## Amendments

- Updated 2026-09-01: executable Issues must be delivered through linked PRs
  rather than direct pushes and manual closure — see
  [`002-pr-linked-delivery.md`](002-pr-linked-delivery.md).
- Updated 2026-09-01: the implemented M0 surface is compatibility-frozen before
  M1 begins — see [`003-m0-contract-freeze.md`](003-m0-contract-freeze.md).
- Updated 2026-09-01: combat, loot, and dungeon randomness use independently
  restorable named streams — see
  [`004-deterministic-rng-streams.md`](004-deterministic-rng-streams.md).
- Updated 2026-09-01: stats resolve through a registered seven-stage pipeline
  into immutable, explainable tick snapshots — see
  [`005-stat-resolution.md`](005-stat-resolution.md).
- Updated 2026-09-01: all hit damage resolves through one immutable staged
  context/result contract with single-point health rounding — see
  [`006-damage-pipeline.md`](006-damage-pipeline.md).
- Updated 2026-09-01: combat reactions expand through a deterministic FIFO
  event queue with bounded proc chains and explicit diagnostics — see
  [`007-combat-event-queue.md`](007-combat-event-queue.md).
- Updated 2026-09-01: abilities use immutable effect graphs, validated rank
  transforms, and transactional typed execution outputs — see
  [`008-ability-effects.md`](008-ability-effects.md).
- Updated 2026-09-01: runtime entities advance through atomic fixed-tick
  command batches and publish immutable presentation snapshots — see
  [`009-entity-command-snapshots.md`](009-entity-command-snapshots.md).
- Updated 2026-09-01: the production kernel is composed by a versioned headless
  combat CLI with deterministic replay and separate wall-clock observability —
  see [`010-headless-combat-replay.md`](010-headless-combat-replay.md).
- Updated 2026-09-01: M1 closes through a machine-readable correctness,
  determinism, architecture, and reference-performance gate — see
  [`011-m1-kernel-gate.md`](011-m1-kernel-gate.md).
- Updated 2026-09-01: M2 starts with action-mapped input commands and optional
  fixed-tick swept-AABB player movement — see
  [`012-player-input-movement.md`](012-player-input-movement.md).
- Updated 2026-09-02: M2 ability activation gains integer-tick cast phases,
  atomic cost/cooldown commitment, and data-driven cancellation rules — see
  [`013-cast-runtime.md`](013-cast-runtime.md).
- Updated 2026-09-02: M2 spatial delivery uses a transactional fixed-tick world
  for targeting, swept projectiles, areas, chains, and persistent pulses — see
  [`014-delivery-runtime.md`](014-delivery-runtime.md).
- Updated 2026-09-02: M2 statuses use an immutable catalog and transactional
  fixed-tick world for stacking, refresh, immunity, cleanse, expiry, and Shock
  modifiers — see [`015-status-runtime.md`](015-status-runtime.md).
- Updated 2026-09-02: M2 ordinary enemies extend the entity world with compact
  seek/attack state, typed attack intents, and transition-owned kill events —
  see [`016-enemy-runtime.md`](016-enemy-runtime.md).
- Updated 2026-09-05: M2 composes six authored Stormweaver abilities through
  shared cast, delivery, status, and damage contracts — see
  [017-stormweaver-abilities.md](017-stormweaver-abilities.md).
