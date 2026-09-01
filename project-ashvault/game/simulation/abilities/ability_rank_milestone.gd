class_name AbilityRankMilestone
extends Resource

const TransformContract = preload(
	"res://game/simulation/abilities/ability_effect_transform.gd"
)

var _minimum_rank := 0
var _transforms: Array = []
var _is_configured := false


func configure(minimum_rank: int, transforms: Array) -> String:
	if _is_configured:
		return "Ability rank milestone %d is already configured and immutable." % _minimum_rank
	if minimum_rank < 2:
		return "Ability rank milestones must begin at rank 2 or later."
	if transforms.is_empty():
		return "Ability rank milestone %d requires at least one transform." % minimum_rank
	var observed: Dictionary = {}
	for index in transforms.size():
		var transform: Variant = transforms[index]
		if not transform is TransformContract or not transform.is_configured():
			return "Ability transform at index %d is not configured." % index
		if observed.has(transform.target_effect_id()):
			return "Ability rank %d repeats transform target '%s'." % [
				minimum_rank,
				transform.target_effect_id(),
			]
		observed[transform.target_effect_id()] = true

	_minimum_rank = minimum_rank
	_transforms = transforms.duplicate()
	_transforms.sort_custom(_transform_precedes)
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func minimum_rank() -> int:
	return _minimum_rank


func transforms() -> Array:
	return _transforms.duplicate()


static func _transform_precedes(left: Resource, right: Resource) -> bool:
	if left.target_effect_id() != right.target_effect_id():
		return left.target_effect_id() < right.target_effect_id()
	return left.source_id() < right.source_id()
