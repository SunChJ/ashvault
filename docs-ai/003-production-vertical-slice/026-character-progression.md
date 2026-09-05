# 003.026 — Persistent character progression

## Context and plan

M3-07 owns character lifetime XP, earned skill points, skill ranks, and passive
allocations independently of run state. SaveGameV1 file persistence is the next
task; provide strict plain-data snapshots and atomic restore into unused state.

Frozen native progression and passive Resources author cumulative XP thresholds,
points per level, max skill rank, minimum levels, prerequisite ranks, and numeric
modifiers. Reuse the existing modifier implementation by extracting its common
Resource template into stats while preserving ItemStatEffect's script path and
ID prefix. Passives resolve through StatResolver; skill ranks select existing
AbilityDefinition milestones rather than implementing another ability executor.

XP rewards carry run IDs and monotonic per-run sequences retained across
snapshots, following the existing command watermark pattern. This stores one
watermark per run rather than one ID per kill reward. Multi-level
awards derive point budgets from the resulting level. Allocations only increase
and require the expected revision; explicit free respec clears both skill and
passive allocations and refunds their computed budget. Wrong revisions reject
replayed UI commands. Restore validates level budget, prerequisite graph, known
IDs, ranks, reward sequence watermarks, and numeric bounds before publishing.

The initial native curve supplies 20 levels and one shared point per level gain.
Skills start at rank one, with spent points adding ranks. Final passive content,
respec economy, run/combat UI wiring, and save file I/O remain downstream.
No dependency or generic skill-tree framework is added: existing Godot Resources,
RefCounted state, and shared modifier/ability systems fit this small graph.

## Validation plan

Headless fixtures cover exact XP thresholds, multiple level gains, level cap,
reward deduplication across run restore, allocation prerequisites/caps/budgets,
explicit respec and stale commands, deterministic replay, corrupt restore,
shared stat resolution rollback, and existing ability rank milestones. Follow
with the complete local suite and both platform CI checks.

## Outcome and validation

Implemented native curve/passive definitions, graph validation, revision-checked
allocation/respec, per-run XP watermarks, and atomic JSON restore. Extracted the
shared StatModifierTemplate while preserving ItemStatEffect resource paths and
item-specific IDs. Current behavior is documented in
[progression/README.md](../../project-ashvault/game/simulation/progression/README.md).

Passed the focused progression fixture and complete local
`python3 tools/ci/run_tests.py` suite (49 Python tests, all Godot contracts,
replay/performance gates, and scene smoke). Existing equipment and crafting
fixtures pass after template extraction. Progression fixtures verify cross-run
JSON restoration, deterministic replay, 20-level cap, shared point budget,
explicit respec, invalid stat rollback, and Ward's existing rank-five milestone.
Local full-suite evidence is `.artifacts/progression-validation.log` (ignored).

During the final dependency check, reviewed the Asset Library's
[Skill Editor](https://godotengine.org/asset-library/asset/5170) and
[Worldmap Builder](https://godotengine.org/asset-library/asset/2270).
Their advertised graph authoring/view facilities may fit a later passive UI;
this task needs character-lifetime transactional state and existing stat/ability
composition. No dependency was added. Candidate review occurred after the kernel
implementation; the existing-system inspection and native design preceded it.

No feature scope deviations. Save file I/O, final passive content, economy and
combat/UI composition remain downstream.
