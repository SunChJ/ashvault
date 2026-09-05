class_name RoomDefinition
extends "res://game/content/content_definition.gd"

const Connector = preload("res://game/simulation/dungeon/room_connector.gd")
const Socket = preload("res://game/simulation/dungeon/encounter_socket.gd")
const Id = preload("res://game/content/stable_id.gd")
enum Role { ENTRANCE, COMBAT, REWARD, TRANSITION, BOSS }
const CELL_SIZE := 32
const MAX_EXTENT := 1024
var _schema_version: int = 1
var _revision: int = 1
var _role: int = Role.COMBAT
var _bounds: Rect2i = Rect2i(0, 0, 12, 10)
var _connectors: Array[Resource] = []
var _sockets: Array[Resource] = []

@export var schema_version: int:
	get:
		return _schema_version
	set(value):
		if not is_frozen():
			_schema_version = value

@export var revision: int:
	get:
		return _revision
	set(value):
		if not is_frozen():
			_revision = value

@export_enum("Entrance", "Combat", "Reward", "Transition", "Boss") var role: int:
	get:
		return _role
	set(value):
		if not is_frozen():
			_role = value

@export var bounds: Rect2i:
	get:
		return _bounds
	set(value):
		if not is_frozen():
			_bounds = value

@export var connectors: Array[Resource]:
	get:
		return _connectors.duplicate()
	set(value):
		if not is_frozen():
			_connectors = value.duplicate()

@export var sockets: Array[Resource]:
	get:
		return _sockets.duplicate()
	set(value):
		if not is_frozen():
			_sockets = value.duplicate()


func validation_error() -> String:
	if not Id.is_valid(content_id) or not content_id.begins_with("room."):
		return "Room requires a stable room ID."
	if schema_version != 1 or revision < 1 or revision > 2147483647:
		return "Unsupported room schema version or revision."
	if not tags.is_empty() or not dependencies.is_empty():
		return "Rooms use explicit connectors and sockets, without tags or dependencies."
	if role < Role.ENTRANCE or role > Role.BOSS:
		return "Room role is invalid."
	if bounds.position != Vector2i.ZERO or bounds.size.x < 1 or bounds.size.y < 1 or bounds.size.x > MAX_EXTENT or bounds.size.y > MAX_EXTENT:
		return "Room bounds require a zero local origin and dimensions from 1 to 1024."
	if connectors.is_empty() or connectors.size() > 16 or sockets.size() > 64:
		return "Room requires 1 to 16 connectors and at most 64 encounter sockets."
	var seen: Dictionary = {}
	var occupied: Array[Rect2i] = []
	for value: Resource in connectors:
		if not value is Connector:
			return "Room connectors must be RoomConnector Resources."
		var error: String = value.validation_error(bounds.size)
		if not error.is_empty():
			return error
		if seen.has(value.connector_id):
			return "Room connector IDs must be unique."
		seen[value.connector_id] = true
		var rect: Rect2i = value.clearance_rect(bounds.size)
		for prior: Rect2i in occupied:
			if rect.intersects(prior):
				return "Room connector clearances overlap."
		occupied.append(rect)
	var counts: Dictionary = {}
	for value: Resource in sockets:
		if not value is Socket:
			return "Room encounter sockets must be EncounterSocket Resources."
		var error: String = value.validation_error(bounds)
		if not error.is_empty():
			return error
		if seen.has(value.socket_id):
			return "Room encounter socket IDs must be unique."
		seen[value.socket_id] = true
		counts[value.kind] = counts.get(value.kind, 0) + 1
		for prior: Rect2i in occupied:
			if value.area.intersects(prior):
				return "Encounter sockets overlap a connector clearance or another socket."
		occupied.append(value.area)
	if counts.get(Socket.Kind.ENTRY, 0) != (1 if role == Role.ENTRANCE else 0):
		return "Exactly one entry socket belongs in an entrance room only."
	if counts.get(Socket.Kind.BOSS, 0) != (1 if role == Role.BOSS else 0):
		return "Exactly one boss socket belongs in a boss room only."
	if role == Role.COMBAT and counts.get(Socket.Kind.SPAWN, 0) < 1:
		return "Combat rooms require a spawn socket."
	if role == Role.REWARD and counts.get(Socket.Kind.REWARD, 0) < 1:
		return "Reward rooms require a reward socket."
	if role == Role.TRANSITION and connectors.size() < 2:
		return "Transition rooms require at least two connectors."
	return ""


func connector(id: String) -> Resource:
	for value: Resource in connectors:
		if value is Connector and value.connector_id == id:
			return value
	return null


func freeze() -> void:
	_connectors.sort_custom(func(a: Resource, b: Resource) -> bool: return a.connector_id < b.connector_id)
	_sockets.sort_custom(func(a: Resource, b: Resource) -> bool: return a.socket_id < b.socket_id)
	for value: Resource in _connectors + _sockets:
		value.freeze()
	super.freeze()


func descriptor() -> Dictionary:
	var connector_values: Array = []
	var socket_values: Array = []
	for value: Resource in connectors:
		if value is Connector:
			connector_values.append(value.descriptor())
	for value: Resource in sockets:
		if value is Socket:
			socket_values.append(value.descriptor())
	connector_values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.connector_id < b.connector_id)
	socket_values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.socket_id < b.socket_id)
	return {"schema_version": schema_version, "definition_id": content_id, "revision": revision,
		"role": role, "cell_size": CELL_SIZE, "bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"connectors": connector_values, "sockets": socket_values}


func validation_metadata() -> Dictionary:
	return {"validation_version": 1, "definition_id": content_id, "revision": revision,
		"connector_count": connectors.size(), "socket_count": sockets.size(),
		"descriptor_hash": JSON.stringify(descriptor()).sha256_text()}
