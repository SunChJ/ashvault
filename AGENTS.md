# Project Agent Instructions

## Optimize the development loop

Prioritize reproducibility, iteration speed, observability, data-driven
content, and tooling ROI. Optimize this loop:

```text
Change -> Run -> Reproduce -> Observe -> Diagnose -> Fix
```

The highest-priority engineering rules are:

- Simple before generic.
- Explicit before abstract.
- Observed complexity before designed complexity.
- Data-driven where content scales.
- Observable where debugging hurts.
- Automate only proven high-ROI friction.
- Optimize iteration speed, not tooling quantity.
- Build the game first; build tools only when they materially accelerate it.

Every task should identify the shortest deterministic reproduction path and
inspectable evidence. Prefer focused headless tests, seeded fixtures, clear exit
codes, and structured output. Do not require Editor interaction when a reliable
command-line validation path is practical.

Before adding a generator, editor plugin, generic framework, or broad
abstraction, name the repeated observed friction and include implementation,
maintenance, compatibility, learning, future-change, and cognitive costs. If
lifetime time saved is not plausibly at least 10x total development cost,
continue manually and gather evidence.

Follow [`docs/GODOT_ENGINEERING_PRINCIPLES.md`](docs/GODOT_ENGINEERING_PRINCIPLES.md)
for the complete project policy.

## Prefer Godot-native primitives

- Presentation and composition default to `Scene`, `Node`, `Resource`,
  `Signal`, `PackedScene`, `Autoload`, and explicit `res://` references.
- Preserve the scene-independent deterministic simulation boundary; its
  `RefCounted` contracts are intentional Godot-native design.
- Use `preload()` or a direct reference for small fixed dependencies, typed
  Resources for gameplay definitions, and stable IDs plus feature-specific
  registries for large content families.
- Treat `%UniqueName` nodes as stable scene APIs. Use them only for important
  code-referenced nodes, and do not rename them casually.
- Prefer direct typed parent-to-child calls, child-to-parent signals, focused
  cross-system events, and explicit persistent state. Do not turn an EventBus
  into a universal service locator or state store.
- Prefer feature-tailored schemas over universal entity, metadata, properties,
  components, or attributes containers.

## Prefer proven ecosystem components

- Before implementing a non-trivial subsystem, inspect Godot's built-in APIs,
  the official Asset Library, and actively maintained community plugins or
  assets that may already satisfy the requirement.
- Prefer a suitable existing component over custom implementation when its
  behavior, license, maintenance status, platform support, deterministic
  boundaries, runtime cost, and integration surface fit the project.
- Record why a candidate was adopted, wrapped, or rejected when the decision
  affects architecture or long-term maintenance.
- Do not add a dependency only for superficial reuse; keep small kernel
  contracts local when an external component would broaden the trusted surface
  or weaken determinism.
