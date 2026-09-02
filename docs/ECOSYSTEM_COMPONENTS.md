# Ecosystem Component Roadmap

Third-party components are installed manually and adopted only after license,
maintenance, platform, deterministic-boundary, runtime-cost, and integration
review. Editor and presentation plugins may accelerate production, but they do
not own authoritative simulation state.

| Component | Intended milestone | Project role | Status / boundary |
| --- | --- | --- | --- |
| Aseprite Wizard | M2 | `.aseprite` import to `SpriteFrames` / `AnimationPlayer` | Installed manually; editor-only asset pipeline. |
| Phantom Camera 0.11.0.3 | M2-08 | Camera2D composition and feedback | Installed; presentation only. Simulation snapshots remain authoritative. |
| Godot State Charts | M2 | Player, ability, and combat presentation orchestration | Preferred candidate; may mirror simulation snapshots but not own deterministic rules. |
| LimboAI | M2-05 | Enemy behavior trees and hierarchical state machines | Preferred candidate; AI decisions must emit simulation commands. |
| GdUnit4 or GUT | Cross-cutting | Scene, integration, mocks, and test reporting | Evaluate one framework when it adds coverage beyond the existing headless harness. |
| Limbo Console | M2/M3 | In-game developer commands and diagnostics | Preferred candidate; development-only adapters call validated APIs. |
| Controller Icons | M2-07 | Automatic keyboard/controller prompts | Preferred candidate; presentation only. |
| Gloot | M3 | Inventory, item, and equipment workflow | Preferred candidate; evaluate against Ashvault item-instance and save contracts before adoption. |
| Better Terrain | M4 | TileMap terrain authoring | Evaluate when modular dungeon authoring begins. |
| Dialogue Manager | M4 | NPC dialogue and branching text | Evaluate when narrative content enters production. |
| Sentry Godot | Post-alpha | Crash, error, and release monitoring | Defer until consent, privacy, release-symbol, and environment policies exist. |
| Juicee / Saltmire Juice | Prototype / M2-08 | Shake, hit-stop, flash, and combat feel | Optional presentation acceleration; never a simulation dependency. |

Each implementation issue must still verify the selected component's current
release, license, Godot compatibility, and maintenance state before installation.
