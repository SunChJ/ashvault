# 003.010 — Headless Combat Simulation and Replay

## Context

M1-07 composes the production RNG, stats, ability, damage, combat-event, command,
and entity-state contracts without loading gameplay or rendered frames. It must
produce reproducible combat evidence while retaining real wall-clock tick
measurements for the M1 performance gate.

## Planned change

A repository CLI accepts explicit build, encounter, and command-replay JSON
files together with root seed, content version, simulation version, duration,
and output path. The wrapper resolves the pinned Godot executable and launches a
single headless `SceneTree` entrypoint. Input paths and every version are
explicit; no editor state, locale, current time, or presentation state may
influence combat.

`HeadlessCombatSimulation` is an infrastructure composition root. It constructs
immutable fixture abilities and stats, named RNG streams, the ability/damage
pipeline, the bounded event queue, and `EntityWorld`. Player cast-release
commands and authored encounter intervals create attacks. Damage reaches health
only as a validated `DamageResult` committed within the entity world's atomic
tick batch.

The output schema separates two domains:

```text
deterministic: inputs + combat counters + tick counters + final state/report hash
observed: captured time + runtime identity + measured tick-time percentiles
```

Replay and report hashes exclude timestamps, processor labels, and measured
microseconds. They include versioned inputs, named RNG state, entity state,
drained event progress, combat totals, and accepted command counts. Identical
inputs must publish identical deterministic sections; a changed seed, command,
version, build, or encounter is a distinct replay.

The simulation report is a new versioned schema. The frozen M0 performance
report remains schema version 1 and gains no incompatible fields. Existing
`PerformanceMetrics` aggregation is reused for the observed tick summary.

## Ecosystem review

| Candidate | Decision |
| --- | --- |
| Godot headless `SceneTree`, `OS` arguments, `JSON`, `HashingContext`, and `Time` | Adopt. These APIs already support the required CLI lifecycle, deterministic encoding, hashing, and isolated observation. |
| Existing Ashvault production kernel and performance aggregator | Adopt and compose; the simulator must exercise the authoritative rules rather than duplicate formulae. |
| [`SnoringCatGames/godot-rollback-netcode`](https://github.com/SnoringCatGames/godot-rollback-netcode) | Reject for this slice. It targets multiplayer prediction/reconciliation through Nodes and autoloads; multiplayer and rollback buffers are non-goals. |
| Godot 4 Asset Library replay/rollback packages | None matched the offline deterministic combat-report boundary during review. |
| Add a Python JSON Schema dependency | Reject. The repository has no Python dependency manifest, and its existing schema plus standard-library validator pattern is sufficient. |

## Validation

- Run identical build, encounter, replay, seed, version, and duration inputs in
  independent simulations and compare deterministic reports and golden hashes.
- Change one replay command and one seed independently; both must change the
  replay state hash without invalidating the report schema.
- Reject incompatible versions, malformed fixtures, late/impossible commands,
  and invalid damage commits without publishing partial tick state.
- Validate the generated report with the machine-readable schema validator.
- Run the unified local suite and macOS/Windows CI matrix.

## Current state

Implementation and local validation are complete for M1-07. The two-second
fixture replay publishes state hash
`650d204d9ae61efcab7c731456e66db45968ba61f2af16e0b0d3494a24aea6f8`
and deterministic report hash
`d8e0ef3d3b1791c45f3d9366f67ac40c49864c76d24008f683b35207319dea64`.
Changing either the replay command or root seed changes the state hash.

The unified suite passes with 42 Python tests, eleven production GDScript
contract suites, both machine-readable report validators, prototype
regressions, and the main-scene smoke test. The generated combat report passes
`simulation-report.schema.json`, and the editor scan confirms complete unique
UID coverage for all 61 GDScript files. The linked PR and #13 remain the
authoritative delivery state; macOS and Windows CI are pending that PR.
