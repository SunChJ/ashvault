class_name CraftingCatalog
extends RefCounted

const Rune = preload("res://game/simulation/items/rune_definition.gd")
const Word = preload("res://game/simulation/items/runeword_definition.gd")
const Policy = preload("res://game/simulation/items/crafting_policy.gd")
const Effect = preload("res://game/simulation/items/item_stat_effect.gd")
const Instance = preload("res://game/simulation/items/item_instance.gd")
const Id = preload("res://game/content/stable_id.gd")
const MAX_QUALITY := 20

var _runes: Dictionary = {}
var _words: Dictionary = {}
var _policy: Resource


func load_definitions(runes: Array, words: Array, policy: Variant = null) -> String:
	if _policy != null:
		return "Crafting catalog is already published."
	var rules: Variant = Policy.new() if policy == null else policy
	if not rules is Policy:
		return "Crafting requires a CraftingPolicy Resource."
	for amount: int in [rules.quality_rate, rules.socket_rate, rules.reroll_rate, rules.insertion_cost]:
		if amount < 1 or amount > 1000000:
			return "Recipe rates must be between 1 and 1000000."
	if rules.salvage_yields.size() != Instance.RARITIES.size():
		return "Salvage must define all rarity yields."
	for rarity: String in Instance.RARITIES:
		var amount: Variant = rules.salvage_yields.get(rarity)
		if not Instance._integer(amount, 1) or amount > 1000000:
			return "Salvage yields must be bounded positive integers."
	var staged_runes: Dictionary = {}
	for rune: Variant in runes:
		if not rune is Rune or not _id(rune.content_id, "rune.") or staged_runes.has(rune.content_id):
			return "Runes require unique stable rune IDs."
		if rune.effects.is_empty() or not Effect.list_error(rune.effects).is_empty():
			return "Runes require valid numeric effects."
		staged_runes[rune.content_id] = rune
	var staged_words: Dictionary = {}
	var signatures: Dictionary = {}
	for word: Variant in words:
		if not word is Word or not _id(word.content_id, "runeword.") or staged_words.has(word.content_id):
			return "Runewords require unique stable runeword IDs."
		if word.runes.size() < 2 or word.runes.size() > 32 or word.allowed_bases.is_empty() or word.effects.is_empty() or not Effect.list_error(word.effects).is_empty():
			return "Runewords require 2–32 ordered runes, eligible bases, and effects."
		for rune_id: String in word.runes:
			if not staged_runes.has(rune_id):
				return "Runeword references an unknown rune."
		for base_id: String in word.allowed_bases:
			var signature := base_id + ":" + ",".join(word.runes)
			if not _id(base_id, "item.") or signatures.has(signature):
				return "Runeword bases must be valid and ordered recipes unambiguous."
			signatures[signature] = true
		staged_words[word.content_id] = word
	for definition: Resource in staged_runes.values() + staged_words.values():
		definition.freeze()
	rules.freeze()
	_runes = staged_runes
	_words = staged_words
	_policy = rules
	return ""


func is_loaded() -> bool:
	return _policy != null


func policy() -> Resource:
	return _policy


func rune(id: String) -> Resource:
	return _runes.get(id)


func material_known(id: String) -> bool:
	return id == "material.shard" or _runes.has(id)


func bases_error(definitions: Dictionary) -> String:
	for word: Resource in _words.values():
		for id: String in word.allowed_bases:
			var definition: Resource = definitions.get(id)
			if definition == null or not definition.allowed_rarities.has("white") or definition.max_sockets < word.runes.size():
				return "Runeword base must exist, allow white rarity, and have enough sockets."
	return ""


func record_error(record: Dictionary) -> String:
	if record.quality > MAX_QUALITY:
		return "Item quality exceeds the crafting cap."
	for id: String in record.sockets:
		if not id.is_empty() and not _runes.has(id):
			return "Socket references an unpublished rune."
	return ""


func active_word(record: Dictionary) -> Resource:
	if record.rarity != "white":
		return null
	for word: Resource in _words.values():
		if word.allowed_bases.has(record.definition_id) and word.runes == record.sockets:
			return word
	return null


static func _id(value: String, prefix: String) -> bool:
	return value.length() <= 128 and value.begins_with(prefix) and Id.is_valid(value)
