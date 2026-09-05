class_name EquipmentState
extends RefCounted

const World = preload("res://game/simulation/items/item_world.gd")
const Registry = preload("res://game/simulation/stats/stat_registry.gd")
const Resolver = preload("res://game/simulation/stats/stat_resolver.gd")
const SetBonus = preload("res://game/simulation/items/equipment_set_bonus.gd")
const StatModifierContract = preload("res://game/simulation/stats/stat_modifier.gd")
const SLOTS := ["slot.weapon", "slot.off_hand", "slot.head", "slot.body", "slot.hands", "slot.feet", "slot.neck", "slot.ring"]

var _world: RefCounted
var _registry: RefCounted
var _base_modifiers: Array = []
var _sets: Dictionary = {}
var _slots: Dictionary = {}
var _stats: RefCounted
var _special_effects: Array = []
var _sources: Dictionary = {}


func configure(world: Variant, registry: Variant, base_modifiers: Array = [], set_bonuses: Array = []) -> String:
	if _world != null:
		return "Equipment is already configured."
	if not world is World or world.item_catalog() == null or not registry is Registry or not registry.is_loaded():
		return "Equipment requires an item world and loaded stat registry."
	var staged_sets: Dictionary = {}
	for bonus: Variant in set_bonuses:
		if not bonus is SetBonus:
			return "Equipment set bonuses must be authored Resources."
		var error: String = bonus.validation_error()
		if not error.is_empty():
			return error
		if not staged_sets.has(bonus.set_id):
			staged_sets[bonus.set_id] = {}
		if staged_sets[bonus.set_id].has(bonus.pieces):
			return "Set bonus thresholds must be unique."
		staged_sets[bonus.set_id][bonus.pieces] = bonus
	for id: String in staged_sets:
		if staged_sets[id].size() != 3:
			return "Each set must define all 2/3/4-piece bonuses."
	var initial: RefCounted = Resolver.resolve(registry, base_modifiers, PackedStringArray(), 0)
	if not initial.is_success():
		return "\n".join(initial.errors())
	for bonus: Resource in set_bonuses:
		bonus.freeze()
	_world = world
	_registry = registry
	_base_modifiers = base_modifiers.duplicate()
	_sets = staged_sets
	_stats = initial.snapshot()
	for slot: String in SLOTS:
		_slots[slot] = ""
	return ""


