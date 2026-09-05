# SaveGameV1

SaveGameV1 stores character identity, immutable item records, inventory locations,
materials/vendor stock/equipment, progression, checkpoint/run loot, settings,
named RNG streams, and content/simulation/save versions. This is a single-character
checkpoint contract. It does not serialize Nodes, Resources, callables, scene
ownership, active casts/projectiles, or future M4 dungeon state.

## Composition

Configure SaveGameV1 with the published item/progression/stat catalogs, loot
tables, set bonuses, and character base modifiers. These are runtime dependencies,
never serialized content objects. `capture(session)` builds a plain DTO from the
world, inventory, progression, RNG, loot, character identities, world-run fields,
and settings. Internal StringName dictionary keys normalize to JSON string keys.

The exact top-level fields are `schema_version`, `versions`, `character`,
`items`, `inventory`, `progression`, `world_run`, `settings`, and `rng`.
Character identity names the character, owner, creator, and item namespace.
World-run fields are stable `run_id`/`checkpoint_id`, nonnegative int32 `tick`,
and loot receipt/ground data. Settings currently contain master volume `[0,1]`
and fullscreen boolean. Do not pass arbitrary opaque scene state in these fields.

`reconstruct(dto)` creates fresh objects in this order:

1. ItemWorld validates all item IDs, records, and the UID allocator.
2. CharacterProgression validates XP, allocations, prerequisites, and watermarks.
3. InventoryState validates every UID has exactly one location across containers,
   ground, equipment, or consumed tombstones. It rebuilds equipment with shared
   base and passive modifiers; no derived stat values are trusted from disk.
4. RngStreams restores combat, loot, and dungeon states explicitly.
5. LootState validates receipt provenance against current tables and reconciles
   every ground UID with its reserved owner and occurrence.

Only a fully reconstructed session is returned. Callers replace their active
session after success; failed reconstruction never mutates it. Inventory/loot
restore rejects use on active state. CharacterProgression and ItemWorld retain
their existing unused-state restore requirements. Loaded equipment stats start
at revision/tick zero and contain no active transient combat conditions.

## Format and migration

The outer JSON envelope has exactly `format: "ashvault.save"`, `checksum`, and
`payload`. Payload is the **exact JSON string** whose UTF-8 bytes SHA-256 covers.
Using that string avoids checksumming a parse/re-serialize cycle that could alter
floating-point formatting. The checksum detects corruption; it is not an
anti-cheat signature. UID counters and RNG int64 values retain decimal strings.

SaveJson rejects engine values, nonfinite/unsafe numeric values, excessive depth
(32), more than 500000 values, keys above 4096 characters, and files above 16 MiB.
Native StringName keys are normalized; values must already be JSON primitives.
Loading validates envelope structure and checksum before parsing/migrating the
payload, then validates content references through simulation reconstruction.
Current content and simulation versions must match exactly. Unknown references
fail closed; release content-removal policy must be authored before removing IDs.

The only forward migration is the explicitly defined **pre-release fixture v0**
to v1: add default settings, upgrade inventory schema 1 to 2, and initialize the
previously absent owner material wallets. It preserves all item, progression,
loot, and RNG data. No shipped v0 save history is implied. Exact legacy shapes
are required, and future versions/downgrades reject. Add separately tested
forward steps when the real schema changes; do not infer fields from malformed
current saves.

## File lifecycle

Configure SaveStore with the codec and call `save_game(path, dto)` or
`load_game(path)`. The parent directory must already exist. Operations are
synchronous and require one writer per path; the application owns save scheduling.

A write validates/reconstructs the DTO before touching files, writes and flushes
`path.tmp`, and reads it back for validation. It writes a validated old primary
to `path.bak.tmp`, verifies it, then renames it over `path.bak`. If no valid prior
generation exists, it seeds the backup from the validated new data. A corrupt
primary never rotates over an existing valid backup. Finally it renames
`path.tmp` over the primary, without first unlinking that primary.

Loads try the primary and then the backup on any validation/reconstruction error.
Recovery returns `recovered: true` plus the primary error; it does not rewrite the
files during loading. Incomplete `.tmp`/`.bak.tmp` files are ignored. A later
successful write replaces them. One committed `.bak` generation is retained.

`breadcrumbs()` returns structured stage/result records for temporary validation,
backup, primary commit, and load/recovery. Failures carry explicit errors; no
user-facing message or vendor telemetry is sent by this layer.

Godot's [FileAccess flush](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html#class-fileaccess-method-flush)
and [DirAccess rename](https://docs.godotengine.org/en/stable/classes/class_diraccess.html#class-diraccess-method-rename-absolute)
provide the local file operations. The contract covers normal same-directory
replacement and interruption boundaries tested on supported platforms. It does
not claim filesystem directory-fsync or hardware power-loss durability.

## Reproduction

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project-ashvault --script res://tests/production/test_save_game.gd
python3 tools/ci/run_tests.py
```

The fixture uses a unique temporary user-data directory and real file operations.
It tests first/second save, full reconstruction and exact RNG continuation,
checksums, missing IDs, malformed ownership, backup recovery, corrupt-primary
backup preservation, partial temporary files, write failure, DTO engine-value
rejection, and v0 migration. A test subclass injects stops after verified temporary
write and after backup publication; this is deterministic interruption injection,
not a claim that CI physically cuts power. Tests clean only their own directory.
