class_name LootTable
extends "res://game/content/content_definition.gd"

const Entry = preload("res://game/simulation/items/loot_entry.gd")
const Id = preload("res://game/content/stable_id.gd")

var _source_id := ""
var _entries: Array[Resource] = []

@export var source_id: String:
	get:
		return _source_id
	set(value):
		if not is_frozen():
			_source_id = value

@export var entries: Array[Resource]:
	get:
		return _entries.duplicate()
	set(value):
		if not is_frozen():
			_entries = value.duplicate()


func validation_error(catalog: RefCounted) -> String:
	if not Id.is_valid(content_id) or not content_id.begins_with("loot.") or not Id.is_valid(source_id) or not source_id.begins_with("drop_source."):
		return "Loot tables require stable loot and drop_source IDs."
	if not tags.is_empty() or not dependencies.is_empty():
		return "Loot tables currently use explicit item references, without tags or dependencies."
	if entries.size() > 1024:
		return "Loot tables support at most 1024 entries."
	var seen: Dictionary = {}
	var total: int = 0
	for entry: Resource in entries:
		if not entry is Entry or not Id.is_valid(entry.entry_id) or not entry.entry_id.begins_with("entry.") or seen.has(entry.entry_id):
			return "Loot entries require unique stable entry IDs."
		if entry.weight < 1 or entry.weight > 2147483647:
			return "Loot weights must be positive signed 32-bit integers."
		total += entry.weight
		if total > 2147483647:
			return "Total loot weight exceeds the signed 32-bit draw range."
		seen[entry.entry_id] = true
		if entry.definition_id.is_empty():
			if not entry.rarity.is_empty():
				return "No-drop entries must omit both item and rarity."
			continue
		var item: Resource = catalog.get_definition(entry.definition_id)
		if item == null or not item.allowed_rarities.has(entry.rarity):
			return "Loot entry references an unknown item or unsupported rarity."
		if entry.rarity == "green" and item.drop_source_id != source_id:
			return "Target-farmed green items must match their authored drop source."
	return ""


func freeze() -> void:
	_entries.sort_custom(func(a: Resource, b: Resource) -> bool: return a.entry_id < b.entry_id)
	for entry: Resource in _entries:
		entry.freeze()
	super.freeze()
