# 002 — Numerical Combat Sketch: Action

| | |
| --- | --- |
| **Status** | Implemented |
| **Date** | 2026-09-01 |
| **Plan** | [`000-plan.md`](000-plan.md) |
| **Runtime** | Godot 4.7.2 |

## Outcome

Implemented a playable procedural arena as the project entry point. The sketch
combines automatic Storm Bolt and Arc Nova casting, XP pickups, keyboard-driven
level-up choices, elites, a two-minute boss cadence, charge novas, and temporary
Overdrive windows.

The reusable numerical boundary is limited to two stateless modules:

- `combat_math.gd` resolves damage layers, resistance and penetration, critical
  boundaries, and diminishing-return haste.
- `progression_math.gd` owns the piecewise XP curve and skill-rank damage and
  behavior milestones.

The arena itself deliberately remains one compact simulation owner. Enemies,
projectiles, drops, and effects use state arrays and procedural drawing rather
than production-facing object hierarchies.

## Reference decisions

The damage pipeline preserves the useful stage separation documented by the
[Hero Siege Helper damage calculator](https://hero-siege-helper.vercel.app/damage).
Constants, item identities, and the helper's interpolated
[Hero Level XP values](https://hero-siege-helper.vercel.app/exp) were not copied.
Ashvault's three-minute sample requires a compressed curve and independently
tuned values.

Skill ranks change behavior at explicit milestones: Storm Bolt gains a second
projectile at rank 3 and chaining at rank 5. This creates visible level-up value
without requiring rarity or item systems.

## Balance sample

The deterministic three-minute headless run produced:

| Signal | Observed |
| --- | ---: |
| First upgrade | 16.87 s |
| First Overdrive | 15.65 s |
| First boss | 120.02 s |
| Final level | 14 |
| Kills | 1,590 |
| Peak live enemies | 81 |
| Storm Bolt rank | 5 |

These values satisfy the automated acceptance bands and density hypothesis. The
test follows a seeded movement route and uses effectively infinite player health
so it measures build output rather than idle-input survival.

## Deviations from plan

- The initial small-viewport sample upgraded at 3.4 seconds and understated
  density. The acceptance test now fixes the production viewport at 1152×648,
  follows an active movement route, and validates the 30–120 density band.
- The charge nova and Overdrive are separate systems: every 12 kills creates a
  radial release, while a 22-kill combo grants five seconds of haste and damage.
- Final audiovisual impact remains outside scope; the rendered scene uses only
  circles, diamonds, grids, health bars, and rings.

## Verification

Executed successfully:

```text
Godot --headless --path project-ashvault --script res://tests/test_numerical_core.gd
Godot --headless --path project-ashvault --script res://tests/test_numerical_sketch.gd
Godot --headless --path project-ashvault --quit-after 30
Godot --path project-ashvault --write-movie /tmp/ashvault-capture/frame.png --fixed-fps 60 --quit-after 180 --audio-driver Dummy
```

The movie capture was inspected for arena, HUD, entity, projectile, and pickup
rendering. No external visual assets were added.
