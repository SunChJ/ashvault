class_name RoomConnector
extends Resource

const Id = preload("res://game/content/stable_id.gd")
enum Kind { PASSAGE, GATE }
enum Facing { NORTH, EAST, SOUTH, WEST }
const NORMALS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var _frozen := false
var _connector_id: String = ""
var _kind: int = Kind.PASSAGE
var _facing: int = Facing.NORTH
var _offset: int = 0
var _width: int = 2
var _clearance: int = 2

@export var connector_id: String:
	get:
		return _connector_id
	set(value):
		if not is_frozen():
			_connector_id = value

@export_enum("Passage", "Gate") var kind: int:
	get:
		return _kind
	set(value):
		if not is_frozen():
			_kind = value

@export_enum("North", "East", "South", "West") var facing: int:
	get:
		return _facing
	set(value):
		if not is_frozen():
			_facing = value

@export var offset: int:
	get:
		return _offset
	set(value):
		if not is_frozen():
			_offset = value

@export var width: int:
	get:
		return _width
	set(value):
		if not is_frozen():
			_width = value

@export var clearance: int:
	get:
		return _clearance
	set(value):
		if not is_frozen():
			_clearance = value


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	_frozen = true


func validation_error(size: Vector2i) -> String:
	if not Id.is_valid(connector_id) or not connector_id.begins_with("connector."):
		return "Connector requires a stable connector ID."
	if kind < Kind.PASSAGE or kind > Kind.GATE or facing < Facing.NORTH or facing > Facing.WEST:
		return "Connector kind or cardinal facing is invalid."
	if width < 1 or width > 32 or clearance < 1 or clearance > 16 or offset < 0 or offset > 1024:
		return "Connector width, clearance, or offset is out of range."
	var horizontal := facing in [Facing.NORTH, Facing.SOUTH]
	var span := size.x if horizontal else size.y
	var depth := size.y if horizontal else size.x
	if offset + width > span or clearance > depth:
		return "Connector opening or inward clearance exceeds room bounds."
	return ""


func normal() -> Vector2i:
	return NORMALS[facing]


func start(size: Vector2i) -> Vector2i:
	match facing:
		Facing.NORTH: return Vector2i(offset, 0)
		Facing.EAST: return Vector2i(size.x, offset)
		Facing.SOUTH: return Vector2i(offset, size.y)
		_: return Vector2i(0, offset)


func clearance_rect(size: Vector2i) -> Rect2i:
	match facing:
		Facing.NORTH: return Rect2i(offset, 0, width, clearance)
		Facing.EAST: return Rect2i(size.x - clearance, offset, clearance, width)
		Facing.SOUTH: return Rect2i(offset, size.y - clearance, width, clearance)
		_: return Rect2i(0, offset, clearance, width)


func descriptor() -> Dictionary:
	return {"connector_id": connector_id, "kind": kind, "facing": facing,
		"offset": offset, "width": width, "clearance": clearance}
