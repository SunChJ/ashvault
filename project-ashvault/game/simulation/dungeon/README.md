# Authored room contracts

`RoomDefinition`, `RoomConnector`, and `EncounterSocket` are authored Godot
Resources. `RoomCatalog` validates the complete set before delegating atomic
publication to `ContentCatalog`; successful publication freezes rooms and their
nested Resources. No descriptor references a scene, Node, or presentation path.

## Geometry and authoring

| Contract | Rules |
| --- | --- |
| Room identity | Stable `room.*` ID, schema version 1, positive signed 32-bit content revision. |
| Bounds | `Rect2i` with local origin `(0, 0)` and each dimension 1–1024 grid cells. One cell is 32 world units. |
| Connector identity | Unique `connector.*` ID within the room; 1–16 connectors per room. |
| Connector kind | `PASSAGE` or `GATE`; both sides of a connection must have the same kind. A gate is a compatibility category, not an implemented lock mechanic. |
| Opening | Cardinal facing and non-negative tangent offset; width 1–32, fully inside the corresponding wall span. |
| Clearance | 1–16 cells inward from the opening, fully inside the room. Different connector clearance rectangles cannot overlap. |
| Encounter socket | Unique `socket.*` ID, typed kind, positive `Rect2i` area entirely inside the room; at most 64 sockets. |
| Occupancy | Socket areas cannot overlap each other or any connector clearance rectangle. Edge contact is allowed. |

North/south offsets run left to right; west/east offsets run top to bottom.
North is negative Y. The connector's `start(size)` returns the first point of
its boundary segment. `clearance_rect(size)` returns its reserved inward area.
Validate an authoring draft before calling geometry helpers. Room connection
APIs revalidate frozen definitions so manual freezing cannot bypass checks.
Bounds and offsets are checked before endpoint arithmetic to prevent overflow.

Socket kinds are `ENTRY`, `SPAWN`, `REWARD`, `BOSS`, and `EXIT`. Role constraints:

- Entrance: exactly one entry socket; other room roles cannot contain entry sockets.
- Combat: at least one spawn socket.
- Reward: at least one reward socket.
- Transition: at least two connectors.
- Boss: exactly one boss socket; other room roles cannot contain boss sockets.

Other socket kinds may coexist when their areas do not overlap. Exit sockets
mark candidate return/exit locations; uniqueness and reachability across the
assembled dungeon belong to the graph validator. Sockets do not yet select enemy
archetypes, spawn actors, grant rewards, or assign encounter pacing budgets.

## Connecting published modules

`RoomConnection.align(a, connector_a, b, connector_b, origin_a)` returns
`{error: "", origin: Vector2i}` for the translated origin of room B, or `{error}`.
`validation_error(a, origin_a, connector_a, b, origin_b, connector_b)` validates
an explicit proposed placement. Origins must remain within ±1,000,000 cells on
both axes, including the origin computed by alignment.

Both APIs require valid frozen definitions, known connector IDs, matching kind
and width, opposite outward normals, identical world-space opening segments,
and non-overlapping room interiors. Shared boundaries are valid. A definition
can be reused for multiple room instances. Placement uses translation only;
rotation, reflection, seed consumption, graph search, and connector-use tracking
are outside M4-01. The assembler must check each placed room against every prior
room and prevent reusing occupied connectors.

A connector's width and clearance describe reserved geometric space; they do
not prove navigation through a furnished room. Collision obstacles, actor-radius
clearance, and traversal reachability need separate validation when authored
room topology is integrated with movement.

## Inspectable publication evidence

`descriptor()` returns detached plain values with room identity, schema/revision,
role, cell size, integer bounds, and connector/socket records sorted by stable ID. No engine
objects or vector/rectangle values enter this descriptor. Enum numeric values are
part of schema version 1 and must not be reordered silently.

`validation_metadata()` returns validation version, identity/revision, counts,
and the SHA-256 of the sorted JSON descriptor. It describes the current values;
only a successful catalog publication certifies validity. `validation_report()`
on a published catalog returns these records in sorted room-ID order. A failed
catalog returns no report and can be retried without freezing valid siblings.
Catalogs accept 1–512 definitions. Tags and dependency lists remain empty; future
room graphs use explicit runtime connections rather than content dependency edges.

## Presentation and fixtures

`game/presentation/dungeon/AuthoredRoom` consumes a descriptor and draws a simple
floor, reserved connector space, and socket outlines. Its `connector_position`
returns the opening midpoint in local world units. Scene roots support finite
translation and an identity basis; rotated/scaled/skewed roots fail validation.
Scene parent/camera transforms are presentation concerns and never alter the
simulation descriptor.

Five `.tres`/`.tscn` pairs under `tests/fixtures/rooms/` cover entrance, combat,
reward, transition, and boss modules. They are contract fixtures, not final dungeon
artwork or the playable dungeon loop. Run their descriptor and scene checks without
opening the Editor:

```sh
"$ASHVAULT_GODOT" --headless --path project-ashvault \
  --script res://tests/production/test_room_modules.gd
```

The fixture prints structured validation evidence. The unified CI runner checks
its exit status and Godot error output on Windows and macOS.
