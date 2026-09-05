class_name CharacterProgression
extends RefCounted

const Catalog = preload("res://game/simulation/progression/progression_catalog.gd")
const Registry = preload("res://game/simulation/stats/stat_registry.gd")
const Resolver = preload("res://game/simulation/stats/stat_resolver.gd")
const Id = preload("res://game/content/stable_id.gd")
const FIELDS := ["schema_version", "character_id", "experience", "skills", "passives", "reward_sequences", "revision"]

var _catalog: RefCounted
var _registry: RefCounted
var _base_modifiers: Array = []
var _state: Dictionary = {}
var _stats: RefCounted
var _modifiers: Array = []
var _used := false


func configure(character_id: String, catalog: Variant, registry: Variant, base_modifiers: Array = []) -> String:
	if _catalog != null or not _valid_id(character_id) or not catalog is Catalog or not catalog.is_loaded() or not registry is Registry or not registry.is_loaded():
		return "Progression requires an unused state, stable character ID, and published catalogs."
	var resolved: RefCounted = Resolver.resolve(registry, base_modifiers, PackedStringArray(), 0)
	if not resolved.is_success():
		return "\n".join(resolved.errors())
	_catalog = catalog
	_registry = registry
	_base_modifiers = base_modifiers.duplicate()
	_stats = resolved.snapshot()
	_state = {"schema_version": 1, "character_id": character_id, "experience": 0, "skills": {}, "passives": {}, "reward_sequences": {}, "revision": 0}
	return ""


func award_xp(run_id: String, sequence: Variant, amount: Variant) -> String:
	if _catalog == null or not _valid_id(run_id) or not Catalog.integer(sequence, 1) or not Catalog.integer(amount, 1):
		return "XP reward requires a run ID, positive sequence, and positive int32 amount."
	if sequence <= _state.reward_sequences.get(run_id, 0):
		return "XP reward sequence was already processed or arrived out of order."
	var staged: Dictionary = _state.duplicate(true)
	staged.experience = mini(staged.experience + int(amount), _catalog.definition().xp_thresholds.back())
	staged.reward_sequences[run_id] = int(sequence)
	return _commit(staged)


func allocate(kind: String, id: String, amount: Variant, expected_revision: int) -> String:
	if _catalog == null or expected_revision != _state.revision or kind not in ["skills", "passives"] or not Catalog.integer(amount, 1):
		return "Allocation requires current revision, known allocation kind, and positive rank count."
	var staged: Dictionary = _state.duplicate(true)
	staged[kind][id] = staged[kind].get(id, 0) + int(amount)
	return _commit(staged)


func respec(expected_revision: int) -> String:
	if _catalog == null or expected_revision != _state.revision:
		return "Respec requires the current revision."
	var staged: Dictionary = _state.duplicate(true)
	staged.skills.clear()
	staged.passives.clear()
	return _commit(staged)


func restore(value: Variant) -> String:
	if _catalog == null or _used:
		return "Restore requires configured, unused character state."
	if not value is Dictionary or value.size() != FIELDS.size() or not value.has_all(FIELDS):
		return "Progression snapshot has unexpected fields."
	if not value.character_id is String or value.character_id != _state.character_id or not Catalog.integer(value.schema_version, 1) or value.schema_version != 1 or not Catalog.integer(value.revision):
		return "Progression identity, schema, or revision is invalid."
	if not value.skills is Dictionary or not value.passives is Dictionary or not value.reward_sequences is Dictionary:
		return "Progression allocations and rewards have invalid shapes."
	var error := _validate(value)
	if not error.is_empty():
		return error
	var staged: Dictionary = value.duplicate(true)
	staged.schema_version = 1
	staged.experience = int(staged.experience)
	staged.revision = int(staged.revision)
	for kind: String in ["skills", "passives"]:
		for id: String in staged[kind]:
			staged[kind][id] = int(staged[kind][id])
	for run_id: String in staged.reward_sequences:
		staged.reward_sequences[run_id] = int(staged.reward_sequences[run_id])
	return _publish(staged)


func level() -> int:
	return _catalog.level(_state.experience) if _catalog != null else 0


func available_points() -> int:
	return (level() - 1) * _catalog.definition().points_per_level - _spent(_state) if _catalog != null else 0


func skill_rank(id: String) -> int:
	return 1 + int(_state.skills.get(id, 0)) if _catalog != null and _catalog.skill(id) != null else 0


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func stats() -> RefCounted:
	return _stats


func passive_modifiers() -> Array:
	return _modifiers.duplicate()


func _commit(staged: Dictionary) -> String:
	if _state.revision >= Catalog.MAX_VALUE:
		return "Progression revision is exhausted."
	staged.revision = _state.revision + 1
	var error := _validate(staged)
	return _publish(staged) if error.is_empty() else error


func _validate(staged: Dictionary) -> String:
	if not Catalog.integer(staged.experience) or staged.experience > _catalog.definition().xp_thresholds.back():
		return "Experience is outside the authored curve."
	var current_level: int = _catalog.level(int(staged.experience))
	var spent := 0
	for kind: String in ["skills", "passives"]:
		for id: Variant in staged[kind]:
			var rank: Variant = staged[kind][id]
			if not id is String or not Catalog.integer(rank, 1):
				return "Allocated IDs and ranks must be valid."
			if kind == "skills":
				if _catalog.skill(id) == null or rank >= _catalog.definition().max_skill_rank:
					return "Skill allocation references an unknown skill or exceeds its cap."
			else:
				var passive: Resource = _catalog.passive(id)
				if passive == null or rank > passive.max_rank or current_level < passive.minimum_level:
					return "Passive allocation violates ID, rank, or minimum level."
				for prerequisite: String in passive.prerequisites:
					var prerequisite_rank: Variant = staged.passives.get(prerequisite, 0)
					if not Catalog.integer(prerequisite_rank) or prerequisite_rank < passive.prerequisites[prerequisite]:
						return "Passive prerequisites are not satisfied."
			spent += int(rank)
	if spent > (current_level - 1) * _catalog.definition().points_per_level:
		return "Insufficient earned skill points."
	for id: Variant in staged.reward_sequences:
		if not id is String or not _valid_id(id) or not Catalog.integer(staged.reward_sequences[id], 1):
			return "XP rewards require valid run IDs and positive int32 sequence watermarks."
	return ""


func _publish(staged: Dictionary) -> String:
	var modifiers: Array = []
	var ids: Array = staged.passives.keys()
	ids.sort()
	for id: String in ids:
		for effect: Resource in _catalog.passive(id).modifiers:
			var built: Dictionary = effect.modifier("progression." + id + "." + effect.effect_id, staged.passives[id])
			if not built.error.is_empty():
				return built.error
			modifiers.append(built.modifier)
	var resolved: RefCounted = Resolver.resolve(_registry, _base_modifiers + modifiers, PackedStringArray(), int(staged.revision))
	if not resolved.is_success():
		return "\n".join(resolved.errors())
	_state = staged
	_stats = resolved.snapshot()
	_modifiers = modifiers
	_used = true
	return ""


static func _spent(state: Dictionary) -> int:
	var result := 0
	for kind: String in ["skills", "passives"]:
		for rank: int in state[kind].values():
			result += rank
	return result


static func _valid_id(value: String) -> bool:
	return value.length() <= 128 and Id.is_valid(value)
