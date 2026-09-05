extends SceneTree

const Rooms = preload("res://game/simulation/dungeon/room_catalog.gd")
const Room = preload("res://game/simulation/dungeon/room_definition.gd")
const Connector = preload("res://game/simulation/dungeon/room_connector.gd")
const Socket = preload("res://game/simulation/dungeon/encounter_socket.gd")
const Connection = preload("res://game/simulation/dungeon/room_connection.gd")
const Module = preload("res://game/presentation/dungeon/authored_room.gd")
const ROLES := ["entrance", "combat", "reward", "transition", "boss"]

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions: Array = []
	for role: String in ROLES:
		definitions.append(load("res://tests/fixtures/rooms/%s.tres" % role))
	var catalog := Rooms.new()
	_check(catalog.load_definitions(definitions).is_empty(), "Five authored roles must publish.")
	if not catalog.is_loaded():
		_finish()
		return
	var report: Dictionary = catalog.validation_report()
	_check(report.rooms.size() == 5, "Validation evidence must cover every room.")
	for role: String in ROLES:
		var scene: PackedScene = load("res://tests/fixtures/rooms/%s.tscn" % role)
		var module: Node2D = scene.instantiate()
		_check(module is Module and module.validation_error().is_empty(), "Authored scene must compose a valid descriptor.")
		_check(module.definition == catalog.get_definition("room.fixture." + role), "Scene and simulation must share the published Resource.")
		module.position = Vector2(64, 96)
		_check(module.connector_position("connector.west") == Vector2(0, 160), "Presentation coordinates must derive from descriptor grid units.")
		module.rotation = PI / 2
		_check(not module.validation_error().is_empty(), "Scene rotation must not silently disagree with translation-only geometry.")
		module.free()
	_test_connections(catalog)
	_test_validation()
	_test_publication(catalog, report)
	print(JSON.stringify({"fixture": "room_modules", "validation": report}))
	_finish()


func _test_connections(catalog: RefCounted) -> void:
	var a: Resource = catalog.get_definition("room.fixture.entrance")
	var b: Resource = catalog.get_definition("room.fixture.combat")
	var aligned := Connection.align(a, "connector.east", b, "connector.west", Vector2i(20, -10))
	_check(aligned.error.is_empty() and aligned.origin == Vector2i(32, -10), "Opposed openings must align by exact grid translation.")
	_check(Connection.validation_error(a, Vector2i(20, -10), "connector.east", b, aligned.origin, "connector.west").is_empty(), "Shared boundary is valid; room interiors must not overlap.")
	_check(not Connection.validation_error(a, Vector2i.ZERO, "connector.east", b, Vector2i(11, 0), "connector.west").is_empty(), "Overlapping room placement must fail.")
	_check(not Connection.validation_error(a, Vector2i.ZERO, "connector.east", b, Vector2i(12, 1), "connector.west").is_empty(), "Offset opening segments must fail.")
	_check(not Connection.align(a, "connector.east", b, "connector.east").error.is_empty(), "Equal-facing connectors must fail.")
	_check(not Connection.align(a, "connector.missing", b, "connector.west").error.is_empty(), "Missing connector references must fail.")
	_check(not Connection.align(a, "connector.east", b, "connector.west", Vector2i(2147483647, 0)).error.is_empty(), "Origins must be bounded before vector arithmetic.")
	for change: String in ["kind", "width"]:
		var changed := _draft("combat")
		var west: Resource = changed.connector("connector.west")
		if change == "kind":
			west.kind = Connector.Kind.GATE
		else:
			west.width = 3
		var other := Rooms.new()
		_check(other.load_definitions([changed]).is_empty(), "Individually legal connector variants must publish.")
		_check(not Connection.align(a, "connector.east", changed, "connector.west").error.is_empty(), "Incompatible connector %s must fail." % change)
	var vertical := _draft("transition")
	vertical.connector("connector.west").facing = Connector.Facing.NORTH
	vertical.connector("connector.east").facing = Connector.Facing.SOUTH
	var vertical_catalog := Rooms.new()
	_check(vertical_catalog.load_definitions([vertical]).is_empty(), "North/south room must publish.")
	var below := Connection.align(vertical, "connector.east", vertical, "connector.west", Vector2i(-10, 30))
	_check(below.error.is_empty() and below.origin == Vector2i(-10, 40), "North/south adjacency must align exactly and allow repeated modules.")
	var above := Connection.align(vertical, "connector.west", vertical, "connector.east")
	_check(above.error.is_empty() and above.origin == Vector2i(0, -10), "Negative placement must preserve opposite boundary alignment.")
	var invalid_frozen := _draft("combat")
	invalid_frozen.connector("connector.west").facing = 99
	invalid_frozen.freeze()
	_check(not Connection.align(a, "connector.east", invalid_frozen, "connector.west").error.is_empty(), "Manually freezing an invalid draft must not bypass geometry validation.")
	_check(not Connection.align(a, "connector.east", _draft("combat"), "connector.west").error.is_empty(), "Runtime placement requires published descriptors.")


