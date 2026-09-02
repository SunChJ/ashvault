class_name AbilityCastBinding
extends RefCounted

const AbilityContract = preload(
	"res://game/simulation/abilities/ability_definition.gd"
)
const StableIdContract = preload("res://game/content/stable_id.gd")

enum MovementPolicy {
	ALLOW,
	LOCK,
	CANCEL_CAST,
}

var _ability_slot := -1
var _ability: Resource = null
var _movement_policy := -1
var _manual_cancel_allowed := false
var _interrupt_reasons := PackedStringArray()
var _cancels_active_cast := false
var _is_configured := false


func configure(
	ability_slot_value: int,
	ability_value: Variant,
	movement_policy_value: int,
	manual_cancel_allowed_value: bool,
	interrupt_reasons_value: PackedStringArray,
	cancels_active_cast_value: bool
) -> String:
	if _is_configured:
		return "Ability cast binding is immutable after configuration."
	if ability_slot_value < 0:
		return "Ability cast binding slot must be non-negative."
	if not ability_value is AbilityContract or not ability_value.is_configured():
		return "Ability cast binding requires a configured AbilityDefinition."
	if movement_policy_value < MovementPolicy.ALLOW or movement_policy_value > MovementPolicy.CANCEL_CAST:
		return "Unknown cast movement policy '%s'." % movement_policy_value
	var observed_reasons: Dictionary = {}
	for reason_id: String in interrupt_reasons_value:
		var reason_error := StableIdContract.validation_error(reason_id)
		if not reason_error.is_empty():
			return reason_error
		if observed_reasons.has(reason_id):
			return "Duplicate cast interruption reason '%s'." % reason_id
		observed_reasons[reason_id] = true

	_ability_slot = ability_slot_value
	_ability = ability_value
	_ability.freeze()
	_movement_policy = movement_policy_value
	_manual_cancel_allowed = manual_cancel_allowed_value
	_interrupt_reasons = interrupt_reasons_value.duplicate()
	_interrupt_reasons.sort()
	_cancels_active_cast = cancels_active_cast_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func ability_slot() -> int:
	return _ability_slot


func ability() -> Resource:
	return _ability


func movement_policy() -> int:
	return _movement_policy


func manual_cancel_allowed() -> bool:
	return _manual_cancel_allowed


func interrupt_reasons() -> PackedStringArray:
	return _interrupt_reasons.duplicate()


func allows_interruption(reason_id: String) -> bool:
	return _interrupt_reasons.has(reason_id)


func cancels_active_cast() -> bool:
	return _cancels_active_cast


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		_ability_slot,
		_ability.content_id,
		_ability.cost_resource_id(),
		_ability.cost_amount(),
		_ability.cooldown_ticks(),
		_ability.cast_time_ticks(),
		_ability.recovery_ticks(),
		_movement_policy,
		_manual_cancel_allowed,
		Array(_interrupt_reasons),
		_cancels_active_cast,
	]
