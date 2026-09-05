class_name EncounterSocket
extends Resource

const Id = preload("res://game/content/stable_id.gd")
enum Kind { ENTRY, SPAWN, REWARD, BOSS, EXIT }
var _frozen := false
var _socket_id: String = ""
var _kind: int = Kind.SPAWN
var _area: Rect2i = Rect2i()

@export var socket_id: String:
	get:
		return _socket_id
	set(value):
		if not is_frozen():
			_socket_id = value

@export_enum("Entry", "Spawn", "Reward", "Boss", "Exit") var kind: int:
	get:
		return _kind
	set(value):
		if not is_frozen():
			_kind = value

@export var area: Rect2i:
	get:
		return _area
	set(value):
		if not is_frozen():
			_area = value


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	_frozen = true


func validation_error(bounds: Rect2i) -> String:
	if not Id.is_valid(socket_id) or not socket_id.begins_with("socket."):
		return "Encounter socket requires a stable socket ID."
	if kind < Kind.ENTRY or kind > Kind.EXIT:
		return "Encounter socket kind is invalid."
	if area.position.x < 0 or area.position.y < 0 or area.position.x > 1024 or area.position.y > 1024 or area.size.x < 1 or area.size.y < 1 or area.size.x > 1024 or area.size.y > 1024:
		return "Encounter socket area must be positive and bounded."
	if not bounds.encloses(area):
		return "Encounter socket must fit inside room bounds."
	return ""


func descriptor() -> Dictionary:
	return {"socket_id": socket_id, "kind": kind,
		"area": [area.position.x, area.position.y, area.size.x, area.size.y]}
