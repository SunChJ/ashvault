class_name SaveGameV1
extends RefCounted

const Versions = preload("res://game/infrastructure/version_info.gd")
const JsonContract = preload("res://game/infrastructure/save/save_json.gd")
const World = preload("res://game/simulation/items/item_world.gd")
const Ownership = preload("res://game/simulation/items/inventory_state.gd")
const Progression = preload("res://game/simulation/progression/character_progression.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const Loot = preload("res://game/simulation/items/loot_state.gd")
const Id = preload("res://game/content/stable_id.gd")
const FIELDS := ["schema_version", "versions", "character", "items", "inventory", "progression", "world_run", "settings", "rng"]

var _items: RefCounted
var _progression: RefCounted
var _registry: RefCounted
var _tables: Array = []
var _sets: Array = []
var _base: Array = []


func configure(items: RefCounted, progression: RefCounted, registry: RefCounted, tables: Array, set_bonuses: Array = [], base_modifiers: Array = []) -> void:
	_items = items
	_progression = progression
	_registry = registry
	_tables = tables.duplicate()
	_sets = set_bonuses.duplicate()
	_base = base_modifiers.duplicate()


func reconstruct(value: Variant) -> Dictionary:
	var error := JsonContract.validate(value, 0, [JsonContract.MAX_VALUES])
	if not error.is_empty():
		return _failure(error)
	if not Ownership._fields(value, FIELDS) or not Ownership._money(value.schema_version) or value.schema_version != 1 or not Ownership._fields(value.versions, ["content_version", "simulation_version", "save_schema_version"]):
		return _failure("Invalid SaveGameV1 fields or versions.")
	for key: String in Versions.snapshot():
		if not Ownership._money(value.versions[key]) or value.versions[key] != Versions.snapshot()[key]:
			return _failure("Unsupported content, simulation, or save version.")
	if _items == null or _progression == null or _registry == null:
		return _failure("Save reconstruction requires published content dependencies.")
	if not Ownership._fields(value.character, ["character_id", "owner_id", "creator_id", "item_namespace"]):
		return _failure("Invalid character identity fields.")
	for id: Variant in value.character.values():
		if not id is String or id.length() > 128 or not Id.is_valid(id):
			return _failure("Character identities require bounded stable IDs.")
	if not Ownership._fields(value.world_run, ["run_id", "checkpoint_id", "tick", "loot"]) or not value.world_run.run_id is String or not Id.is_valid(value.world_run.run_id) or not value.world_run.checkpoint_id is String or not Id.is_valid(value.world_run.checkpoint_id) or not Ownership._money(value.world_run.tick):
		return _failure("Invalid checkpoint/run fields.")
	if not Ownership._fields(value.settings, ["master_volume", "fullscreen"]) or not value.settings.fullscreen is bool or not (value.settings.master_volume is int or value.settings.master_volume is float) or value.settings.master_volume < 0 or value.settings.master_volume > 1:
		return _failure("Invalid saved settings.")
	var world := World.new()
	error = world.configure(value.character.item_namespace, _items)
	if error.is_empty():
		error = world.restore(value.items)
	if not error.is_empty():
		return _failure(error)
	var progression := Progression.new()
	error = progression.configure(value.character.character_id, _progression, _registry, _base)
	if error.is_empty():
		error = progression.restore(value.progression)
	if not error.is_empty():
		return _failure(error)
	if not value.inventory is Dictionary or not value.inventory.get("owners") is Dictionary or value.inventory.owners.size() != 1 or not value.inventory.owners.has(value.character.owner_id):
		return _failure("SaveGameV1 requires exactly its character's inventory owner.")
	var inventory := Ownership.new()
	error = inventory.configure(world, value.character.creator_id)
	if error.is_empty():
		error = inventory.restore(value.inventory, _registry, _base + progression.passive_modifiers(), _sets)
	if not error.is_empty():
		return _failure(error)
	var rng := Streams.new()
	var rng_errors: PackedStringArray = rng.restore(value.rng)
	if not rng_errors.is_empty():
		return _failure("\n".join(rng_errors))
	var loot := Loot.new()
	error = loot.configure(world, rng, value.character.creator_id, _tables, inventory)
	if error.is_empty():
		error = loot.restore(value.world_run.loot)
	if not error.is_empty():
		return _failure(error)
	return {"error": "", "session": {"world": world, "inventory": inventory, "progression": progression, "rng": rng, "loot": loot, "character": value.character.duplicate(true), "world_run": {"run_id": value.world_run.run_id, "checkpoint_id": value.world_run.checkpoint_id, "tick": int(value.world_run.tick)}, "settings": {"master_volume": float(value.settings.master_volume), "fullscreen": value.settings.fullscreen}}}


static func capture(session: Dictionary) -> Dictionary:
	var run: Dictionary = session.world_run.duplicate(true)
	var loot: Dictionary = session.loot.snapshot()
	loot.erase("inventory")
	run.loot = loot
	return JsonContract.plain_keys({"schema_version": 1, "versions": Versions.snapshot(), "character": session.character.duplicate(true), "items": session.world.snapshot(), "inventory": session.inventory.snapshot(), "progression": session.progression.snapshot(), "world_run": run, "settings": session.settings.duplicate(true), "rng": session.rng.snapshot()})


static func migrate(value: Dictionary) -> Dictionary:
	var validation_error := JsonContract.validate(value, 0, [JsonContract.MAX_VALUES])
	if not validation_error.is_empty():
		return _failure(validation_error)
	if not value.get("schema_version") is float and not value.get("schema_version") is int:
		return _failure("Missing numeric save schema version.")
	var dto: Dictionary = value.duplicate(true)
	var steps: Array[String] = []
	if dto.schema_version == 0:
		var legacy_fields: Array = FIELDS.duplicate()
		legacy_fields.erase("settings")
		if not Ownership._fields(dto, legacy_fields) or not dto.inventory is Dictionary or dto.inventory.get("schema_version") != 1 or not dto.inventory.get("owners") is Dictionary or not Ownership._fields(dto.versions, ["content_version", "simulation_version", "save_schema_version"]) or dto.versions.save_schema_version != 0:
			return _failure("Malformed legacy v0 save.")
		for owner: Variant in dto.inventory.owners:
			if not Ownership._fields(dto.inventory.owners[owner], ["bag", "stash", "currency"]):
				return _failure("Malformed legacy inventory owner.")
			dto.inventory.owners[owner].materials = {}
		dto.inventory.schema_version = 2
		dto.settings = {"master_volume": 1.0, "fullscreen": false}
		dto.schema_version = 1
		dto.versions.save_schema_version = 1
		steps.append("v0_to_v1")
	if dto.schema_version != 1:
		return _failure("Unsupported save schema version; downgrade is forbidden.")
	return {"error": "", "dto": dto, "migrations": steps}


static func _failure(error: String) -> Dictionary:
	return {"error": error}
