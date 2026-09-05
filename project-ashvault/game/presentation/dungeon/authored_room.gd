class_name AuthoredRoom
extends Node2D

const Room = preload("res://game/simulation/dungeon/room_definition.gd")
const Connector = preload("res://game/simulation/dungeon/room_connector.gd")

@export var definition: Resource


func validation_error() -> String:
	if not definition is Room:
		return "Authored room scene requires a RoomDefinition."
	if not position.is_finite() or not is_zero_approx(rotation) or not is_zero_approx(skew) or not scale.is_equal_approx(Vector2.ONE):
		return "Authored rooms support finite translation only, without rotation, scale, or skew."
	return definition.validation_error()


func connector_position(id: String) -> Vector2:
	if not validation_error().is_empty():
		return Vector2.INF
	var connector: Resource = definition.connector(id)
	if connector == null:
		return Vector2.INF
	var tangent := Vector2.RIGHT if connector.facing in [Connector.Facing.NORTH, Connector.Facing.SOUTH] else Vector2.DOWN
	return (Vector2(connector.start(definition.bounds.size)) + tangent * float(connector.width) * 0.5) * Room.CELL_SIZE


func _draw() -> void:
	if not validation_error().is_empty():
		return
	var scale_value := float(Room.CELL_SIZE)
	draw_rect(Rect2(Vector2.ZERO, Vector2(definition.bounds.size) * scale_value), Color("202e3d"))
	for connector: Resource in definition.connectors:
		var area: Rect2i = connector.clearance_rect(definition.bounds.size)
		draw_rect(Rect2(Vector2(area.position) * scale_value, Vector2(area.size) * scale_value), Color("447f87"))
	for socket: Resource in definition.sockets:
		draw_rect(Rect2(Vector2(socket.area.position) * scale_value, Vector2(socket.area.size) * scale_value), Color("a67b40"), false, 2)
