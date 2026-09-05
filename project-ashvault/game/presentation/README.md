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

The HUD is a reusable presentation scene. Playable scene assembly and ability
input dispatch remain integration work; these labels do not emit cast commands.
