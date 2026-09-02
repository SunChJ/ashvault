class_name CastInterruption
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

var _actor_id := 0
var _reason_id := ""
var _is_configured := false


func configure(actor_id_value: int, reason_id_value: String) -> String:
	if _is_configured:
		return "Cast interruption is immutable after configuration."
	if actor_id_value <= 0:
		return "Cast interruption actor ID must be positive."
	var reason_error := StableIdContract.validation_error(reason_id_value)
	if not reason_error.is_empty():
		return reason_error
	_actor_id = actor_id_value
	_reason_id = reason_id_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func actor_id() -> int:
	return _actor_id


func reason_id() -> String:
	return _reason_id
