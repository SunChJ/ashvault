# Godot Engineering Principles

## Purpose

Ashvault optimizes engineering decisions for, in order:

1. reproducibility;
2. iteration speed;
3. observability;
4. data-driven content;
5. tooling return on investment.

The target development loop is:

```text
Change -> Run -> Reproduce -> Observe -> Diagnose -> Fix
```

Architecture and tooling are valuable only when they make this loop shorter,
more reliable, or easier to inspect.

## Core rules

- **Simple before generic.**
- **Explicit before abstract.**
- **Observed complexity before designed complexity.**
- **Data-driven where content scales.**
- **Observable where debugging hurts.**
- **Automate only proven high-ROI friction.**
- **Optimize iteration speed, not tooling quantity.**
- **Build the game first; build tools when they materially accelerate it.**

## Decision order

For each engineering problem:

1. Use a fitting Godot-native capability if it meets the contract.
2. For a non-trivial solved problem, evaluate a maintained official or
   community component against license, compatibility, runtime cost, and the
   deterministic boundary.
3. Prefer small, explicit local code when a dependency would cost more than it
   saves.
4. Confirm that repeated friction exists before building project tooling.
5. Automate the smallest useful part only when lifetime benefit plausibly
   exceeds total development and maintenance cost by at least 10x.
6. Introduce a general abstraction or framework only after measured complexity
   requires it.

The ecosystem decision record lives in
[`ECOSYSTEM_COMPONENTS.md`](ECOSYSTEM_COMPONENTS.md).

## Reproducible environment

- Godot is pinned to 4.7.2. CI downloads that exact release, and the local test
  runner rejects another version.
- Repository commands and CI must not depend on a developer machine happening
  to contain the correct engine or hidden configuration.
- New prerequisites must be explicit, versioned, and reproducible from a fresh
  clone with minimal manual setup.
- Engine binaries need not be committed. Automatic acquisition is preferred
  when repeated local setup friction justifies maintaining it.
- `tools/ci/run_tests.py` remains the unified validation entrypoint. Add
  bootstrap, run, build, or export wrappers when their workflows exist and the
  repeated friction is observed; do not create placeholder automation.

## Time-to-test

- Every task identifies its shortest deterministic reproduction path: a focused
  headless test, direct scene, preset, fixture, or seeded command.
- Focused validation should run before the complete regression suite.
- High-frequency gameplay checks should not require navigating menus, saves,
  characters, maps, or encounters unrelated to the behavior under test.
- Add Fast Start or a deterministic Test Arena when the assembled gameplay loop
  makes those steps a repeated blocker. Presets may select map, character,
  level, difficulty, equipment, skills, enemies, and RNG seed.
- Prefer command-line execution, clear exit codes, and structured output so the
  same path works for humans, agents, and CI.

## Godot-native design

- Presentation and composition default to `Scene`, `Node`, `Resource`,
  `Signal`, `PackedScene`, `Autoload`, and explicit `res://` references.
- The authoritative simulation remains scene-independent because deterministic
  headless execution is a validated project requirement. `RefCounted` values
  and Resources are Godot-native primitives too; do not convert kernel state
  into Nodes for stylistic consistency.
- Do not introduce DI containers, service locators, generic repositories,
  universal asset managers, or generic entity frameworks without observed
  project complexity that simpler primitives cannot handle.

### Scene APIs

Use `%UniqueName` for stable, code-referenced nodes such as `%Hitbox`,
`%HealthBar`, or `%WeaponSocket`. Treat these names as public scene contracts:
rename them deliberately and update consumers and tests together.

Do not assign unique names to ordinary layout or private implementation nodes.
Parent-to-child interaction normally uses a direct typed call; child-to-parent
notification normally uses a signal.

## Explicit dependencies

Use the smallest dependency mechanism that fits the scale:

| Scope | Default |
| --- | --- |
| Small fixed runtime asset set | `preload()` or direct scene/resource reference |
| Gameplay definitions | Typed Godot `Resource` |
| Large content family | Stable ID plus feature-specific registry/data layer |

A direct path is acceptable when it is fixed and local. Hundreds of items,
skills, monsters, or encounters must not spread hard-coded paths throughout
gameplay code.

## Calls, events, and state

Use different mechanisms for different semantics:

| Relationship | Default |
| --- | --- |
| Parent to child | Direct typed method call |
| Child to parent | Signal |
| Cross-system occurrence | Typed event or focused event bus |
| Persistent global fact | Explicit game state/store |

An event reports that something occurred; state answers what is true now. Do
not use an event bus as a state store or route all local calls through it. Avoid
stringly typed paths such as `Data.apply("some.string.path", value)` when a
typed API, `StringName`, stable ID, or explicit structure is available.

## Data-driven gameplay

- Separate scalable content from runtime logic: items, affixes, skills,
  monsters, loot tables, shops, encounters, missions, difficulty curves, and
  narrative triggers.
- Choose `Resource`, YAML, JSON, or CSV per feature. Data must be readable by
  humans, Git diffs, scripts, and agents; Inspector-only authoring is not a
  universal requirement.
- Prefer feature-tailored schemas such as `skills`, `monsters`, or
  `loot_tables` over universal metadata/property/component containers.
- Declarative interpreters are appropriate for repeated content families such
  as encounters, spawns, loot, missions, and narrative triggers. Keep their
  formats direct and debuggable; do not create a language merely to claim that
  content is data-driven.

## Observability

- First preserve provenance and expose structured state at the domain boundary.
- Add a domain debugger only after ordinary debugging repeatedly fails to
  answer a concrete question.
- High-value candidates include damage, combat events, loot, spawn decisions,
  statuses, saves, and audio. A debugger should turn ambiguous behavior into an
  inspectable stage-by-stage explanation.
- Development consoles and overlays call validated project APIs. They do not
  become alternate gameplay authority.

## Save and production reporting

SaveGameV1 is critical infrastructure. It requires atomic replacement, a
temporary file, last-known-good backup, schema versioning, migration,
validation, corruption recovery, and structured lifecycle breadcrumbs.

Minimal Sentry integration remains deferred until the first real gameplay loop
and SaveGameV1 exist. Gameplay code must report through a project-owned
`ErrorReporter`; it must not depend directly on a vendor SDK.

## Tooling ROI

Before creating a tool, record:

- the observed repeated friction;
- frequency, manual cost, and error rate;
- expected remaining lifetime;
- who benefits: humans, agents, CI, or content authors;
- implementation, debugging, compatibility, learning, maintenance, future
  change, and cognitive costs;
- the smallest automation that removes the bottleneck.

If estimated lifetime time saved is not plausibly at least 10x the total tool
development cost, continue manually and gather evidence. One instance of
duplication is not evidence for a framework, generator, editor plugin, or broad
refactor.
