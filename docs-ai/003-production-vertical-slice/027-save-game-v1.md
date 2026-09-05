# 003.027 — SaveGameV1 and recoverable atomic commits

## Context and plan

M3-08 persists character identity, item records, inventory/equipment/materials,
progression, checkpoint/run loot, settings, named RNG streams, and version IDs.
Reconstruct fresh simulation objects before returning a loaded session; never
mutate the active session during validation or recovery.

Add unused-state inventory and loot restore contracts with full UID/location,
content, provenance, owner, and equipment checks. SaveGameV1 composes them in
order: item world, progression, inventory (including passive modifiers), RNG,
then loot. This first save contract supports one character and checkpoint state;
mid-cast combat/projectile snapshots and M4 dungeon state are not invented here.

Use a checksummed exact JSON payload string inside a small envelope. Reject
non-JSON engine values, unsafe numbers, excessive nesting/size, unsupported
versions and missing content. Validate checksum before forward migration and
simulation reconstruction. Explicit v0 fixture migration adds default settings
and upgrades pre-material inventory observations; unknown versions reject.

Write and flush a same-directory temporary file, verify it, preserve a validated
old primary through backup temporary + rename, then rename the new primary.
Never unlink the primary before replacement. Corrupt primary loads try backup;
new writes must not rotate a corrupt primary over a good backup. Structured
breadcrumbs distinguish validation, temporary write, backup, commit and recovery.
Single writer per save path is an application composition requirement.

Reviewed native FileAccess/DirAccess and Asset Library SaveState/Save Manager
Lite. Their general node/autoload save workflows do not supply this project's
UID/content/RNG reconstruction contracts. Keep a small local DTO/file boundary;
no plugin, arbitrary object deserializer, cloud sync, or encryption dependency.
Godot flush/rename cannot promise hardware power-loss durability or directory
fsync; validate process-interruption recovery without claiming that guarantee.

## Validation plan

Headless fixtures cover real file round-trip, exact RNG continuation, ownership
and equipment reconstruction, checksum/missing-content errors, backup recovery,
interruption after temporary and backup stages, write errors, engine-value
rejection, and the v0-to-v1 migration. Follow with full local and platform CI.

## Outcome and validation

Implemented fresh inventory/loot reconstruction, exact-payload SHA-256 envelope,
explicit pre-release v0-to-v1 migration, bounded JSON validation, verified primary
and backup replacement, and structured recovery results. A first save seeds its
backup from validated new data; corrupt primary data never rotates over a valid
backup. Current contract is [save/README.md](../../project-ashvault/game/infrastructure/save/README.md).

Passed focused SaveGameV1 real-file fixtures and the complete local
`python3 tools/ci/run_tests.py` suite (49 Python tests, all Godot contracts,
replay/performance gates, and scene smoke). Fixtures verify item/inventory/loot/
progression round-trip, next draws from all three RNG streams, malformed content
and ownership, checksum and backup recovery, first-generation backup, partial
files, injected stops at two commit boundaries, I/O failures, engine-value
rejection, and every supported migration step. Local full-suite output is
`.artifacts/save-validation.log` (ignored).

The ecosystem candidates reviewed were
[SaveState](https://godotengine.org/asset-library/asset/4990) and
[Save Manager Lite](https://godotengine.org/asset-library/asset/4430), alongside
native FileAccess/DirAccess documentation. No dependency was needed for the
project-specific content/UID/reconstruction invariants.

No feature scope deviations. Interruption coverage uses deterministic fault
injection against real files, not physical power cuts. Mid-combat resumption,
future dungeon content, multi-character saves and cloud conflict handling remain
outside this checkpoint schema.
