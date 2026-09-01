class_name AbilityExecutionContext
extends RefCounted

const DamageModifierContract = preload(
	"res://game/simulation/combat/damage_modifier.gd"
)
const StableIdContract = preload("res://game/content/stable_id.gd")
const StatSnapshotContract = preload(
	"res://game/simulation/stats/stat_snapshot.gd"
)

var _rank := 0
var _tick := -1
var _source_entity_id := 0
var _target_entity_id := 0
var _origin_event_id := 0
var _stat_snapshot: RefCounted = null
var _critical_roll := 0.0
var _active_conditions := PackedStringArray()
var _damage_modifiers: Array = []
var _target_position := Vector2.ZERO
var _direction := Vector2.ZERO
var _is_configured := false


func configure(
	rank: int,
	tick: int,
	source_entity_id: int,
	target_entity_id: int,
	origin_event_id: int,
	stat_snapshot: Variant,
	critical_roll: float,
	active_conditions: PackedStringArray,
	damage_modifiers: Array,
	target_position: Vector2,
	direction: Vector2
) -> String:
	if _is_configured:
		return "Ability execution context is already configured and immutable."
	if rank < 1 or tick < 0:
		return "Ability rank must be positive and execution tick non-negative."
	if source_entity_id <= 0 or target_entity_id < 0 or origin_event_id <= 0:
		return "Ability execution entity/event IDs are outside their valid range."
	if not stat_snapshot is StatSnapshotContract:
		return "Ability execution requires an immutable StatSnapshot."
	if stat_snapshot.tick() != tick:
		return "Ability execution tick must match the StatSnapshot tick."
	if not is_finite(critical_roll) or critical_roll < 0.0 or critical_roll > 1.0:
		return "Ability critical roll must be finite and between 0 and 1."
	if not target_position.is_finite() or not direction.is_finite():
		return "Ability target vectors must be finite."
	var condition_error := _validate_conditions(active_conditions)
	if not condition_error.is_empty():
		return condition_error
	var observed_modifiers: Dictionary = {}
	for index in damage_modifiers.size():
		var modifier: Variant = damage_modifiers[index]
		if not modifier is DamageModifierContract or not modifier.is_configured():
			return "Runtime damage modifier at index %d is not configured." % index
		if observed_modifiers.has(modifier.identity_key()):
			return "Duplicate runtime damage modifier '%s'." % modifier.identity_key()
		observed_modifiers[modifier.identity_key()] = true

	_rank = rank
	_tick = tick
	_source_entity_id = source_entity_id
	_target_entity_id = target_entity_id
	_origin_event_id = origin_event_id
	_stat_snapshot = stat_snapshot
	_critical_roll = critical_roll
	_active_conditions = active_conditions.duplicate()
	_active_conditions.sort()
	_damage_modifiers = damage_modifiers.duplicate()
	_target_position = target_position
	_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.ZERO
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func rank() -> int:
	return _rank


func tick() -> int:
	return _tick


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func origin_event_id() -> int:
	return _origin_event_id


func stat_snapshot() -> RefCounted:
	return _stat_snapshot


func critical_roll() -> float:
	return _critical_roll


func active_conditions() -> PackedStringArray:
	return _active_conditions.duplicate()


func damage_modifiers() -> Array:
	return _damage_modifiers.duplicate()


func target_position() -> Vector2:
	return _target_position


func direction() -> Vector2:
	return _direction


static func _validate_conditions(conditions: PackedStringArray) -> String:
	var observed: Dictionary = {}
	for condition_id in conditions:
		var condition_error := StableIdContract.validation_error(condition_id)
		if not condition_error.is_empty():
			return condition_error
		if observed.has(condition_id):
			return "Duplicate active ability condition '%s'." % condition_id
		observed[condition_id] = true
	return ""
