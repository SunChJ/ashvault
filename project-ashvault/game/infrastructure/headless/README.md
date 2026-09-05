# Headless Build comparison

`BuildLoadout` validates versioned JSON and resolves a baseline loadout against
an already published `ItemWorld`. `BuildSimulation.run(build, world, bonuses)`
loads that Build without a scene or UI. `compare` evaluates every compatible-slot
item in the supplied pool as a single-slot replacement; other baseline slots
remain fixed. Both return `{error, report}` on success and `{error}` on failure.
Callers retain ownership of the candidate world, which is never mutated.

## Build V1

[build.schema.json](build.schema.json) describes the JSON shape. Runtime validation
also checks published references, equipment legality, and actual cast execution.
The four representative inputs live in `tests/fixtures/builds/`.

- `build_id`: stable identity; `schema_version`: exactly 1.
- `skills`: Stormweaver skill names to integer ranks 1–20. These are explicit
  benchmark ranks, not a progression allocation or proof of an earned point budget.
- `rotation`: strictly increasing `{tick, skill}` cast starts. Releases follow the
  authored cast time. The command runtime rejects overlaps, cooldown violations,
  and insufficient resources. Every release must fit inside the duration.
- `duration_ticks`: 1–3600 at 60 Hz; `root_seed`: signed 32-bit integer.
- `base_stats`: explicit power, critical chance, critical multiplier, and armor.
  Resolve progression/passives upstream when constructing these benchmark inputs.
- `conditions`: fixed stat-resolution conditions for the entire benchmark.
  Combat Shock/Ward stacks remain owned by the real status runtime.
- `loadout`: 1–8 standard equipment slots. Each selector is either `{uid}` or
  `{bases, affixes, rarities}`. Empty constraint arrays mean unrestricted;
  every named affix is required. References must exist. The lexical lowest UID
  satisfying all constraints is the baseline. No random rolls or global search
  occur. An illegal selected combination fails even if another combination exists.
- `objective`: `damage` maximizes dealt damage, `defense` minimizes damage taken,
  or `procs` maximizes player critical-trigger notifications. Ties remain explicit.

Constraints select the baseline only. Comparisons deliberately include the entire
slot-compatible pool, including red/set challengers, rather than hiding them behind
baseline preferences. Candidate errors remain visible and make the rarity gate
inconclusive. At most 64 authored candidate instances may enter a comparison.
Multi-slot exchanges, changing a two-handed weapon together with an off-hand,
and global set optimization are outside this local comparison contract.

## Runtime and evidence

The fixed `arena.build_comparison.v1` runs `StormweaverCombat`, including projectile
travel, chaining, Shock, Nova, Ward, totem pulses, enemy attacks, and seeded critical
rolls. One player and four targets start at one million health; the player has
10,000 mana. Positions are 0/50/100/150/200 on the x axis. Target 2 attacks every
30 ticks using the existing ordinary-enemy runtime. Armor mitigates that arena's
lightning attack through `DamageModifier.DEFENSE`. Player gear never changes enemy
stats. Actor or target death fails the comparison to avoid capped damage evidence.

`StormweaverCombat.configure` accepts an optional immutable player `StatSnapshot`
and configured mitigation modifiers. It rebases player stats to each execution
tick, retains default enemy stats, and includes injected inputs in its state hash.
Default showcase callers retain their original golden hashes.

Reports include actual damage/DPS, incoming damage, player hits/criticals, Shock
peak, Ward ticks, event counts, final state hash, resolved stats and sources, full
item records, and rarity composition. `proc_events` counts player `event.critical`
notifications from the bounded event queue. It does **not** claim item-specific proc
damage or execute the item's declared interaction/rule IDs. Those declarations are
reported as `special_effects`; final named-item rules and tuning remain M5 work.

## Rarity gate

`RarityValueGate.evaluate(reports)` requires all four reference Build identities,
all occupied baseline slots, finite successful candidate metrics, and at least
one red/set challenger per slot. It recomputes scores from measured metrics;
cached winner IDs cannot conceal a red/set tie. Blue, gold, green, and purple must
each have at least one best-slot candidate. A Build fails when every compared slot
has a red or set candidate tied for best or better.

This is evidence within the authored pool and a fixed baseline, not a proof of a
global optimum or release balance. The seven-weapon regression pool (plus two head-slot candidates)
intentionally exposes distinct tradeoffs for the four reference skill profiles.
M5 must expand the content, legal progression budgets, slots, and encounter coverage
before using these results as the final rarity-value release gate.

## Reproduction

Run from the repository root (substitute the pinned Godot executable):

```sh
godot --headless --path project-ashvault \
  --script res://tests/production/test_build_simulation.gd

godot --headless --path project-ashvault \
  --script res://tools/simulation/run_reference_builds.gd -- \
  --output /absolute/path/build-report.json
```

The second command loads all four JSON profiles against the representative pool,
writes full comparisons plus gate evidence, and exits 0 on pass, 1 on gate failure,
2 on usage error, 3 on simulation failure, or 4 on output failure. CI runs both
paths and writes `.artifacts/simulation/ci-builds.json` in its workspace.
The original `HeadlessCombatSimulation` and `tools/simulation/run_headless.py`
continue to accept their separate scalar replay fixture format unchanged.
