# 003.012 — Player Input Adapter and Fixed-Tick Movement

## Context

M2-01 turns the M1 movement-intent command into authoritative position changes
without allowing input devices, rendered frames, Nodes, or a physics server to
own simulation state. The existing M1 replay and hashes must remain valid when
movement is not configured.

## Planned change

`KeyboardMouseCommandAdapter` lives in presentation. It polls named InputMap
actions, converts viewport mouse position to world aim, and emits immutable
`PlayerCommand` values with strictly increasing client sequences. A pure sampled
input method exposes the same translation for headless tests and future binding
UI. The adapter never receives or mutates `EntityWorld`; physical keys remain
Project Settings data rather than simulation identifiers.

`MovementEnvironment` is an immutable simulation value configured with arena
bounds, static axis-aligned obstacles, actor radius, and movement speed. It
normalizes authored obstacle order and resolves each 60 Hz movement step using
continuous axis sweeps in fixed X-then-Y order. Obstacles are expanded by actor
radius, which gives swept-circle bounds behavior, prevents tunneling, and
produces deterministic wall sliding without a scene or physics server.

`EntityWorld` accepts an optional movement environment. Accepted command batches
first update intent, then integrate every living player-controlled entity once
before damage commitment. Copy-on-write staging keeps command, movement, and
damage changes atomic. Invalid placement or movement configuration rejects
before publication.

Compatibility is additive. Worlds without a movement environment retain the M1
state-hash schema and golden values. Movement-enabled worlds use a new canonical
hash schema that includes collision configuration. The global simulation
version remains unchanged because existing configured inputs and behavior are
unchanged; the new environment cannot be consumed by older replay fixtures.

## Ecosystem review

| Candidate | Decision |
| --- | --- |
| Godot `InputMap`, `Input.get_vector`, viewport mouse position, `Vector2`, and `Rect2` | Adopt. Input actions preserve remapping ownership in presentation; value types support the required deterministic static solver. |
| Godot [`CharacterBody2D`](https://docs.godotengine.org/en/4.7/tutorials/physics/using_character_body_2d.html) | Reject as authoritative movement. Its intended `_physics_process()`/Node/physics-server lifecycle conflicts with headless replay ownership. It may later mirror snapshots for presentation only. |
| [`appsinacup/godot-rapier-physics`](https://github.com/appsinacup/godot-rapier-physics) | Defer. It is active and offers Godot 4.7 builds plus enhanced-determinism features, but a native physics replacement is disproportionate for bounded player motion against static room rectangles. Re-evaluate if dynamic-body interactions outgrow the solver boundary. |
| Encode WASD keycodes in simulation | Reject. Remapping must alter InputMap only and cannot change deterministic rules or command DTOs. |

## Validation

- Verify action samples emit only normalized move/aim commands with monotonic
  client sequences and suppress unchanged samples.
- Verify neutral movement, diagonal speed, arena bounds, obstacle tunneling,
  deterministic slide order, invalid starts, and obstacle-order independence.
- Replay identical movement commands with and without presentation snapshots;
  hashes and positions must match.
- Verify worlds without movement configuration retain the M1 replay golden.
- Run the unified local suite and macOS/Windows CI matrix.

## Current state

Implemented locally for #15. The command adapter emits only immutable move/aim
DTOs from named actions or supplied samples. Optional movement configuration is
integrated transactionally in `EntityWorld`, and movement-enabled hashes include
the normalized environment while the M1 replay golden remains unchanged.

Focused validation covers command suppression and sequencing, normalization,
invalid samples, arena radius bounds, obstacle tunneling, wall sliding,
obstacle-order independence, invalid placement, and rendered/headless hash
equivalence. The movement replay freezes state hash
`ccbb94ed2230576cb4a4dcf5b6a3ab7f0ad9006572435b51c44601c5fe52fd7d`.

The unified local suite passes with 47 Python tests, twelve GDScript contract
suites, both report-schema validators, the M1 kernel gate, numerical
regressions, and the main-scene smoke test. The legacy M1 replay retains state
hash `650d204d9ae61efcab7c731456e66db45968ba61f2af16e0b0d3494a24aea6f8`.
The editor scan reports 64 unique GDScript UIDs. The linked PR and #15 remain
the authoritative delivery state; macOS and Windows CI are pending that PR.