func _test_validation() -> void:
	var invalid: Array = []
	for row: Array in [["bounds", Rect2i(0, 0, 0, 10)], ["bounds", Rect2i(0, 0, -1, 10)], ["bounds", Rect2i(1, 0, 12, 10)], ["bounds", Rect2i(0, 0, 2147483647, 10)], ["role", 99], ["schema_version", 2], ["revision", 0], ["content_id", "not_valid"]]:
		var room := _draft("combat")
		room.set(row[0], row[1])
		invalid.append(room)
	for row: Array in [["facing", 99], ["kind", 99], ["offset", -1], ["offset", 2147483647], ["width", 0], ["clearance", 0], ["clearance", 1000], ["connector_id", "bad"]]:
		var room := _draft("combat")
		room.connectors[0].set(row[0], row[1])
		invalid.append(room)
	var overlap := _draft("combat")
	overlap.connectors[1].facing = overlap.connectors[0].facing
	invalid.append(overlap)
	var duplicate := _draft("combat")
	duplicate.connectors[1].connector_id = duplicate.connectors[0].connector_id
	invalid.append(duplicate)
	for area: Rect2i in [Rect2i(-1, 1, 2, 2), Rect2i(2, 2, 0, 2), Rect2i(0, 4, 2, 2)]:
		var room := _draft("combat")
		room.sockets[0].area = area
		invalid.append(room)
	var empty_sockets: Array[Resource] = []
	for resource: Resource in [null, Resource.new()]:
		var resources: Array[Resource] = [resource]
		var wrong_connector := _draft("combat")
		wrong_connector.connectors = resources
		invalid.append(wrong_connector)
		var wrong_socket := _draft("combat")
		wrong_socket.sockets = resources
		invalid.append(wrong_socket)
	for field: String in ["socket_id", "kind"]:
		var wrong := _draft("combat")
		wrong.sockets[0].set(field, "bad" if field == "socket_id" else 99)
		invalid.append(wrong)
	var no_spawn := _draft("combat")
	no_spawn.sockets = empty_sockets
	invalid.append(no_spawn)
	var no_entry := _draft("entrance")
	no_entry.sockets[0].kind = Socket.Kind.SPAWN
	invalid.append(no_entry)
	var no_boss := _draft("boss")
	no_boss.sockets[0].kind = Socket.Kind.SPAWN
	invalid.append(no_boss)
	var no_reward := _draft("reward")
	no_reward.sockets = empty_sockets
	invalid.append(no_reward)
	var no_transition := _draft("transition")
	var only: Array[Resource] = [no_transition.connectors[0]]
	no_transition.connectors = only
	invalid.append(no_transition)
	var repeated := _draft("combat")
	var socket: Resource = repeated.sockets[0].duplicate(true)
	socket.socket_id = "socket.other"
	var sockets: Array[Resource] = [repeated.sockets[0], socket]
	repeated.sockets = sockets
	invalid.append(repeated)
	for room: Resource in invalid:
		var catalog := Rooms.new()
		_check(not catalog.load_definitions([room]).is_empty(), "Malformed room must fail: " + str(room.descriptor()))
		_check(not room.is_frozen() and not catalog.is_loaded(), "Failed publication must remain atomic.")


func _test_publication(catalog: RefCounted, report: Dictionary) -> void:
	var room: Resource = catalog.get_definition("room.fixture.combat")
	var original: Dictionary = room.descriptor()
	_check(original.cell_size == 32, "Plain descriptors must retain the grid-to-world unit contract.")
	room.bounds = Rect2i(0, 0, 99, 99)
	room.connectors[0].width = 9
	room.sockets[0].area = Rect2i(1, 1, 9, 9)
	room.connectors.clear()
	var detached: Dictionary = room.descriptor()
	detached.connectors.clear()
	_check(room.descriptor() == original, "Published room and nested descriptors must remain immutable.")
	var reversed: Array = []
	for role: String in ROLES:
		var draft := _draft(role)
		var connectors: Array[Resource] = draft.connectors
		connectors.reverse()
		draft.connectors = connectors
		reversed.push_front(draft)
	var second := Rooms.new()
	_check(second.load_definitions(reversed).is_empty() and second.validation_report() == report, "Authoring order must not change validation hashes.")
	var retry := Rooms.new()
	var valid := _draft("combat")
	var bad := _draft("reward")
	bad.bounds = Rect2i()
	_check(not retry.load_definitions([valid, bad]).is_empty() and not valid.is_frozen(), "One invalid room must not freeze another room.")
	var duplicate_catalog := Rooms.new()
	_check(not duplicate_catalog.load_definitions([valid, valid]).is_empty() and not valid.is_frozen(), "Duplicate room IDs must fail atomically through ContentCatalog.")
	_check(retry.load_definitions([valid]).is_empty(), "A failed catalog must remain reusable.")


func _draft(role: String) -> Resource:
	# Ignore the published Resource cache when creating mutable authoring fixtures.
	return ResourceLoader.load("res://tests/fixtures/rooms/%s.tres" % role, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("Production room module tests passed.")
	quit(0 if failures.is_empty() else 1)
