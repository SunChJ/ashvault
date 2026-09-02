class_name MovementEnvironment
extends RefCounted

const CONFIG_SCHEMA_VERSION := 1

var _bounds := Rect2()
var _obstacles: Array[Rect2] = []
var _actor_radius := 0.0
var _speed_per_second := 0.0
var _is_configured := false


func configure(
	bounds_value: Rect2,
	obstacles_value: Array,
	actor_radius_value: float,
	speed_per_second_value: float
) -> String:
	if _is_configured:
		return "Movement environment is immutable after configuration."
	if not _rect_is_finite(bounds_value) or bounds_value.size.x <= 0.0 or bounds_value.size.y <= 0.0:
		return "Movement bounds must be a finite rectangle with positive size."
	if not is_finite(actor_radius_value) or actor_radius_value < 0.0:
		return "Movement actor radius must be finite and non-negative."
	if (
		actor_radius_value * 2.0 >= bounds_value.size.x
		or actor_radius_value * 2.0 >= bounds_value.size.y
	):
		return "Movement actor radius must leave usable arena bounds."
	if not is_finite(speed_per_second_value) or speed_per_second_value <= 0.0:
		return "Movement speed must be finite and positive."

	var staged_obstacles: Array[Rect2] = []
	for value: Variant in obstacles_value:
		if not value is Rect2:
			return "Movement obstacles must contain only Rect2 values."
		var obstacle: Rect2 = value
		if not _rect_is_finite(obstacle) or obstacle.size.x <= 0.0 or obstacle.size.y <= 0.0:
			return "Movement obstacles must be finite rectangles with positive size."
		if not _contains_rect(bounds_value, obstacle):
			return "Movement obstacles must remain inside arena bounds."
		staged_obstacles.append(obstacle)
	staged_obstacles.sort_custom(_rect_precedes)

	_bounds = bounds_value
	_obstacles = staged_obstacles
	_actor_radius = actor_radius_value
	_speed_per_second = speed_per_second_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func bounds() -> Rect2:
	return _bounds


func obstacles() -> Array[Rect2]:
	return _obstacles.duplicate()


func actor_radius() -> float:
	return _actor_radius


func speed_per_second() -> float:
	return _speed_per_second


func placement_error(position: Vector2) -> String:
	return placement_error_for(position, _actor_radius)


func placement_error_for(position: Vector2, actor_radius_value: float) -> String:
	if not _is_configured:
		return "Movement environment is not configured."
	if not position.is_finite():
		return "Entity placement must be finite."
	var radius_error := _actor_radius_error(actor_radius_value)
	if not radius_error.is_empty():
		return radius_error
	var effective_bounds := _effective_bounds(actor_radius_value)
	if (
		position.x < effective_bounds.position.x
		or position.x > effective_bounds.end.x
		or position.y < effective_bounds.position.y
		or position.y > effective_bounds.end.y
	):
		return "Entity placement must remain inside movement bounds."
	for obstacle: Rect2 in _obstacles:
		if _point_is_inside(position, _expanded_obstacle(obstacle, actor_radius_value)):
			return "Entity placement overlaps a movement obstacle."
	return ""


func resolve_position(position: Vector2, movement_input: Vector2, fixed_delta: float) -> Dictionary:
	return resolve_position_for(
		position,
		movement_input,
		fixed_delta,
		_actor_radius,
		_speed_per_second
	)


func resolve_position_for(
	position: Vector2,
	movement_input: Vector2,
	fixed_delta: float,
	actor_radius_value: float,
	speed_per_second_value: float
) -> Dictionary:
	var start_error := placement_error_for(position, actor_radius_value)
	if not start_error.is_empty():
		return {"position": position, "error": start_error}
	if not movement_input.is_finite() or movement_input.length_squared() > 1.000001:
		return {"position": position, "error": "Movement input must be finite with length at most one."}
	if not is_finite(fixed_delta) or fixed_delta <= 0.0:
		return {"position": position, "error": "Movement fixed delta must be finite and positive."}
	if not is_finite(speed_per_second_value) or speed_per_second_value < 0.0:
		return {"position": position, "error": "Movement speed must be finite and non-negative."}

	var displacement := movement_input * speed_per_second_value * fixed_delta
	var effective_bounds := _effective_bounds(actor_radius_value)
	var resolved := position
	resolved.x = clampf(
		resolved.x + displacement.x,
		effective_bounds.position.x,
		effective_bounds.end.x
	)
	for obstacle: Rect2 in _obstacles:
		resolved.x = _sweep_x(
			position,
			resolved.x,
			displacement.x,
			_expanded_obstacle(obstacle, actor_radius_value)
		)

	var position_after_x := Vector2(resolved.x, position.y)
	resolved.y = clampf(
		resolved.y + displacement.y,
		effective_bounds.position.y,
		effective_bounds.end.y
	)
	for obstacle: Rect2 in _obstacles:
		resolved.y = _sweep_y(
			position_after_x,
			resolved.y,
			displacement.y,
			_expanded_obstacle(obstacle, actor_radius_value)
		)

	var resolved_error := placement_error_for(resolved, actor_radius_value)
	if not resolved_error.is_empty():
		return {"position": position, "error": resolved_error}
	return {"position": resolved, "error": ""}


