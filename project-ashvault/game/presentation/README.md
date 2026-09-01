# Presentation

Owns scenes, rendering, UI, VFX, audio, camera behavior, and input adaptation.
It may consume simulation events and snapshots and emit player commands.

Presentation must not own authoritative game state, calculate final damage, or
reference `res://prototype/`.

## Input adaptation

`input/KeyboardMouseCommandAdapter` reads named InputMap actions and translates
sampled movement and world-space mouse aim into immutable `PlayerCommand`
values. It suppresses unchanged intent and owns only the actor's monotonic
client sequence. Tests and future binding UI use the sampled-input method, so
physical key remapping never enters simulation rules.
