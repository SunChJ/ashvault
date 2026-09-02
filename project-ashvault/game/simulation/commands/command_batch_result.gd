class_name CommandBatchResult
extends RefCounted

var _tick := -1
var _is_success := false
var _accepted_count := 0
var _diagnostics: Array = []
var _enemy_attack_intents: Array = []
var _combat_events: Array = []
var _is_configured := false


func tick() -> int:
	return _tick


func is_success() -> bool:
	return _is_success


func accepted_count() -> int:
	return _accepted_count


func diagnostics() -> Array:
	return _diagnostics.duplicate(true)


func enemy_attack_intents() -> Array:
	return _enemy_attack_intents.duplicate()


func combat_events() -> Array:
	return _combat_events.duplicate()


func _configure(
	tick_value: int,
	is_success_value: bool,
	accepted_count_value: int,
	diagnostics_value: Array,
	enemy_attack_intents_value: Array = [],
	combat_events_value: Array = []
) -> void:
	if _is_configured:
		return
	_tick = tick_value
	_is_success = is_success_value
	_accepted_count = accepted_count_value
	_diagnostics = diagnostics_value.duplicate(true)
	_enemy_attack_intents = enemy_attack_intents_value.duplicate()
	_combat_events = combat_events_value.duplicate()
	_is_configured = true
