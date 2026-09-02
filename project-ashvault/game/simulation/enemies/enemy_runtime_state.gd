class_name EnemyRuntimeState
extends RefCounted

const CANONICAL_SCHEMA_VERSION := 1

var _actor_id := 0
var _target_id := 0
var _next_attack_tick := 0
var _is_configured := false


func configure(actor_id_value: int, target_id_value: int = 0, next_attack_tick_value: int = 0) -> String:
	if _is_configured:
		return "Enemy runtime state is immutable after configuration."
	if actor_id_value <= 0:
		return "Enemy runtime actor ID must be positive."
	if target_id_value < 0:
		return "Enemy runtime target ID must be zero or positive."
	if next_attack_tick_value < 0:
		return "Enemy next attack tick must be non-negative."
	_actor_id = actor_id_value
	_target_id = target_id_value
	_next_attack_tick = next_attack_tick_value
	_is_configured = true
	return ""


func actor_id() -> int:
	return _actor_id


func target_id() -> int:
	return _target_id


func next_attack_tick() -> int:
	return _next_attack_tick


func _set_target_id(value: int) -> void:
	_target_id = value


func _set_next_attack_tick(value: int) -> void:
	_next_attack_tick = value


func _duplicate_state() -> RefCounted:
	var result: RefCounted = get_script().new()
	var error: String = result.configure(_actor_id, _target_id, _next_attack_tick)
	assert(error.is_empty(), "Configured enemy runtime states must be duplicable.")
	return result


func canonical_values() -> Array:
	return [CANONICAL_SCHEMA_VERSION, _actor_id, _target_id, _next_attack_tick]
