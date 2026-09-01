# Presentation

Owns scenes, rendering, UI, VFX, audio, camera behavior, and input adaptation.
It may consume simulation events and snapshots and emit player commands.

Presentation must not own authoritative game state, calculate final damage, or
reference `res://prototype/`.
