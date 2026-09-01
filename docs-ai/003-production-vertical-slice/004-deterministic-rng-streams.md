# 003.004 — Deterministic RNG Streams

## Context

Combat rolls, loot generation, and dungeon assembly must be replayable without
coupling their call counts. A single generator would make an added loot roll
change later combat or dungeon results. Godot's `RandomNumberGenerator` exposes
restorable `seed` and `state`, but similar seed values do not have strong
avalanche behavior and JSON numbers are unsafe for arbitrary 64-bit state.

## Change

One run owns exactly three named streams: `combat`, `loot`, and `dungeon`.
`RngStreams` is the only production entrypoint for obtaining them.

- Each stream receives the first 56 bits of SHA-256 over the versioned domain,
  root seed, and stream name. This provides stable domain separation without
  signed 64-bit overflow.
- Each stream wraps its own Godot `RandomNumberGenerator`; gameplay code cannot
  instantiate generators or call global random functions directly.
- Snapshot schema version 1 stores the root seed plus each stream's seed and
  current state as canonical decimal strings, preserving exact values through
  JSON serialization.
- Restore validates the complete snapshot before mutation, rejects missing or
  extra streams/fields, sets seed before state, and preserves existing stream
  handles on success.

The derivation domain, stream names, snapshot shape, and Godot RNG behavior are
part of `simulation_version`. A breaking change requires a version change and
explicit replay/save compatibility handling.

## Alternatives and decisions

| Alternative | Decision |
| --- | --- |
| One generator for the whole run | Rejected because unrelated subsystem call counts would change each other's sequences. |
| Root seed XOR fixed salts | Rejected because Godot documents weak avalanche behavior for similar seeds. |
| Serialize seed/state as JSON numbers | Rejected because external JSON tooling may round integers beyond 53 bits. |
| Restore only state | Rejected because Godot requires seed initialization before restoring state. |

## Validation

- Lock a golden sequence for the pinned Godot and simulation versions.
- Test identical seed replay and cross-stream call-count isolation.
- Test exact snapshot round-trip through JSON.
- Test transactional rejection of malformed, missing, extra, and mismatched
  stream state.
- Enforce that production code outside the RNG wrapper cannot instantiate
  `RandomNumberGenerator` or call global random functions.
- Run the unified suite locally and on the macOS/Windows CI matrix.

## Current state

Implementation and local validation are complete for M1-01. The unified suite
passes with 33 Python tests, five production GDScript contract suites,
performance report validation, prototype regressions, and the main-scene smoke
test. The linked PR and #7 remain the authoritative delivery state.

During validation, an intentionally failing golden vector exposed that
`SceneTree.quit(1)` called from `_init()` returned process status 0 under Godot
4.7.2, while parse errors can return 0 before any entrypoint runs. All scripted
test and benchmark entrypoints now defer execution to `_run()`; the unified
runner also rejects Godot `ERROR:` output. CI contract tests enforce both paths.
The intentional runtime failure was rerun and returned status 1 before the
accepted golden vectors were locked.
