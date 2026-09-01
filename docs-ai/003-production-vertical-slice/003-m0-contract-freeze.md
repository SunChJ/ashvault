# 003.003 — M0 Contract Freeze

## Context

M0-01 through M0-05 established the production roots, identity and version
contracts, transactional catalog publication, cross-platform headless CI, and
the performance-reporting baseline. M0-06 reviews those outcomes before M1
introduces deterministic simulation state.

The Kernel specification currently mixes implemented M0 contracts with accepted
M1–M5 design targets. Its `Accepted for M0 implementation` status no longer
describes the repository state after the M0 implementation tasks completed.

## Change

Freeze the implemented M0 surface as Kernel specification version 1.0 and make
the implementation boundary explicit:

- Sections 2–3 and the M0 performance report contract in section 12 are
  implemented and compatibility-controlled.
- Sections 4–11, the production simulator portions of section 12, and section
  13 remain accepted downstream requirements rather than claims of current
  implementation.
- Root ownership is enforced as directional dependency policy, not only as a
  prohibition on prototype imports.
- A dedicated headless freeze test locks stable ID syntax, version constants,
  public catalog types, and performance report schema version.

Breaking changes to a frozen contract require the corresponding content,
simulation, save, or report schema version to change with its tests and
migration/compatibility policy. Compatible additions may retain the version.

## Validation

- `python3 tools/ci/run_tests.py` passed locally with Godot 4.7.2: 30 Python
  tests, four production GDScript contract suites, performance report
  generation/schema validation, two prototype regressions, and the main-scene
  smoke test.
- GitHub macOS 14 and Windows 2022 jobs passed on PR #54.
- M0-01 through M0-05 were closed before delivery.
- PR #54 used `Closes #6`; its merge automatically closed M0-06.

## Accepted deviations

| Deviation | Disposition |
| --- | --- |
| The default project scene remains the numerical prototype. | Accepted through M0 because no production composition scene exists yet; bidirectional import tests keep it outside the production API. |
| The M0 density baseline advances a synthetic fixed-tick workload. | Accepted as measurement-pipeline evidence only; M1 replaces it with the production headless simulator before timing thresholds become a gate. |
| M0-01 through M0-03 were initially delivered directly. | Corrected by substantive PRs #49–#51 and governed by the PR-linked delivery amendment. |

No unresolved ownership or compatibility deviation is accepted for the frozen
M0 surface.

## Current state

PR #54 completed the M0 contract freeze in merge commit `9953256`. All six M0
tasks closed and the M0 milestone exited with no unresolved ownership or
compatibility deviation. M1 production-kernel work is unblocked.

M0-06 and its milestone were temporarily reopened only to deliver this
post-merge state correction through the required PR workflow; no frozen
contract changed during finalization.
