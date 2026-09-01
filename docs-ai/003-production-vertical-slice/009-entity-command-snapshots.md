# 003.009 — Entity State, Commands, and Presentation Snapshots

## Context

M1-06 establishes the authoritative entity boundary consumed by the later
headless simulator and presentation adapters. It must advance independently of
rendered frames, reject invalid player command sequences without partial state,
and expose only read-only presentation data.

## Planned change

`EntityWorld` owns configured `EntityState` values and advances exactly one
explicit 60 Hz tick per successful command batch. Callers cannot mutate stored
entities directly. A batch uses copy-on-write staging, orders commands by actor
ID and client sequence, validates the entire transition, and publishes the
staged state only when every command succeeds. A rejected batch does not advance
the tick, consume a sequence, or retain earlier transitions from that batch.

`PlayerCommand` is immutable after validation and uses the frozen fields `tick`,
`actor_id`, `command_type`, `aim_vector`, `ability_slot`, and
`client_sequence`. Supported command IDs are movement, aim, cast start, cast
release, and cancel. Movement and aim update input intent only; spatial
integration and cast timing remain M2 work. Client sequences are positive and
strictly increasing per actor, reserving their future authority role without
introducing networking.

Entity cast intent follows a small deterministic state machine:

```text
idle -> started -> released
                -> canceled
released|canceled -> idle at the next accepted tick
```

`PresentationSnapshot` contains immutable, runtime-ID-sorted entity views and
the authoritative state hash for one tick. The SHA-256 input is a canonical
array schema rather than dictionary iteration order. Hash calculation is lazy
and cached per accepted tick. Snapshot construction is a pure read and
presentation may be entirely disabled without changing the hash.

## Ecosystem review

| Candidate | Decision |
| --- | --- |
| Godot `RefCounted`, `Vector2`, `JSON`, and `HashingContext` | Adopt. They provide the required headless values, serialization primitives, and hashing without a runtime dependency. |
| [`godothub/godot-ecs`](https://github.com/godothub/godot-ecs) | Reject for this boundary. Its broad runner, mutable component, parallel scheduler, event, and save surfaces duplicate frozen project ownership and do not supply atomic player-command semantics. |
| Godot Asset Library ECS packages [1680](https://godotengine.org/asset-library/asset/1680), [1727](https://godotengine.org/asset-library/asset/1727), and [3115](https://godotengine.org/asset-library/asset/3115) | Reject. They are general ECS/workflow frameworks with older update histories and no stronger deterministic command/snapshot contract than the built-in approach. |
| Add rollback networking now | Reject. `client_sequence` reserves authority validation, but networking and rollback are explicit slice non-goals. |

## Validation

- Replay the same JSON command fixture through independent worlds and compare a
  golden state hash after every tick.
- Compare hashes when one replay publishes presentation snapshots and the other
  runs with presentation disabled.
- Reject duplicate, late, future, unknown-actor, non-player, malformed, and
  impossible cast commands without advancing or mutating state.
- Verify snapshot arrays and nested views cannot mutate the world or a published
  snapshot.
- Run the unified local suite and macOS/Windows CI matrix.

## Current state

Implementation and local validation are complete for M1-06. The JSON fixture
replays to the frozen SHA-256 hash
`93bc6abe5dda72e9e2ff6e8c634ddba37bb99177030d0703eb752a036d3ca274`
with or without presentation snapshots. The unified suite passes with 35
Python tests, ten production GDScript contract suites, performance report
validation, prototype regressions, and the main-scene smoke test. The editor
scan confirms complete unique UID coverage for all 58 GDScript files. The
linked PR and #12 remain the authoritative delivery state.
