# 003.018 — Snapshot-driven Combat HUD

## Context

M2-07 requires readable health, mana, six bindings, casting, cooldowns, and
statuses without introducing UI-owned combat state.

## Planned change

Use native Control/Container scenes and a small snapshot-to-view adapter.
Configure immutable loadout metadata once; present entity snapshots and copied
status records for the same tick. UI availability is feedback only; EntityWorld
continues to validate commands. Read binding labels from InputMap, including
remapped and unbound actions. Keep simulation tick time authoritative and avoid
wall-clock cooldown timers.

Controller Icons is unnecessary for the six keyboard/mouse text labels in this
milestone. Native Labels, ProgressBars, and Containers cover the required UI;
no additional dependency or generic UI framework is warranted.

## Validation

Headless UI fixtures check normal, unavailable, casting, cooldown, and status
states, snapshot isolation, binding remaps, and 1920x1080 layout bounds. A
rendered fixture captures those five states for visual inspection. Run the
unified local suite and desktop CI before merging the linked PR.

## Current state

Implemented for #21 using native Control scenes and a RefCounted view adapter.
The HUD has fixed-width ability cards, live InputMap labels, health/mana bars,
cast progress, cooldown feedback, and actor-filtered status durations/stacks.
It holds no combat-world reference and uses no wall-clock timers.

Verified the five headless state fixtures and rendered all five at 1920x1080
with Godot 4.7.2 OpenGL Compatibility. Inspected PNG captures for text clipping,
contrast, progress, and status visibility. Fixed state-dependent card resizing
observed in the first render and verified stable 200-unit slot widths. Added
exact cooldown-expiry and remapping/unbound tests; positive cooldowns cannot
round down to a misleading zero-second label.

The unified local suite passed, including 49 Python tests, project import,
production/prototype headless suites, simulation CLI/schema checks, and the M1
kernel gate. HUD validation is registered in the existing desktop CI runner.
Capture commands and the snapshot integration contract are documented in the
presentation README.

Gameplay scene assembly, cast input dispatch, VFX, audio, and camera feedback
remain downstream integration work. No new plugin or generic UI framework was
introduced.
