# 003.029 — Authored room modules and connection contracts

## Context

M4-01 supplies deterministic room descriptors for later seeded graph assembly.
No room authoring or dungeon graph subsystem exists yet. Gameplay definitions
already use validated, immutable Resources and feature-specific catalogs.

## Change

- Author typed room, connector, and encounter-socket Resources with stable IDs.
  Use positive integer-grid bounds, cardinal boundary openings, connection
  kinds, and inward clearance rectangles. Bound geometry before arithmetic.
- Validate roles, required sockets, duplicate IDs, bounds, and overlapping
  clearance/socket areas before atomic catalog publication. Publish sorted,
  plain descriptor values and versioned validation evidence.
- Validate pairwise connections using opposite normals, equal kind/width,
  exact boundary alignment, and non-overlapping translated room interiors.
  Support translation only; graph assembly and rotation remain M4-02 decisions.
- Add entrance/combat/reward/transition/boss Resource and scene fixtures.
  Presentation reads descriptors; descriptors never reference scenes or Nodes.

## Decisions

Use native Resource, Rect2i, Vector2i, PackedScene, and the existing ContentCatalog.
The [official Better Terrain listing](https://godotengine.org/asset-library/asset/1806)
describes a TileMapLayer terrain-authoring tool (Unlicense). Its terrain painting
surface does not implement the required simulation connection contract. Defer it
until tile artwork needs that workflow; do not install a generator or editor
plugin for this bounded descriptor task. Native
[Rect2i geometry](https://docs.godotengine.org/en/4.7/classes/class_rect2i.html)
supports explicit integer adjacency without float tolerances.

No traversal/pathfinding claim, encounter spawning, seed consumption, save
migration, or playable town/dungeon loop is included in this change.

## Validation

- Focused headless fixture passed for five native Resource/Scene pairs and
  both horizontal and vertical connection directions, including negative origins
  and repeated use of the same module definition.
- Rejected malformed schema/revision/role/IDs, missing required sockets, invalid
  nested Resources, duplicate IDs, bounds overflow, overlapping clearances/socket
  areas, incompatible widths/kinds, same-facing normals, misaligned boundaries,
  overlapping placements, unsupported scene transforms, and unpublished or
  manually frozen invalid drafts.
- Atomic publication, retry after rejection, detached descriptors, nested
  immutability, and order-independent validation hashes passed.
- `python3 tools/ci/run_tests.py` passed: 49 Python tests and all Godot checks.
  The final explicit cell-size descriptor field passed the focused fixture too.
- Windows/macOS CI must pass on the PR's final commit before merge.

## Current state

Implemented. The maintained contract is
[dungeon/README.md](../../project-ashvault/game/simulation/dungeon/README.md).
Five fixtures publish room identity, role, bounds, connector/socket counts, and
stable descriptor hashes without a scene tree. PackedScene checks separately
verify presentation composition. No dependency, generator, graph assembly,
movement topology, or save-format change was introduced.
