# 003.019 — Combat Presentation and Readability

## Context

M2-08 needs a runnable composition to demonstrate the six abilities, bounded
combat feedback, audio, camera intensity, and readable 120-enemy encounters.
The current headless kernel and HUD have no playable scene integration.

## Planned change

- Add a direct-run arena scene with fixed-tick combat, keyboard/mouse skill
  commands, the existing HUD, and a snapshot-driven Node2D presentation.
- Give each skill a distinct geometric shape and authored synthesized sound.
  Distinguish ordinary, critical, protected, player-hit, Shock, and death cues.
- Cap transient visual effects and simultaneous audio voices. Preserve player
  silhouette and priority telegraphs when crowd feedback reaches the cap.
- Use Camera2D with a bounded presentation-only offset and an intensity control.
  Phantom Camera is installed, but a fixed arena camera needs no camera
  transitions/host lifecycle. Native Camera2D is the smaller fitting primitive.
- Demonstrate an elite telegraph as an explicit presentation fixture, without
  inventing M4 elite AI or combat authority in the renderer.
- Extend the copied combat report with delivery positions for projectile/totem
  rendering; keep this outside the authoritative state hash.

## Validation

Run seeded input and presentation-disabled hash comparisons, cue/budget and
camera-zero tests, and the unified headless suite. Capture representative and
120-enemy footage with Godot Movie Maker and inspect 1080p frames. Audio assets
are original PCM samples authored offline, with measured peaks and durations.
The final M5 frame-time/soak gate remains separate from M2 readability.

## Current state

Implemented. The default scene now composes the deterministic combat kernel,
input adapter, reusable HUD, native Camera2D, and snapshot-driven feedback.
The old numerical prototype remains runnable by explicit scene path.

- Six skill signatures and thirteen original PCM cues distinguish casts, hit
  classes, criticals, Shock, deaths, and the presentation-only elite warning.
- Feedback caps at 96 effects and eight voices, with per-target hit coalescing,
  sound retrigger limits, priority effect retention, and separate player and
  telegraph drawing passes. Corpse status markers are suppressed.
- Camera motion scales from zero to a bounded maximum; aiming uses unshaken
  coordinates. Audio can be muted immediately. Live play does not accumulate
  benchmark timing samples.
- Input dispatch handles cast completion, cancellation, Dash interruption, and
  held movement resumption using immutable actor snapshots.

## Verified outcome

`python3 tools/ci/run_tests.py` passed with Godot 4.7.2: 49 Python tests,
production/prototype fixtures, the headless report and kernel gate, performance
baseline, and the default scene smoke test. The feedback fixture covers every
cue, bounded effects/voices, zero camera motion, and cast/movement lifecycle.
Headless teardown checks mute immediately, then waits for weak playback
references to retire (with a two-second failure deadline). A fixed 50 ms wait
proved intermittently shorter than asynchronous mixer cleanup during M3-01
validation; frame boundaries alone did not guarantee release.

Both 480-tick presentation-enabled and disabled fixtures match:

| Enemies | State hash |
| --- | --- |
| 12 | `c698e353b88a959a52aa8e7cf1bb16f751bb04b9b7579f36f273c5f075944396` |
| 120 | `23fea8f5e12e409f49d2da5b6d5db687eb04b31c6ae652c7d6213c5a457ff8c6` |

Movie Maker captures are reproducible using the
[presentation guide](../../project-ashvault/game/presentation/README.md).
Local evidence lives in `.artifacts/combat-feedback/`: `representative.mp4`,
`density.mp4`, and corresponding tick-170 PNGs. Both H.264/AAC captures use 1920x1080 at 60 FPS for 8.067 seconds.
The original recorded audio peaks at -17.3 dBFS (12 enemies) and -19.8 dBFS
(120 enemies), confirming non-silent audio without clipping. Movie Maker
simulation P95 on the Apple M1 Pro was 1,569 and 9,182 microseconds respectively;
the latter exceeds the eventual 8 ms target and requires M5 optimization.
The player silhouette, elite warning, HUD, and totem remain distinguishable in
both scenes; crowded melee enemies can overlap under the current movement
model. This gate covers feedback readability, not enemy separation or final art.

## Scope and remaining gates

Elite telegraphs are a presentation fixture; M4 owns elite AI and attacks.
The M5 120-enemy/500-projectile frame-time and extended-soak gates are still
outstanding. Recorded simulation timings are diagnostic samples, not a claim
that the final performance gate has passed.
