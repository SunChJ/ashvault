class_name ProgressionCatalog
extends RefCounted

const Definition = preload("res://game/simulation/progression/progression_definition.gd")
const Passive = preload("res://game/simulation/progression/passive_definition.gd")
const Template = preload("res://game/simulation/stats/stat_modifier_template.gd")
const Ability = preload("res://game/simulation/abilities/ability_definition.gd")
const Id = preload("res://game/content/stable_id.gd")
const MAX_VALUE := 2147483647

var _definition: Resource
var _skills: Dictionary = {}
var _passives: Dictionary = {}


func load_definitions(definition: Variant, skills: Array, passives: Array) -> String:
	if _definition != null or not definition is Definition:
		return "Progression requires an unused catalog and ProgressionDefinition."
	var thresholds: Array = definition.xp_thresholds
	if thresholds.is_empty() or thresholds.size() > 100 or thresholds[0] != 0 or definition.points_per_level < 1 or definition.points_per_level > 100 or definition.max_skill_rank < 1 or definition.max_skill_rank > 20:
		return "Invalid XP curve, points per level, or skill rank cap."
	var previous := -1
	for xp: int in thresholds:
		if xp <= previous or xp > MAX_VALUE:
			return "XP thresholds must start at zero and strictly increase within int32."
		previous = xp
	var staged_skills: Dictionary = {}
	for skill: Variant in skills:
		if not skill is Ability or not skill.is_configured() or staged_skills.has(skill.content_id):
			return "Skills require distinct configured AbilityDefinition Resources."
		staged_skills[skill.content_id] = skill
	var staged_passives: Dictionary = {}
	for passive: Variant in passives:
		if not passive is Passive or not Id.is_valid(passive.content_id) or not passive.content_id.begins_with("passive.") or staged_passives.has(passive.content_id):
			return "Passives require distinct stable passive IDs."
		if passive.minimum_level < 1 or passive.minimum_level > thresholds.size() or passive.max_rank < 1 or passive.max_rank > 20 or passive.modifiers.is_empty():
			return "Passive level, rank cap, or modifiers are invalid."
		var error: String = Template.list_error(passive.modifiers)
		if not error.is_empty():
			return error
		for modifier: Resource in passive.modifiers:
			if not modifier.modifier("progression.validation", passive.max_rank).error.is_empty():
				return "Passive modifier exceeds valid bounds at maximum rank."
		staged_passives[passive.content_id] = passive
	for passive: Resource in staged_passives.values():
		for id: Variant in passive.prerequisites:
			var rank: Variant = passive.prerequisites[id]
			if not id is String or not staged_passives.has(id) or not integer(rank, 1) or rank > staged_passives[id].max_rank:
				return "Passive prerequisite references an unknown passive or invalid rank."
	var remaining: Dictionary = staged_passives.duplicate()
	while not remaining.is_empty():
		var removed := false
		for id: String in remaining.keys():
			var ready := true
			for dependency: String in remaining[id].prerequisites:
				if remaining.has(dependency):
					ready = false
			if ready:
				remaining.erase(id)
				removed = true
		if not removed:
			return "Passive prerequisites contain a cycle."
	definition.freeze()
	for value: Resource in staged_skills.values() + staged_passives.values():
		value.freeze()
	_definition = definition
	_skills = staged_skills
	_passives = staged_passives
	return ""


func is_loaded() -> bool:
	return _definition != null


func definition() -> Resource:
	return _definition


func skill(id: String) -> Resource:
	return _skills.get(id)


func passive(id: String) -> Resource:
	return _passives.get(id)


func level(experience: int) -> int:
	var result := 1
	for threshold: int in _definition.xp_thresholds.slice(1):
		if experience < threshold:
			break
		result += 1
	return result


static func integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= MAX_VALUE and floor(value) == value
