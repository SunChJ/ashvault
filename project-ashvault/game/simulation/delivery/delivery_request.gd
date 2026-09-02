class_name DeliveryRequest
extends RefCounted

const DefinitionContract = preload(
	"res://game/simulation/delivery/delivery_definition.gd"
)

var _request_id := 0
var _definition: Resource = null
var _source_entity_id := 0
var _source_team_id := 0
var _origin := Vector2.ZERO
var _direction := Vector2.ZERO
var _primary_target_id := 0
var _is_configured := false


func configure(
	request_id_value: int,
	definition_value: Variant,
	source_entity_id_value: int,
	source_team_id_value: int,
	origin_value: Vector2,
	direction_value: Vector2 = Vector2.ZERO,
	primary_target_id_value: int = 0
) -> String:
	if _is_configured:
		return "Delivery request %d is immutable." % _request_id
	if request_id_value <= 0:
		return "Delivery request ID must be positive."
	if not definition_value is DefinitionContract or not definition_value.is_configured():
		return "Delivery request requires a configured DeliveryDefinition."
	if source_entity_id_value <= 0 or source_team_id_value < 0:
		return "Delivery source entity must be positive and team must be non-negative."
	if not origin_value.is_finite() or not direction_value.is_finite():
		return "Delivery origin and direction must be finite."
	if primary_target_id_value < 0:
		return "Delivery primary target ID must be non-negative."
	if (
		definition_value.kind() == DefinitionContract.Kind.PROJECTILE
		and direction_value.is_zero_approx()
	):
		return "Projectile requests require a non-zero direction."

	_request_id = request_id_value
	_definition = definition_value
	_source_entity_id = source_entity_id_value
	_source_team_id = source_team_id_value
	_origin = origin_value
	_direction = direction_value.normalized() if not direction_value.is_zero_approx() else Vector2.ZERO
	_primary_target_id = primary_target_id_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func request_id() -> int:
	return _request_id


func definition() -> Resource:
	return _definition


func source_entity_id() -> int:
	return _source_entity_id


func source_team_id() -> int:
	return _source_team_id


func origin() -> Vector2:
	return _origin


func direction() -> Vector2:
	return _direction


func primary_target_id() -> int:
	return _primary_target_id


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		_request_id,
		_definition.canonical_values(),
		_source_entity_id,
		_source_team_id,
		_origin.x,
		_origin.y,
		_direction.x,
		_direction.y,
		_primary_target_id,
	]
