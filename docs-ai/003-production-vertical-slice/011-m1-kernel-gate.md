# 003.011 — M1 Kernel Correctness and Performance Gate

## Context

M1-08 closes the production-kernel milestone only when its correctness,
determinism, architecture, and performance evidence can be evaluated without
editor state or subjective review. Shared CI runners remain useful correctness
and catastrophic-regression signals, but they are not reference performance
hardware.

## Planned change

A versioned machine-readable gate manifest freezes the M1 runtime versions,
fixture identity, deterministic replay hashes, portable smoke threshold, Apple
M1 Pro reference threshold, event-depth bound, and entity-count bound. A
dependency-free validator checks both a freshly generated simulation report and
the archived reference capture against that manifest.

The production replay fixture remains deliberately small. Its portable 8 ms
P95 bound detects severe kernel regressions across CI runners; it is not evidence
for the later 120-enemy/500-projectile density target. The M1 Pro reference
capture receives a tighter 1 ms P95 bound. M5-06 retains ownership of the
representative-density workload, Windows reference-profile capture, and
30-minute soak gate.

The existing production GDScript suites remain the correctness and replay-audit
entrypoints. Architecture tests additionally reject SceneTree, scene-resource,
and rendered-frame dependencies under `game/simulation/`. The unified runner
generates the current replay report, validates its schema, evaluates the kernel
gate, then retains the existing numerical and smoke regressions.

## Ecosystem review

| Candidate | Decision |
| --- | --- |
| Godot 4.7.2 headless runtime and existing Ashvault GDScript/Python harness | Adopt. It already runs the authoritative kernel directly on macOS and Windows and exposes exact process output. |
| [GUT 9.7.1](https://github.com/bitwes/Gut) | Defer. It is mature, MIT-licensed, and has a Godot 4.7 branch, but migrating the completed kernel suites would change execution semantics without adding gate evidence. Reconsider for future scene-heavy tests, mocks, or JUnit export. |
| [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) | Defer for the same boundary reason. Its editor integration, scene runner, mocking, and retry features are valuable downstream but unnecessary for a deterministic scene-independent gate. |
| Enforce reference timings on GitHub-hosted runners | Reject. Runner hardware and contention are not the named Apple M1 Pro or Windows reference profiles. CI enforces only the generous portable smoke bound. |

## Validation

- Run the complete unified suite with Godot 4.7.2.
- Run identical replay instances plus independently changed command and seed
  inputs; compare the frozen state/report hashes.
- Generate and schema-validate the current production simulation report.
- Validate the current report and archived Apple M1 Pro capture against the
  gate manifest and their respective P95 thresholds.
- Confirm production simulation imports no SceneTree, scene, or rendered-frame
  lifecycle.
- Run the macOS/Windows CI matrix through the linked PR.

## Current state

Implementation and local validation are complete for M1-08. The manifest
freezes the existing replay state/report hashes, an 8,000 μs portable P95 smoke
bound, a 1,000 μs Apple M1 Pro P95 bound, maximum event depth one, and peak
entity count two. Ten independent M1 Pro captures observed P95 values from 214
to 567 μs; the conservative 567 μs capture is archived.

The unified suite passes with 47 Python tests, eleven production GDScript
contract suites, the current-report and reference-capture kernel gate,
simulation/performance schema validation, prototype regressions, and the
main-scene smoke test. The replay audit retains state hash
`650d204d9ae61efcab7c731456e66db45968ba61f2af16e0b0d3494a24aea6f8`
and report hash
`d8e0ef3d3b1791c45f3d9366f67ac40c49864c76d24008f683b35207319dea64`.
The editor scan from M1-07 remains complete at 61 unique GDScript UIDs because
this gate adds no GDScript files. The linked PR and #14 remain the authoritative
delivery state; macOS and Windows CI are pending that PR.
