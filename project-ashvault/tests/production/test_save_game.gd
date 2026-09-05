extends SceneTree

const Fixture = preload("res://tests/fixtures/items/crafting_fixture.gd")
const Codec = preload("res://game/infrastructure/save/save_game_v1.gd")
const Store = preload("res://game/infrastructure/save/save_store.gd")
const JsonContract = preload("res://game/infrastructure/save/save_json.gd")
const Interrupted = preload("res://tests/fixtures/save/interrupted_store.gd")
const Progression = preload("res://game/simulation/progression/character_progression.gd")
const ProgressionCatalog = preload("res://game/simulation/progression/progression_catalog.gd")
const Loot = preload("res://game/simulation/items/loot_state.gd")
const Table = preload("res://game/simulation/items/loot_table.gd")
const Entry = preload("res://game/simulation/items/loot_entry.gd")
const Stat = preload("res://game/simulation/stats/stat_definition.gd")
const Registry = preload("res://game/simulation/stats/stat_registry.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _fixture() -> Dictionary:
	var f: Dictionary = Fixture.create()
	var stat := Stat.new()
	stat.configure("stat.power", 100)
	var registry := Registry.new()
	registry.load_definitions([stat])
	var progression_catalog := ProgressionCatalog.new()
	progression_catalog.load_definitions(preload("res://game/simulation/progression/character_curve.tres"), [], [])
	var progression := Progression.new()
	progression.configure("character.fixture", progression_catalog, registry)
	progression.award_xp("run.fixture", 1, 300)
	var entry := Entry.new()
	entry.entry_id = "entry.wand"
	entry.definition_id = "item.wand"
	entry.rarity = "white"
	var table := Table.new()
	table.content_id = "loot.fixture"
	table.source_id = "drop_source.fixture"
	table.entries = [entry]
	var loot := Loot.new()
	loot.configure(f.world, f.streams, "authority.local", [table], f.inventory)
	loot.drop("authority.local", "occurrence.fixture", table.source_id, table.content_id, "actor.player", 1)
	f.inventory.grant_materials("authority.local", "actor.player", {"material.shard": 20})
	f.inventory.craft("authority.local", "actor.player", 0, f.items[0], "quality", f.streams)
	f.inventory.equip("authority.local", "actor.player", {"slot.weapon": f.items[0].uid()}, 1)
	f.inventory.register_vendor("authority.local", "vendor.fixture", 1, {"item.wand": {"buy": 10, "sell": 5}})
	var stock: String = f.world.copy_item(f.items[0].uid()).item.uid()
	f.inventory.place_item("authority.local", "vendor.fixture", "stock", 0, stock)
	var session := {"world": f.world, "inventory": f.inventory, "progression": progression, "rng": f.streams, "loot": loot, "character": {"character_id": "character.fixture", "owner_id": "actor.player", "creator_id": "authority.local", "item_namespace": "profile.craft"}, "world_run": {"run_id": "run.fixture", "checkpoint_id": "checkpoint.town", "tick": 12}, "settings": {"master_volume": 0.75, "fullscreen": false}}
	var codec := Codec.new()
	codec.configure(f.world.item_catalog(), progression_catalog, registry, [table])
	return {"codec": codec, "session": session, "dto": Codec.capture(session)}


func _run() -> void:
	var f: Dictionary = _fixture()
	var directory := ProjectSettings.globalize_path("user://save-contract-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Save test directory must be created.")
	var path := directory.path_join("character.json")
	var store := Store.new()
	store.configure(f.codec)
	var saved: Dictionary = store.save_game(path, f.dto)
	_check(saved.error.is_empty(), "Initial save must succeed: " + saved.error)
	_check(FileAccess.file_exists(path + ".bak"), "First save must seed a recoverable backup generation.")
	var loaded: Dictionary = store.load_game(path)
	_check(loaded.error.is_empty() and not loaded.get("recovered", true), "Primary must round-trip without recovery: " + loaded.error)
	if not loaded.error.is_empty():
		_finish(directory)
		return
	_check(loaded.session.world.snapshot() == f.session.world.snapshot(), "Item UID records must round-trip exactly.")
	_check(loaded.session.inventory.snapshot() == f.session.inventory.snapshot(), "Containers, materials, vendors, equipment, and locations must round-trip.")
	_check(loaded.session.progression.snapshot() == f.session.progression.snapshot(), "Character progression must round-trip.")
	_check(loaded.session.loot.snapshot() == f.session.loot.snapshot(), "Ground provenance and ownership must round-trip.")
	_check(loaded.session.inventory.equipment_stats("actor.player").values() == f.session.inventory.equipment_stats("actor.player").values(), "Equipment stats must reconstruct from records.")
	for name: String in ["combat", "loot", "dungeon"]:
		_check(loaded.session.rng.get_stream(name).next_u32() == f.session.rng.get_stream(name).next_u32(), "Each RNG stream must continue with the exact next draw.")
	_check(not loaded.session.progression.award_xp("run.fixture", 1, 300).is_empty(), "Restored reward watermark must reject duplicate XP.")
	var next: Dictionary = f.dto.duplicate(true)
	next.settings.master_volume = 0.5
	_check(store.save_game(path, next).error.is_empty(), "Second save must replace primary and retain backup.")
	var backup_text := FileAccess.get_file_as_string(path + ".bak")
	_check(JsonContract.decode(backup_text).error.is_empty(), "Backup must have a valid checksum envelope.")
	var interrupted := Interrupted.new()
	interrupted.configure(f.codec)
	var third: Dictionary = next.duplicate(true)
	third.settings.master_volume = 0.25
	for stage: String in ["temporary_ready", "backup_ready"]:
		interrupted.stop_at = stage
		_check(not interrupted.save_game(path, third).error.is_empty(), "Interrupted save must stop at its durable boundary.")
		_check(store.load_game(path).session.settings.master_volume == 0.5, "Interrupted save must preserve the last committed primary.")
	_write(path + ".tmp", "partial")
	_check(store.load_game(path).session.settings.master_volume == 0.5, "Partial temporary files must never replace committed state during load.")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	envelope.payload += " "
	_write(path, JSON.stringify(envelope))
	var recovered: Dictionary = store.load_game(path)
	_check(recovered.error.is_empty() and recovered.recovered and recovered.session.settings.master_volume == 0.5, "Checksum failure must recover the last validated backup.")
	var backup_before := FileAccess.get_file_as_string(path + ".bak")
	_check(store.save_game(path, third).error.is_empty(), "A new validated save may replace a corrupt primary.")
	_check(FileAccess.get_file_as_string(path + ".bak") == backup_before, "Corrupt primary must never overwrite the good backup.")
	var invalid: Dictionary = third.duplicate(true)
	invalid.items.items[0].definition_id = "item.missing"
	var primary_before := FileAccess.get_file_as_string(path)
	_check(not store.save_game(path, invalid).error.is_empty() and FileAccess.get_file_as_string(path) == primary_before, "Missing content must reject writes before touching the primary.")
	_write(path, JsonContract.encode(invalid).text)
	_check(store.load_game(path).get("recovered", false), "Content-reference failure must also attempt backup recovery.")
	_write(path + ".bak", "broken")
	_check(not store.load_game(path).error.is_empty(), "Failure of primary and backup must be reported.")
	_check(not store.save_game(directory.path_join("missing/character.json"), third).error.is_empty(), "I/O failure must return an actionable error.")
	_test_migration(f, store, path)
	_test_validation(f)
	print(JSON.stringify({"fixture": "save_game", "stages": interrupted.breadcrumbs(), "migration": "v0_to_v1"}))
	_finish(directory)


func _test_migration(f: Dictionary, store: RefCounted, path: String) -> void:
	var legacy: Dictionary = f.dto.duplicate(true)
	legacy.schema_version = 0
	legacy.versions.save_schema_version = 0
	legacy.erase("settings")
	legacy.inventory.schema_version = 1
	for owner: String in legacy.inventory.owners:
		legacy.inventory.owners[owner].erase("materials")
	_write(path, JsonContract.encode(legacy).text)
	var loaded: Dictionary = store.load_game(path)
	_check(loaded.error.is_empty() and loaded.migrations == ["v0_to_v1"] and loaded.session.settings.master_volume == 1.0, "Legacy v0 must take the explicit migration step.")
	_check(loaded.session.inventory.snapshot().owners["actor.player"].materials.is_empty(), "Legacy inventory migration must initialize its absent material wallet.")
	_check(loaded.session.rng.snapshot() == f.dto.rng, "Migration must preserve all RNG state.")
	_check(not Codec.migrate({"schema_version": 2}).error.is_empty(), "Future schema versions must not downgrade.")
	var malformed: Dictionary = legacy.duplicate(true)
	malformed.inventory.owners["actor.player"].materials = {}
	_check(not Codec.migrate(malformed).error.is_empty(), "Malformed legacy schemas cannot be silently repaired.")


func _test_validation(f: Dictionary) -> void:
	for value: Variant in [Node.new(), Resource.new(), Callable(self, "_run"), Vector2.ZERO, NAN, 9007199254740992]:
		_check(not JsonContract.encode({"value": value}).error.is_empty(), "Engine values and unsafe numbers must be rejected.")
		if value is Node:
			value.free()
	var cyclic: Array = []
	cyclic.append(cyclic)
	_check(not JsonContract.encode({"cycle": cyclic}).error.is_empty(), "Cyclic DTOs must fail the depth bound before serialization.")
	cyclic.clear()
	var uid: String = f.dto.items.items[0].uid
	for mutation: String in ["duplicate_uid", "missing_location", "wrong_owner", "bad_receipt", "unknown_rune", "bad_rng", "bad_settings"]:
		var dto: Dictionary = f.dto.duplicate(true)
		match mutation:
			"duplicate_uid": dto.inventory.owners["actor.player"].stash[0] = uid
			"missing_location": dto.inventory.locations.erase(uid)
			"wrong_owner": dto.inventory.locations[uid].holder_id = "actor.other"
			"bad_receipt": dto.world_run.loot.receipts["occurrence.fixture"].draw = 999
			"unknown_rune": dto.items.items[0].sockets = ["rune.missing"]
			"bad_rng": dto.rng.streams.loot.state = "invalid"
			"bad_settings": dto.settings.master_volume = 2
		_check(not f.codec.reconstruct(dto).error.is_empty(), "Invalid save boundary must reject: " + mutation)
	_check(Codec.capture(f.session).inventory == f.dto.inventory, "Invalid reconstruction must not mutate the active inventory.")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _finish(directory: String) -> void:
	for file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	if failures.is_empty():
		print("Production SaveGameV1 contracts passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
