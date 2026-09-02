class_name DeliveryRuntimeState
extends RefCounted

const DefinitionContract = preload(
	"res://game/simulation/delivery/delivery_definition.gd"
)

var _runtime_id := 0
var _request_id := 0
var _definition_id := ""
var _kind := -1
var _source_entity_id := 0
var _source_team_id := 0
var _position := Vector2.ZERO
var _direction := Vector2.ZERO
var _radius := 0.0
var _speed_per_second := 0.0
var _expiry_tick := -1
var _max_targets := 0
var _pulse_interval_ticks := 0
var _next_pulse_tick := -1
var _hit_target_ids: Dictionary = {}
var _is_configured := false


func runtime_id() -> int:
	return _runtime_id


func request_id() -> int:
	return _request_id


func definition_id() -> String:
	return _definition_id


func kind() -> int:
	return _kind


func source_entity_id() -> int:
	return _source_entity_id


func source_team_id() -> int:
	return _source_team_id


func position() -> Vector2:
	return _position


func direction() -> Vector2:
	return _direction


func radius() -> float:
	return _radius


func speed_per_second() -> float:
	return _speed_per_second


func expiry_tick() -> int:
	return _expiry_tick


func max_targets() -> int:
	return _max_targets


func pulse_interval_ticks() -> int:
	return _pulse_interval_ticks


func next_pulse_tick() -> int:
	return _next_pulse_tick


func hit_count() -> int:
	return _hit_target_ids.size()


func has_hit_target(target_id: int) -> bool:
	return _hit_target_ids.has(target_id)


func canonical_values() -> Array:
	if not _is_configured:
		return []
	var hit_ids: Array = _hit_target_ids.keys()
	hit_ids.sort()
	return [
		_runtime_id,
		_request_id,
		_definition_id,
		_kind,
		_source_entity_id,
		_source_team_id,
		_position.x,
		_position.y,
		_direction.x,
		_direction.y,
		_radius,
		_speed_per_second,
		_expiry_tick,
		_max_targets,
		_pulse_interval_ticks,
		_next_pulse_tick,
		hit_ids,
	]


func _configure(runtime_id_value: int, request: RefCounted, spawn_tick: int) -> void:
	if _is_configured:
		return
	var definition: Resource = request.definition()
	_runtime_id = runtime_id_value
	_request_id = request.request_id()
	_definition_id = definition.definition_id()
	_kind = definition.kind()
	_source_entity_id = request.source_entity_id()
	_source_team_id = request.source_team_id()
	_position = request.origin()
	_direction = request.direction()
	_radius = definition.radius()
	_speed_per_second = definition.speed_per_second()
	_expiry_tick = spawn_tick + definition.lifetime_ticks()
	_max_targets = definition.max_targets()
	_pulse_interval_ticks = definition.pulse_interval_ticks()
	_next_pulse_tick = spawn_tick
	_hit_target_ids = {}
	_is_configured = true


func _move_projectile(fixed_delta: float) -> Vector2:
	var start := _position
	_position += _direction * _speed_per_second * fixed_delta
	return start


func _record_hit(target_id: int) -> void:
	_hit_target_ids[target_id] = true


func _advance_pulse() -> void:
	_next_pulse_tick += _pulse_interval_ticks


func _duplicate_state() -> RefCounted:
	var result: RefCounted = get_script().new()
	result._runtime_id = _runtime_id
	result._request_id = _request_id
	result._definition_id = _definition_id
	result._kind = _kind
	result._source_entity_id = _source_entity_id
	result._source_team_id = _source_team_id
	result._position = _position
	result._direction = _direction
	result._radius = _radius
	result._speed_per_second = _speed_per_second
	result._expiry_tick = _expiry_tick
	result._max_targets = _max_targets
	result._pulse_interval_ticks = _pulse_interval_ticks
	result._next_pulse_tick = _next_pulse_tick
	result._hit_target_ids = _hit_target_ids.duplicate()
	result._is_configured = _is_configured
	return result
