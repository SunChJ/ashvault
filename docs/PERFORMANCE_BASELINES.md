# Simulation Performance Baselines

## Contract

Performance reports conform to
[`performance-report.schema.json`](../performance/performance-report.schema.json)
and are validated by `tools.performance.validate_report`. Each report records:

- P50, P95, P99, mean, and maximum simulation tick time in microseconds.
- Minimum, mean, and peak entity counts.
- The exact workload, runtime, simulation version, and capture timestamp.
- `rendering_enabled: false` as an explicit headless-execution invariant.

Percentiles use the nearest-rank method. Reports with missing fields, invalid
types, inconsistent sample counts, enabled rendering, or non-monotonic
percentiles fail validation.

## M0 bootstrap workload

`synthetic.fixed_tick.v1` advances compact position and velocity arrays for 120
actors and 500 projectiles. It runs 120 warmup ticks followed by 900 measured
ticks directly from a headless `SceneTree`; it does not load a scene, await a
rendered frame, or call presentation code.

This workload validates the measurement pipeline and provides an early
regression anchor. It is not evidence that production combat meets the 8 ms P95
slice target. Its schema remains frozen; production combat uses the separate
simulation report contract below.

## Production combat replay

`combat.headless.v1` composes the production RNG, stats, ability, damage,
combat-event, command, and entity-state modules. Its report conforms to
[`simulation-report.schema.json`](../performance/simulation-report.schema.json)
and separates deterministic input/combat/replay fields from capture time,
runtime identity, and measured tick duration. Identical explicit inputs produce
the same state and report hashes on every supported platform.

## Commands

Run the complete validation suite:

```sh
python3 tools/ci/run_tests.py
```

Capture and validate an individual report:

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --path project-ashvault \
  --script res://tools/performance/run_baseline.gd \
  -- \
  --output /tmp/ashvault-performance.json
python3 -m tools.performance.validate_report /tmp/ashvault-performance.json
```

Run and validate the production combat replay:

```sh
python3 -m tools.simulation.run_headless \
  --build project-ashvault/tests/fixtures/headless_build.json \
  --encounter project-ashvault/tests/fixtures/headless_encounter.json \
  --replay project-ashvault/tests/fixtures/headless_replay.json \
  --root-seed 424242 \
  --simulation-version 1 \
  --content-version 1 \
  --duration-seconds 2 \
  --output /tmp/ashvault-simulation.json
python3 -m tools.simulation.validate_report /tmp/ashvault-simulation.json
```

The CI suite writes its transient report to
`.artifacts/performance/ci-baseline.json` and its combat replay report to
`.artifacts/simulation/ci-report.json`. CI validates structure and invariants;
the M1 kernel gate also enforces a generous 8,000 μs P95 smoke bound. Shared
runners are not treated as stable performance reference machines.

## M1 kernel gate

[`kernel-gate-v1.json`](../performance/kernel-gate-v1.json) freezes the runtime
versions, fixture identity, replay hashes, structural limits, and two timing
bounds:

| Scope | Workload | P95 bound | Meaning |
| --- | --- | ---: | --- |
| Portable CI smoke | 2 entities, 120 ticks | 8,000 μs | Detect catastrophic kernel regressions across heterogeneous runners. |
| Apple M1 Pro reference | 2 entities, 120 ticks | 1,000 μs | Bound the named local reference profile with headroom over repeated captures. |

The archived M1 Pro production capture records P50/P95/P99 of 19/567/772 μs
and a maximum of 880 μs. Ten independent processes observed P95 values from 214
to 567 μs; the most conservative capture was archived. Validate a fresh report
against both the manifest and archived capture with:

```sh
python3 -m tools.performance.validate_kernel_gate \
  performance/kernel-gate-v1.json \
  /tmp/ashvault-simulation.json
```

This fixture is correctness-oriented and does not represent 120 enemies plus
500 projectiles. M5-06 owns that density workload, Windows reference-profile
capture, and the 30-minute soak gate.

## Archived M0 bootstrap reference capture

[`m1-pro-godot-4.7.2.json`](../performance/baselines/m1-pro-godot-4.7.2.json)
is the initial local reference capture:

| Field | Value |
| --- | ---: |
| Processor | Apple M1 Pro |
| Model | MacBookPro18,3 |
| Memory | 16 GB |
| Godot | 4.7.2 stable official |
| Actors / projectiles | 120 / 500 |
| Samples | 900 |
| P50 / P95 / P99 | 82 / 92 / 184 μs |

Keep historical baselines immutable. A changed benchmark contract receives a
new `benchmark_id`; a new measurement receives a new file rather than replacing
prior evidence.
