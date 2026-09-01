class_name AbilityEffectOutput
extends RefCounted

var _effect_id := ""
var _kind := -1
var _damage_result: RefCounted = null
var _command: RefCounted = null
var _event_request: RefCounted = null
var _is_configured := false


func effect_id() -> String:
	return _effect_id


func kind() -> int:
	return _kind


func damage_result() -> RefCounted:
	return _damage_result


func command() -> RefCounted:
	return _command


func event_request() -> RefCounted:
	return _event_request


func _configure(
	effect_id: String,
	kind: int,
	damage_result: RefCounted,
	command: RefCounted,
	event_request: RefCounted
) -> void:
	if _is_configured:
		return
	_effect_id = effect_id
	_kind = kind
	_damage_result = damage_result
	_command = command
	_event_request = event_request
	_is_configured = true