func canonical_values() -> Array:
	if not _is_configured:
		return []
	var obstacle_values: Array = []
	for obstacle: Rect2 in _obstacles:
		obstacle_values.append([
			obstacle.position.x,
			obstacle.position.y,
			obstacle.size.x,
			obstacle.size.y,
		])
	return [
		CONFIG_SCHEMA_VERSION,
		_bounds.position.x,
		_bounds.position.y,
		_bounds.size.x,
		_bounds.size.y,
		_actor_radius,
		_speed_per_second,
		obstacle_values,
	]


func _duplicate_value() -> RefCounted:
	var result: RefCounted = get_script().new()
	var error: String = result.configure(_bounds, _obstacles, _actor_radius, _speed_per_second)
	assert(error.is_empty(), "Configured movement environments must be duplicable.")
	return result


func _effective_bounds(actor_radius_value: float) -> Rect2:
	var radius_offset := Vector2(actor_radius_value, actor_radius_value)
	return Rect2(_bounds.position + radius_offset, _bounds.size - radius_offset * 2.0)


func _expanded_obstacle(obstacle: Rect2, actor_radius_value: float) -> Rect2:
	var radius_offset := Vector2(actor_radius_value, actor_radius_value)
	return Rect2(obstacle.position - radius_offset, obstacle.size + radius_offset * 2.0)


func _actor_radius_error(actor_radius_value: float) -> String:
	if not is_finite(actor_radius_value) or actor_radius_value < 0.0:
		return "Movement actor radius must be finite and non-negative."
	if (
		actor_radius_value * 2.0 >= _bounds.size.x
		or actor_radius_value * 2.0 >= _bounds.size.y
	):
		return "Movement actor radius must leave usable arena bounds."
	return ""


static func _sweep_x(
	start: Vector2,
	target_x: float,
	displacement_x: float,
	obstacle: Rect2
) -> float:
	if start.y <= obstacle.position.y or start.y >= obstacle.end.y:
		return target_x
	if displacement_x > 0.0 and start.x <= obstacle.position.x and target_x > obstacle.position.x:
		return minf(target_x, obstacle.position.x)
	if displacement_x < 0.0 and start.x >= obstacle.end.x and target_x < obstacle.end.x:
		return maxf(target_x, obstacle.end.x)
	return target_x


static func _sweep_y(
	start: Vector2,
	target_y: float,
	displacement_y: float,
	obstacle: Rect2
) -> float:
	if start.x <= obstacle.position.x or start.x >= obstacle.end.x:
		return target_y
	if displacement_y > 0.0 and start.y <= obstacle.position.y and target_y > obstacle.position.y:
		return minf(target_y, obstacle.position.y)
	if displacement_y < 0.0 and start.y >= obstacle.end.y and target_y < obstacle.end.y:
		return maxf(target_y, obstacle.end.y)
	return target_y


static func _point_is_inside(point: Vector2, rect: Rect2) -> bool:
	return (
		point.x > rect.position.x
		and point.x < rect.end.x
		and point.y > rect.position.y
		and point.y < rect.end.y
	)


static func _rect_is_finite(value: Rect2) -> bool:
	return value.position.is_finite() and value.size.is_finite()


static func _contains_rect(container: Rect2, value: Rect2) -> bool:
	return (
		value.position.x >= container.position.x
		and value.position.y >= container.position.y
		and value.end.x <= container.end.x
		and value.end.y <= container.end.y
	)


static func _rect_precedes(left: Rect2, right: Rect2) -> bool:
	var left_values := [left.position.x, left.position.y, left.size.x, left.size.y]
	var right_values := [right.position.x, right.position.y, right.size.x, right.size.y]
	for index: int in range(left_values.size()):
		if left_values[index] != right_values[index]:
			return left_values[index] < right_values[index]
	return false
