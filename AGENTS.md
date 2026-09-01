# Project Agent Instructions

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
