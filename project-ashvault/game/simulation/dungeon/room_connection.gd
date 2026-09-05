class_name RoomConnection
extends RefCounted

const Room = preload("res://game/simulation/dungeon/room_definition.gd")
const MAX_ORIGIN := 1000000


static func align(a: Variant, connector_a: String, b: Variant, connector_b: String, origin_a: Vector2i = Vector2i.ZERO) -> Dictionary:
	var error := _pair_error(a, connector_a, b, connector_b)
	if not error.is_empty():
		return {"error": error}
	if not _origin_valid(origin_a):
		return {"error": "Room origin is outside the supported grid range."}
	var first: Resource = a.connector(connector_a)
	var second: Resource = b.connector(connector_b)
	var origin_b: Vector2i = origin_a + first.start(a.bounds.size) - second.start(b.bounds.size)
	error = validation_error(a, origin_a, connector_a, b, origin_b, connector_b)
	if not error.is_empty():
		return {"error": error}
	return {"error": "", "origin": origin_b}


static func validation_error(a: Variant, origin_a: Vector2i, connector_a: String, b: Variant, origin_b: Vector2i, connector_b: String) -> String:
	var error := _pair_error(a, connector_a, b, connector_b)
	if not error.is_empty():
		return error
	if not _origin_valid(origin_a) or not _origin_valid(origin_b):
		return "Room origin is outside the supported grid range."
	var bounds_a := Rect2i(origin_a, a.bounds.size)
	var bounds_b := Rect2i(origin_b, b.bounds.size)
	if bounds_a.intersects(bounds_b):
		return "Connected room interiors overlap."
	var first: Resource = a.connector(connector_a)
	var second: Resource = b.connector(connector_b)
	if origin_a + first.start(a.bounds.size) != origin_b + second.start(b.bounds.size):
		return "Connector boundary segments do not align."
	return ""


static func _pair_error(a: Variant, connector_a: String, b: Variant, connector_b: String) -> String:
	for room: Variant in [a, b]:
		if not room is Room or not room.is_frozen():
			return "Room connections require published RoomDefinition Resources."
		var error: String = room.validation_error()
		if not error.is_empty():
			return error
	var first: Resource = a.connector(connector_a)
	var second: Resource = b.connector(connector_b)
	if first == null or second == null:
		return "Room connection references an unknown connector."
	if first.kind != second.kind or first.width != second.width:
		return "Connector kinds and opening widths must match."
	if first.normal() != -second.normal():
		return "Connector normals must face opposite directions."
	return ""


static func _origin_valid(value: Vector2i) -> bool:
	return value.x >= -MAX_ORIGIN and value.x <= MAX_ORIGIN and value.y >= -MAX_ORIGIN and value.y <= MAX_ORIGIN
