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


## Combat HUD

Instantiate `hud/combat_hud.tscn` on a 1920x1080 presentation canvas, configure
it with the player's immutable six-slot AbilityLoadout, then call
`present(snapshot, actor_id, status_records)` after each accepted simulation
tick. Pass `StormweaverCombat.presentation_snapshot()` and the same tick's
`report()["statuses"]`; the HUD does not poll or retain a combat-world owner.
A missing actor clears and hides the HUD.

The model reads health, mana, cast/recovery phase, cooldowns, and copied status
records. Availability is advisory feedback; simulation still validates every
command. Time displays use snapshot ticks, including an upward-rounded positive
cooldown label until its exact expiry. Six stable-width cards show InputMap
bindings and explicit ready, busy, casting, low-mana, unbound, or defeated text.
The keyboard/mouse actions are `ability_primary`, `ability_secondary`,
`ability_nova`, `ability_ward`, `ability_totem`, and `ability_dash`.

Run state and layout fixtures headlessly:

```sh
"$ASHVAULT_GODOT" --headless --path project-ashvault \
  --script res://tests/production/test_combat_hud.gd
```

Capture normal, unavailable, casting, cooldown, and status states with a renderer:

```sh
"$ASHVAULT_GODOT" --path project-ashvault --rendering-method gl_compatibility \
  --script res://tests/production/test_combat_hud.gd -- \
  --capture-dir "$PWD/.artifacts/combat-hud"
```

The HUD is a reusable presentation scene. The combat arena composes it with
the input adapter; HUD labels themselves do not emit cast commands.

## Combat feedback

`combat/CombatFeedback` receives snapshots and copied reports. It draws six
ability signatures, live projectile/totem positions, persistent status markers,
hit/protected/critical/player-hurt cues, and deaths. At most 96 transient effects
and eight audio voices are active. Repeated same-target hit feedback is merged
within a tick; priority effects can replace crowd effects. Player silhouette and
elite warning geometry have independent drawing passes.

Camera motion is a bounded presentation-only offset, clamped to intensity 0–1.
Zero disables the offset immediately. Camera shake is excluded from mouse-to-
world aim mapping. Audio can be muted immediately without touching simulation.
An elite telegraph is an explicit demonstration event; the presentation does
not implement elite attacks or resolve damage.

The default scene is now `game/infrastructure/arena/combat_arena.tscn`, with a
1920x1080 viewport and a 1280x720 initial window. Its controller owns the fixed
simulation tick and input dispatch. WASD moves; the six HUD bindings cast;
movement cancels interruptible casts, and Dash replaces them. F5 restarts.
The numerical prototype remains directly runnable at
`res://prototype/numerical_sketch.tscn`.

```sh
"$ASHVAULT_GODOT" --path project-ashvault
"$ASHVAULT_GODOT" --headless --path project-ashvault \
  --script res://tests/production/test_combat_feedback.gd
```

For a reproducible movie, create the output directory first, then run:

```sh
"$ASHVAULT_GODOT" --path project-ashvault --rendering-method gl_compatibility \
  --write-movie "$PWD/.artifacts/combat-feedback/density.avi" --fixed-fps 60 -- \
  --showcase --enemies 120 --ticks 480 \
  --capture-tick 170 --capture-path "$PWD/.artifacts/combat-feedback/density.png"
```

Use `--enemies 12` for the representative encounter. Add
`--presentation-disabled` to compare the final authoritative hash without the
HUD, camera effects, drawing, or sound. `simulation_p95_us` is a separately
reported observation, not part of the replay hash or the M5 performance gate.

## Authored room modules

`dungeon/AuthoredRoom` composes a typed room descriptor with presentation-only
floor, connector, and socket visuals. Scene transforms never author simulation
geometry. See the [room contract](../simulation/dungeon/README.md) and the five
native scene fixtures under `tests/fixtures/rooms/`.
