class_name AbilityEffectTransform
extends Resource

const EffectContract = preload(
	"res://game/simulation/abilities/ability_effect_definition.gd"
)
const StableIdContract = preload("res://game/content/stable_id.gd")

var _source_id := ""
var _target_effect_id := ""
var _replacement: Resource = null
var _is_configured := false


func configure(
	source_id: String,
	target_effect_id: String,
	replacement: Variant
) -> String:
	if _is_configured:
		return "Ability effect transform '%s' is already configured and immutable." % _source_id
	for id_value in [source_id, target_effect_id]:
		var id_error := StableIdContract.validation_error(id_value)
		if not id_error.is_empty():
			return id_error
	if not replacement is EffectContract or not replacement.is_configured():
		return "Ability effect transform requires a configured replacement effect."
	if replacement.effect_id() != target_effect_id:
		return "Replacement effect ID must match transform target '%s'." % target_effect_id

	_source_id = source_id
	_target_effect_id = target_effect_id
	_replacement = replacement
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func source_id() -> String:
	return _source_id


func target_effect_id() -> String:
	return _target_effect_id


func replacement() -> Resource:
	return _replacement
