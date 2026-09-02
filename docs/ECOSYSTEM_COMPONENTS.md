# Ecosystem Component Roadmap

Third-party components are installed manually and adopted only after license,
maintenance, platform, deterministic-boundary, runtime-cost, and integration
review. Editor and presentation plugins may accelerate production, but they do
not own authoritative simulation state.

| Component | Intended milestone | Project role | Status / boundary |
| --- | --- | --- | --- |
| Aseprite Wizard 9.8.0 | M2 | `.aseprite` import to `SpriteFrames` / `AnimationPlayer` | Installed manually; editor-only asset pipeline. |
| Phantom Camera 0.11.0.3 | M2-08 | Camera2D composition and feedback | Installed; presentation only. Simulation snapshots remain authoritative. |
| [Godot State Charts 0.22.5](https://github.com/derkork/godot-statecharts) | M2 | Player, ability, and combat presentation orchestration | Installed; may mirror simulation snapshots but not own deterministic rules. |
| LimboAI | M2-05 | Enemy behavior trees and hierarchical state machines | Preferred candidate; AI decisions must emit simulation commands. |
| [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) | Cross-cutting | Scene, integration, mocks, and test reporting | Deferred; do not install. Existing deterministic contract gates remain authoritative. |
| Limbo Console | M2/M3 | In-game developer commands and diagnostics | Preferred candidate; development-only adapters call validated APIs. |
| Controller Icons | M2-07 | Automatic keyboard/controller prompts | Preferred candidate; presentation only. |
| [Gloot 3.0.2](https://github.com/peter-kish/gloot) | M3 | Inventory, item, and equipment workflow | Installed behind project-owned item-instance and save adapters. |
| Better Terrain | M4 | TileMap terrain authoring | Evaluate when modular dungeon authoring begins. |
| Dialogue Manager | M4 | NPC dialogue and branching text | Evaluate when narrative content enters production. |
| Sentry Godot | Post-alpha | Crash, error, and release monitoring | Defer until consent, privacy, release-symbol, and environment policies exist. |
| Juicee / Saltmire Juice | Prototype / M2-08 | Shake, hit-stop, flash, and combat feel | Optional presentation acceleration; never a simulation dependency. |

Each implementation issue must still verify the selected component's current
release, license, Godot compatibility, and maintenance state before installation.
Install tagged releases independently, retain their upstream licenses, and keep
vendor upgrades isolated from project-authored behavior changes.