func transact(changes: Dictionary, tick: int, active_conditions: PackedStringArray = PackedStringArray()) -> Dictionary:
	if _world == null or tick < _stats.tick():
		return _failure("Equipment requires configuration and non-decreasing stat ticks.")
	var staged: Dictionary = _slots.duplicate()
	for slot: Variant in changes:
		if not slot is String or not SLOTS.has(slot) or not changes[slot] is String:
			return _failure("Equipment changes require known slots and string UIDs (empty to unequip).")
		staged[slot] = changes[slot]
	var modifiers: Array = _base_modifiers.duplicate()
	var seen: Dictionary = {}
	var set_pieces: Dictionary = {}
	var special_effects: Array = []
	var sources: Dictionary = {}
	var two_handed := false
	for slot: String in SLOTS:
		var uid: String = staged[slot]
		if uid.is_empty():
			continue
		var item: RefCounted = _world.get_item(uid)
		if item == null or seen.has(uid):
			return _failure("Equipment requires known, distinct item UIDs.")
		seen[uid] = true
		var definition: Resource = _world.item_catalog().get_definition(item.definition_id())
		if definition.equipment_slot != slot:
			return _failure("Item is incompatible with the equipment slot.")
		two_handed = two_handed or definition.two_handed
		var record: Dictionary = item.snapshot()
		var source := "equipment." + uid.replace(":", ".i")
		for effect: Resource in definition.base_effects:
			var source_id: String = source + "." + effect.effect_id
			var quality_scale: float = 1.0 + float(record.quality) / 100.0 if effect.operation in [StatModifierContract.Operation.BASE, StatModifierContract.Operation.FLAT] else 1.0
			var built: Dictionary = effect.modifier(source_id, quality_scale)
			sources[source_id] = {"uid": uid, "definition_id": definition.content_id, "effect_id": effect.effect_id}
			if not built.error.is_empty():
				return _failure(built.error)
			modifiers.append(built.modifier)
		for roll: Dictionary in record.rolls:
			var affix: Resource = _world.item_catalog().affix_catalog().get_definition(roll.affix_id)
			var source_id: String = source + "." + affix.content_id
			var built: Dictionary = affix.modifier(roll.value, source_id)
			sources[source_id] = {"uid": uid, "definition_id": definition.content_id, "affix_id": affix.content_id}
			if not built.error.is_empty():
				return _failure(built.error)
			modifiers.append(built.modifier)
		var crafting: RefCounted = _world.item_catalog().crafting_catalog()
		var contributions: Array = []
		for index in record.sockets.size():
			if record.sockets[index].is_empty():
				continue
			var rune: Resource = crafting.rune(record.sockets[index])
			contributions.append({"id": "socket.p%d." % index + rune.content_id, "effects": rune.effects, "rune_id": rune.content_id})
		var word: Resource = crafting.active_word(record)
		if word != null:
			contributions.append({"id": word.content_id, "effects": word.effects, "runeword_id": word.content_id})
		for contribution: Dictionary in contributions:
			for effect: Resource in contribution.effects:
				var source_id: String = source + "." + contribution.id + "." + effect.effect_id
				var built: Dictionary = effect.modifier(source_id)
				if not built.error.is_empty():
					return _failure(built.error)
				var provenance: Dictionary = contribution.duplicate()
				provenance.erase("effects")
				provenance.uid = uid
				provenance.effect_id = effect.effect_id
				sources[source_id] = provenance
				modifiers.append(built.modifier)
		if not definition.set_id.is_empty():
			if not _sets.has(definition.set_id):
				return _failure("Equipped set has no registered bonuses.")
			if not set_pieces.has(definition.set_id):
				set_pieces[definition.set_id] = {}
			set_pieces[definition.set_id][definition.content_id] = true
		if not definition.interaction_id.is_empty() or not definition.rule_id.is_empty():
			special_effects.append({"uid": uid, "interaction_id": definition.interaction_id, "rule_id": definition.rule_id})
	if two_handed and not staged["slot.off_hand"].is_empty():
		return _failure("A two-handed weapon requires an empty off-hand slot.")
	var set_ids: Array = set_pieces.keys()
	set_ids.sort()
	for set_id: String in set_ids:
		for threshold: int in [2, 3, 4]:
			if set_pieces[set_id].size() < threshold:
				continue
			for effect: Resource in _sets[set_id][threshold].effects:
				var source_id: String = "equipment." + set_id + ".p%d." % threshold + effect.effect_id
				var built: Dictionary = effect.modifier(source_id)
				sources[source_id] = {"set_id": set_id, "pieces": threshold, "effect_id": effect.effect_id}
				if not built.error.is_empty():
					return _failure(built.error)
				modifiers.append(built.modifier)
	var resolved: RefCounted = Resolver.resolve(_registry, modifiers, active_conditions, tick)
	if not resolved.is_success():
		return _failure("\n".join(resolved.errors()))
	var displaced: Array[String] = []
	for slot: String in SLOTS:
		var old_uid: String = _slots[slot]
		if not old_uid.is_empty() and not staged.values().has(old_uid):
			displaced.append(old_uid)
	_slots = staged
	_stats = resolved.snapshot()
	_special_effects = special_effects
	_sources = sources
	return {"error": "", "displaced": displaced, "stats": _stats}


func stats() -> RefCounted:
	return _stats


func special_effects() -> Array:
	return _special_effects.duplicate(true)


func sources() -> Dictionary:
	return _sources.duplicate(true)


func snapshot() -> Dictionary:
	return {} if _world == null else {"schema_version": 1, "slots": _slots.duplicate()}


func restore(value: Variant, tick: int, active_conditions: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not value is Dictionary or value.size() != 2 or not value.has_all(["schema_version", "slots"]):
		return _failure("Equipment snapshot has unexpected or missing fields.")
	if not (value.schema_version is int or value.schema_version is float) or value.schema_version != 1:
		return _failure("Unsupported equipment snapshot version.")
	if not value.slots is Dictionary or value.slots.size() != SLOTS.size() or not value.slots.has_all(SLOTS):
		return _failure("Equipment snapshot must contain exactly eight slots.")
	return transact(value.slots, tick, active_conditions)


static func _failure(error: String) -> Dictionary:
	return {"error": error, "displaced": [], "stats": null}
