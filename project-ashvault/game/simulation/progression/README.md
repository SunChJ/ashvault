# Character progression

CharacterProgression belongs to the character lifetime, outside transient run
state. It stores cumulative experience, skill/passive allocations, revision, and
one XP sequence watermark per run. Level and available points are derived;
callers cannot edit them independently. Snapshot/restore carries progression
between runs; SaveGameV1 owns durable file I/O and migrations in the next task.

## Authored content

ProgressionDefinition is a frozen native Resource containing cumulative XP
thresholds (level one starts at zero), points earned per level, and maximum
skill rank. Thresholds strictly increase, with at most 100 levels and positive
int32 totals. Points per level are 1–100 and skill rank cap 1–20.
`character_curve.tres` provides the initial 20-level curve, one point per level
gain, and rank cap 20. Its final threshold is 19000 XP. These are initial slice
rules; balance remains downstream.

ProgressionCatalog accepts configured AbilityDefinition skills and
PassiveDefinition Resources. Passives have a stable `passive.*` ID, minimum
level, rank cap, prerequisite passive ranks, and numeric modifier templates.
Publication rejects unknown prerequisites, impossible prerequisite rank bounds,
cycles, invalid modifiers, and duplicate IDs before freezing content.

StatModifierTemplate contains the existing native numeric effect implementation
extracted from ItemStatEffect. Its IDs use `stat_effect.*`; ItemStatEffect retains
its original script path, exported fields, and `item_effect.*` prefix. Both use
StatModifier/StatResolver, including conditions and conversion bounds. This
avoids making passive content depend on the item module or duplicating the
modifier interpreter.

## Transactions

`award_xp(run_id, sequence, amount)` requires a stable run ID and positive int32
sequence/amount. A sequence must exceed the last accepted value for that run;
duplicates and out-of-order rewards reject. The authority adapter must submit
rewards in authoritative order and provide a unique persistent run ID. Watermarks
survive snapshots so reopening a run cannot grant its old rewards again. Only
one sequence per run is retained, not one occurrence ID per kill.

XP clamps to the final threshold. One award can gain multiple levels; further
rewards at the cap advance the watermark without minting additional points.
Each gained level earns the authored points. All registered skills start at rank
one; each skill point adds one rank. Passives start unallocated. Both families
spend the same pool, with no hidden initial points.

`allocate(kind, id, amount, expected_revision)` accepts `skills` or `passives`
and a positive rank increment. It validates the current revision, ID, level,
rank cap, prerequisite ranks, and total earned budget. There is no decrement or
arbitrary allocation replacement command. `respec(expected_revision)` explicitly
clears both allocation families and refunds their derived budget. Respec is free
in this slice. XP and reward watermarks remain intact. Successful mutations
increment revision; stale UI commands reject, and int32 revision exhaustion
rejects without mutation.

Passive numeric amounts scale linearly by allocated rank. Their modifiers use
stable `progression.passive.*.stat_effect.*` source IDs and resolve through
StatResolver before allocation/respec publication. Unknown stats and modifier
resolution errors preserve allocations, points, revision, and the previous
immutable StatSnapshot. `stats()` is the unconditional progression preview;
`passive_modifiers()` exposes immutable shared modifiers for composition with
gear and active combat conditions. Existing combat/equipment snapshots are not
mutated; consumers must rebuild their composed stats after allocation/respec.

`skill_rank(ability_id)` supplies the rank for existing AbilityDefinition
milestones/execution or the existing StormweaverCatalog rank inputs. Unknown
skills return zero. Progression does not implement another ability executor.
The fixture verifies rank five selects Ward's existing 360-tick milestone.
Run/combat and UI composition remain downstream work.

## Persistence and validation

Snapshot schema 1 contains exactly `schema_version`, `character_id`,
`experience`, `skills`, `passives`, `reward_sequences`, and `revision`. It uses
plain JSON data. Restore accepts only configured, unused state with the same
character identity, normalizes integer numbers, validates allocation budget,
prerequisites and reward watermarks, and re-resolves modifiers before publishing.
Active state cannot rewind through restore. Invalid input leaves the fresh state
untouched. Snapshots are defensive copies, not mutable live character state.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project-ashvault --script res://tests/production/test_progression.gd
python3 tools/ci/run_tests.py
```

Fixtures cover XP thresholds/multiple gains/cap, persistent reward deduplication,
shared point conservation, prerequisites/cycles, rank caps, explicit respec,
stale commands, modifier failure rollback, corrupted/overspent restore, JSON
round-trip across runs, ability milestones, frozen Resources, and deterministic
replay with reversed catalog publication order.
