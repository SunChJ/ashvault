# 003.013 — Deterministic Cast Runtime

## Context

M2-02 turns the M1 cast-intent transitions into authoritative ability
activation. Timing, resource commitment, cooldowns, movement interaction, and
interruptions must remain transactional and independent of scenes, frame time,
animation, and plugin lifecycle.

## Planned change

An immutable ability loadout binds stable ability definitions to integer slots
and one cast policy per binding. The policy declares whether movement is
allowed, locked, or cancels the cast; whether manual cancellation is allowed;
which stable interruption reasons may cancel it; and whether activating the
binding may cancel another active cast. This represents Tempest Dash without a
hard-coded ability ID.

`EntityWorld` accepts optional actor loadouts. A loadout-enabled entity tracks
the active slot, start/ready/recovery ticks, per-slot cooldown end ticks, and
the last cancellation reason. Cast start validates slot, cooldown, resource,
and replacement policy but spends nothing. Cast release is permitted only when
ready; it revalidates resource and cooldown, then spends cost and starts
cooldown atomically. Release remains observable for its accepted tick, followed
by the authored number of recovery ticks. Cancellation before release spends
nothing.

External interruption DTOs are processed before player commands in the same
transaction. Unlisted interruption reasons are ignored; listed reasons produce
an explicit canceled state. Non-zero movement commands follow the active
binding's movement policy. All state changes remain inside the existing
copy-on-write tick transaction.

Compatibility is additive. Worlds without actor loadouts retain M1/M2-01
behavior and frozen hashes. Loadout-enabled worlds use a new canonical state
hash schema that includes loadout behavior and cast runtime state. The global
simulation version remains unchanged because legacy inputs cannot opt into the
new configuration accidentally.

## Ecosystem review

| Candidate | Decision |
| --- | --- |
| Godot integer tick state plus existing `AbilityDefinition`, `PlayerCommand`, and snapshots | Adopt. These are already the authoritative, headless contracts and preserve replay control. |
| Godot `Timer` | Reject as authority. It is a `Node`, counts floating-point seconds, and follows process/physics callbacks rather than the explicit world transaction. |
| Godot State Charts | Defer for presentation and animation orchestration after manual installation. Its state-machine tooling is useful, but scene/plugin state must mirror snapshots rather than own cast results. |
| `godot-gameplay-abilities` / Godot Gameplay Systems | Reject for the kernel. Its `AbilityContainer` is Node-driven and invokes per-process/per-physics callbacks; adopting it would duplicate the existing definitions, stats, effects, and state ownership. |
| GodotGAS | Defer. It is actively maintained and MIT-licensed, but its attribute, tag, effect, cue, autoload, and editor surfaces overlap the existing kernel and broaden the trusted runtime substantially. |
| AsepriteWizard 9.8.0 | Retain as an editor-only asset pipeline dependency. It has no authority over cast timing or state. |

## Validation

- Test start, early release, ready release, recovery, cooldown expiry, and
  zero-cost/zero-time boundaries.
- Test insufficient resource and cooldown rejection without resource, tick,
  movement, sequence, or cast-state mutation.
- Test movement allow/lock/cancel policies, manual cancellation, listed and
  ignored interruptions, and cancel-into-Tempest-Dash policy.
- Compare loadout-enabled rendered and headless hashes and retain all legacy
  replay goldens.
- Run the editor scan, unified local suite, and macOS/Windows CI matrix.

## Current state

Implemented locally for #16. Ability bindings and loadouts are immutable,
definition-backed values with normalized slot and interruption ordering.
Loadout-enabled entities expose start/ready/release/recovery/cancel phases,
atomic release cost and cooldown commitment, movement policy, external
interruptions, death cancellation, and data-driven cast replacement. Legacy
worlds do not enter the new code path.

The cast replay freezes state hash
`3f4a330d75b3f436e487b46e832039da30214844a701c543a5bcdb1d9f987af7`.
The M1 replay retains state hash
`650d204d9ae61efcab7c731456e66db45968ba61f2af16e0b0d3494a24aea6f8`
and report hash
`d8e0ef3d3b1791c45f3d9366f67ac40c49864c76d24008f683b35207319dea64`;
the M2-01 movement replay golden also passes unchanged.

The unified local suite passes with 47 Python tests, thirteen GDScript
contract suites, both report-schema validators, the M1 kernel gate, numerical
regressions, and the main-scene smoke test. The editor scan passes, and all 68
repository-owned GDScript files outside third-party addons have unique UID
sidecars. The linked PR and #16 remain the authoritative delivery state;
macOS and Windows CI are pending that PR.
