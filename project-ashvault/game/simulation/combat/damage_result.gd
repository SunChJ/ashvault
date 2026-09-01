class_name DamageResult
extends RefCounted

var _source_entity_id := 0
var _target_entity_id := 0
var _ability_id := ""
var _origin_event_id := 0
var _is_critical := false
var _total_damage := 0.0
var _mitigated_amount := 0.0
var _component_breakdown: Array = []
var _mitigation_breakdown: Array = []
var _source_breakdown: Array = []
var _contributing_source_ids := PackedStringArray()
var _is_configured := false


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func ability_id() -> String:
	return _ability_id


func origin_event_id() -> int:
	return _origin_event_id


func is_critical() -> bool:
	return _is_critical


func total_damage() -> float:
	return _total_damage


func committed_amount() -> int:
	return maxi(0, roundi(_total_damage))


func mitigated_amount() -> float:
	return _mitigated_amount


func component_breakdown() -> Array:
	return _component_breakdown.duplicate(true)


func mitigation_breakdown() -> Array:
	return _mitigation_breakdown.duplicate(true)


func source_breakdown() -> Array:
	return _source_breakdown.duplicate(true)


func contributing_source_ids() -> PackedStringArray:
	return _contributing_source_ids.duplicate()


func is_configured() -> bool:
	return _is_configured


func _configure(
	context: RefCounted,
	is_critical_value: bool,
	total_damage_value: float,
	mitigated_amount_value: float,
	component_breakdown_value: Array,
	mitigation_breakdown_value: Array,
	source_breakdown_value: Array,
	contributing_source_ids_value: PackedStringArray
) -> String:
	if _is_configured:
		return "Damage result is immutable after publication."
	_source_entity_id = context.source_entity_id()
	_target_entity_id = context.target_entity_id()
	_ability_id = context.ability_id()
	_origin_event_id = context.origin_event_id()
	_is_critical = is_critical_value
	_total_damage = total_damage_value
	_mitigated_amount = mitigated_amount_value
	_component_breakdown = component_breakdown_value.duplicate(true)
	_mitigation_breakdown = mitigation_breakdown_value.duplicate(true)
	_source_breakdown = source_breakdown_value.duplicate(true)
	_contributing_source_ids = contributing_source_ids_value.duplicate()
	_is_configured = true
	return ""
