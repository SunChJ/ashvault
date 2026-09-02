# 005 — Godot Engineering Productivity: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-09-02 |
| **Primary refs** | #76, `0a076dd` |
| **Related** | [`DEVELOPMENT_TASKBOOK.md`](../../docs/DEVELOPMENT_TASKBOOK.md), [`AGENTS.md`](../../AGENTS.md) |

## Background

GodotFest 2025 productivity guidance highlighted that project architecture and
tooling should shorten a reproducible development loop rather than optimize for
abstraction or tooling volume. Ashvault already has fixed-engine CI, headless
kernel tests, deterministic seeds, explicit subsystem contracts, and deferred
tool adoption, but these choices are not yet expressed as one contributor and
agent-facing decision policy.

## Goals

- Make reproducibility, time-to-test, observability, data-driven content, and
  tooling ROI explicit engineering priorities.
- Give agents a short set of high-priority rules that prevent speculative
  abstraction, refactoring, and automation.
- Define Godot-native defaults without weakening the scene-independent
  deterministic simulation boundary.
- Make future task validation describe the shortest reproduction path and
  inspectable evidence.
- Preserve the existing rule to evaluate suitable built-in and community
  components before implementing a non-trivial subsystem.

### Non-goals

- Do not build bootstrap, run, export, editor, or debugger tooling solely to
  satisfy the policy.
- Do not redesign the current kernel, content catalog, plugin boundaries, or
  milestone structure.
- Do not require every content family to use one storage format or universal
  schema.
- Do not adopt Sentry before the first gameplay loop and SaveGameV1 exist.

## Design / Approach

1. Add a concise maintained engineering-principles document under `docs/`.
2. Add the eight core decision rules and their operational consequences to the
   repository-level agent instructions.
3. Link the policy from the taskbook and project README.
4. Tighten the issue-template validation guidance so tasks name a fast,
   deterministic reproduction path and observable output.
5. Record implemented files and actual validation in `001-action.md`.

The project decision order will be:

1. use a fitting Godot-native capability;
2. for non-trivial solved problems, evaluate a proven ecosystem component;
3. prefer small explicit local code when dependency cost exceeds its value;
4. automate only measured, repeated friction with strong lifetime ROI;
5. introduce a general abstraction or framework only after observed complexity
   requires it.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Copy the full source notes into `AGENTS.md` | Rejected: long instructions dilute the rules that must affect every change. |
| Immediately add bootstrap/run/build/export wrappers | Rejected: the policy explicitly forbids automating hypothetical friction. |
| Prefer custom code before ecosystem review | Rejected for non-trivial solved subsystems; it conflicts with the adopted component policy. |
| Require Resources for all gameplay content | Rejected: large content needs feature-tailored, diffable schemas. |
| Use Nodes for authoritative simulation because they are Godot-native | Rejected: the existing deterministic headless boundary has stronger project-specific evidence. |

## Amendments

None.
