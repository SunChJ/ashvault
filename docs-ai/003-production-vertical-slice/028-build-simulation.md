# 003.028 — Build simulation and rarity-value gate

## Context

M3-09 requires exact-item and constrained loadouts, UI-independent simulation,
comparable damage/defense/proc evidence, and a machine-checkable rarity gate.
The existing Stormweaver runtime already owns the four reference skill paths;
its fixed player stats currently prevent equipment comparisons.

## Change

- Load a strict versioned JSON Build against a published candidate ItemWorld.
  Resolve exact UIDs or base/affix constraints deterministically and reject
  impossible equipment combinations through EquipmentState.
- Inject immutable player stats and mitigation into StormweaverCombat while
  preserving the default showcase and keeping enemy stats independent.
- Simulate the actual four skill paths in a fixed seeded arena; compare
  one-slot candidate substitutions under an explicit objective, retaining ties,
  metrics, item records, and rarity composition.
- Gate coverage of blue/gold/green/purple best-slot candidates and reject a
  build whose every occupied slot can be best-filled by red/set candidates.
- Add four representative regression profiles and adversarial dominance cases.
  These prove the harness, not M5's final content balance or a global optimum.

## Decisions

Reuse native JSON, immutable Resources, EquipmentState, and StormweaverCombat.
The installed GLoot adapter is a presentation boundary, not an authoritative
optimizer. Existing delivery/status/event primitives already cover the required
simulation; no new dependency, solver, editor plugin, or generator is warranted.
The [official GLoot listing](https://godotengine.org/asset-library/asset/1368)
and [native RefCounted contract](https://docs.godotengine.org/en/latest/classes/class_refcounted.html)
were checked alongside the installed adapter; neither requires replacing the
existing project-owned deterministic combat/equipment kernels.
Candidate comparison is deliberately local to an authored finite pool and fixed
baseline. Global search and final passive/item authoring remain later work.

## Validation

- Focused Build fixture passed: four real skill paths, equivalent exact/constraint
  loadouts, candidate ordering, immutable pool, malformed references, illegal
  casts, multi-slot composition, and two-handed/off-hand exclusion.
- Measured best weapon candidates: blue Arc Bolt damage 1314, gold Chain
  Lightning damage 1672, green Nova/Ward damage taken 40, and purple totem
  critical-trigger notifications 5 (seed 42, 240 ticks).
- An independently simulated overpowered red item fails the gate. Synthetic
  red/set ties, missing challengers, incomplete slots, invalid metrics, and
  failed candidates also fail. A useful red head slot in a mixed Build passes.
- Existing Stormweaver golden replay tests passed unchanged.
- `python3 tools/ci/run_tests.py` passed (49 Python tests and all Godot fixtures,
  including the reference JSON report CLI). Subsequent expanded multi-slot and
  injection-boundary fixtures passed the focused Build command.
- Windows/macOS CI is required before merge; results are recorded by the PR.

## Current state

Implemented. The maintained contract is
[headless/README.md](../../project-ashvault/game/infrastructure/headless/README.md).
The Build schema and four JSON profiles are independent of the older M1 scalar
replay schema. No dependency or UI integration was added. Proc evidence currently
counts actual critical-trigger notifications; item-specific interaction/rule
execution and release-quality item/passive balance remain M5 scope.
