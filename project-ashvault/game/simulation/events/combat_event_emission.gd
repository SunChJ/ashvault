class_name CombatEventEmission
extends RefCounted

const RequestContract = preload("res://game/simulation/events/combat_event_request.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")

var _trigger_id := ""
var _priority := 0
var _sequence := -1
var _allow_self_reentry := false
var _request: RefCounted = null
var _is_configured := false


func configure(
	trigger_id: String,
	priority: int,
	sequence: int,
	allow_self_reentry: bool,
	request: Variant
) -> String:
	if _is_configured:
		return "Combat event emission from '%s' is already configured and immutable." % _trigger_id
	var trigger_error := StableIdContract.validation_error(trigger_id)
	if not trigger_error.is_empty():
		return trigger_error
	if sequence < 0:
		return "Combat event emission sequence must be non-negative."
	if not request is RequestContract or not request.is_configured():
		return "Combat event emission requires a configured request."

	_trigger_id = trigger_id
	_priority = priority
	_sequence = sequence
	_allow_self_reentry = allow_self_reentry
	_request = request
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func trigger_id() -> String:
	return _trigger_id


func priority() -> int:
	return _priority


func sequence() -> int:
	return _sequence


func allows_self_reentry() -> bool:
	return _allow_self_reentry


func request() -> RefCounted:
	return _request


func identity_key() -> String:
	return "%s|%d" % [_trigger_id, _sequence]
