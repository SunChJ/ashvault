extends SceneTree

const Loot = preload("res://game/simulation/items/loot_state.gd")
const Table = preload("res://game/simulation/items/loot_table.gd")
const Entry = preload("res://game/simulation/items/loot_entry.gd")
const World = preload("res://game/simulation/items/item_world.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const Fixture = preload("res://tests/fixtures/items/affix_fixture.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _entry(id: String, item: String, rarity: String, weight: int = 1) -> Resource:
	var entry := Entry.new()
	entry.entry_id = id
	entry.definition_id = item
	entry.rarity = rarity
	entry.weight = weight
	return entry


func _table(id: String, entries: Array[Resource]) -> Resource:
	var table := Table.new()
	table.content_id = id
	table.source_id = "drop_source.fixture"
	table.entries = entries
	return table


func _fixture(reverse: bool = false) -> Dictionary:
	var world := World.new()
	world.configure("profile.loot", Fixture.catalog())
	var streams := Streams.new()
	streams.initialize(415)
	var entries: Array[Resource] = [_entry("entry.blue", "item.base", "blue", 3), _entry("entry.none", "", "", 2), _entry("entry.white", "item.base", "white")]
	if reverse:
		entries.reverse()
	var tables: Array[Resource] = [_table("loot.mixed", entries), _table("loot.empty", []), preload("res://tests/fixtures/items/white_loot.tres"), _table("loot.blocked", [_entry("entry.blocked", "item.blocked", "green")])]
	tables[3].source_id = "drop_source.blocked"
	var loot := Loot.new()
	_check(loot.configure(world, streams, "authority.local", tables).is_empty(), "Loot must configure.")
	_check(loot.register_owner("authority.local", "actor.player", 1).is_empty(), "Bounded bag must register.")
	return {"loot": loot, "world": world, "streams": streams, "tables": tables}


func _drop(f: Dictionary, occurrence: String, table: String = "loot.white", creator: String = "authority.local", owner: String = "actor.player", source: String = "drop_source.fixture") -> Dictionary:
	return f.loot.drop(creator, occurrence, source, table, owner, 40)


func _run() -> void:
	var f := _fixture()
	var g := _fixture(true)
	var initial_rng: Dictionary = f.streams.snapshot()
	var empty: Dictionary = _drop(f, "occurrence.empty", "loot.empty")
	_drop(g, "occurrence.empty", "loot.empty")
	_check(empty.error.is_empty() and empty.receipt.item.is_empty() and empty.receipt.draw == -1, "Empty table must produce an explicit receipt.")
	_check(f.streams.snapshot() == initial_rng and f.world.snapshot().items.is_empty(), "Empty table must consume no RNG or UID.")
	_check(not _drop(f, "occurrence.empty").error.is_empty(), "Empty occurrences cannot be rerolled with another table.")
	var no_drops := 0
	for index in 200:
		var id := "occurrence.roll_%d" % index
		var result: Dictionary = _drop(f, id, "loot.mixed")
		var repeated: Dictionary = _drop(g, id, "loot.mixed")
		_check(result.error.is_empty() and result == repeated, "Seed and canonical entry order must reproduce every receipt.")
		if result.receipt.item.is_empty():
			no_drops += 1
		else:
			_check(result.receipt.item == f.world.get_item(result.receipt.item.uid).snapshot(), "Receipt must preserve full generated rolls and item level.")
	_check(no_drops > 0 and no_drops < 200, "Weighted table must exercise item and no-drop outcomes.")
	_check(f.streams.snapshot().streams.combat == initial_rng.streams.combat and f.streams.snapshot().streams.dungeon == initial_rng.streams.dungeon, "Loot must not advance other streams.")
	var before: Dictionary = f.loot.snapshot()
	var world_before: Dictionary = f.world.snapshot()
	var rng_before: Dictionary = f.streams.snapshot()
	for args: Array in [["occurrence.foreign", "loot.white", "authority.foreign", "actor.player", "drop_source.fixture"], ["occurrence.owner", "loot.white", "authority.local", "actor.foreign", "drop_source.fixture"], ["occurrence.source", "loot.white", "authority.local", "actor.player", "drop_source.foreign"], ["occurrence.unknown", "loot.unknown", "authority.local", "actor.player", "drop_source.fixture"], ["occurrence.blocked", "loot.blocked", "authority.local", "actor.player", "drop_source.blocked"]]:
		_check(not _drop(f, args[0], args[1], args[2], args[3], args[4]).error.is_empty(), "Invalid authority, source, content, or generation must fail.")
	_check(f.loot.snapshot() == before and f.world.snapshot() == world_before and f.streams.snapshot() == rng_before, "Failed drops must preserve all state, identities, and RNG.")
	var first: Dictionary = _drop(f, "occurrence.first")
	var second: Dictionary = _drop(f, "occurrence.second")
	var uid: String = first.receipt.item.uid
	var next_uid: String = second.receipt.item.uid
	_check(first.receipt.creator_id == "authority.local" and first.receipt.owner_id == "actor.player" and first.receipt.source_id == "drop_source.fixture" and first.receipt.table_id == "loot.white" and first.receipt.entry_id == "entry.white" and first.receipt.item.item_level == 40, "Receipt must expose source, creator, owner, table, entry, and level.")
	_check(not _drop(f, "occurrence.first").error.is_empty(), "One source occurrence must allocate at most one UID.")
	_check(not f.loot.pickup("authority.foreign", "actor.player", uid).is_empty(), "Foreign creator must not mutate ownership.")
	f.loot.register_owner("authority.local", "actor.foreign", 10)
	_check(not f.loot.pickup("authority.local", "actor.foreign", uid).is_empty(), "Foreign owner must not pick up a reserved drop.")
	_check(f.loot.pickup("authority.local", "actor.player", uid).is_empty(), "Pickup must transfer the existing UID.")
	before = f.loot.snapshot()
	_check(not f.loot.pickup("authority.local", "actor.player", uid).is_empty(), "Duplicate pickup must fail.")
	_check(not f.loot.pickup("authority.local", "actor.player", next_uid).is_empty(), "Full inventory must reject pickup.")
	_check(f.loot.snapshot() == before, "Rejected pickup must retain ground and bag ownership.")
	_check(f.loot.resize_bag("authority.local", "actor.player", 2).is_empty(), "Authority can increase bag capacity.")
	_check(f.loot.pickup("authority.local", "actor.player", next_uid).is_empty(), "Full-bag failure must remain retryable.")
	_check(f.loot.bag_items("actor.player") == PackedStringArray([uid, next_uid]), "Each UID must occupy exactly one bag position.")
	_check(not f.loot.resize_bag("authority.local", "actor.player", 1).is_empty(), "Capacity cannot shrink below contents.")
	before = f.loot.snapshot()
	var exposed: Dictionary = f.loot.snapshot()
	exposed.receipts.clear()
	first.receipt.item.rolls.append({})
	_check(f.loot.snapshot() == before, "Snapshots and returned receipts must not alias state.")
	f.tables[0].entries[0].weight = 999
	f.tables[0].source_id = "drop_source.changed"
	_check(f.tables[0].entries[0].weight != 999 and f.tables[0].source_id == "drop_source.fixture", "Published tables and entries must be frozen.")
	_check(JSON.stringify(f.world.snapshot()).sha256_text() == "c3b67efdff6217a00a1b70fe10ec78a0e5a3028467fef97650367a179a735744", "Seeded loot fixture must retain its pinned item hash.")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(before))
	_check(decoded.ground == before.ground and decoded.bags["actor.player"].items == before.bags["actor.player"].items and decoded.receipts.size() == before.receipts.size(), "JSON evidence must preserve ground, bag, and occurrence identities.")
	_test_invalid_tables()
	_test_allocation_failure()
	print(JSON.stringify({"fixture": "loot", "samples": 200, "no_drops": no_drops, "state_hash": JSON.stringify(f.world.snapshot()).sha256_text()}))
	if failures.is_empty():
		print("Production loot contracts passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_invalid_tables() -> void:
	var f := _fixture()
	for raw_entries: Array in [[_entry("entry.bad", "item.missing", "white")], [_entry("entry.bad", "item.base", "red")], [_entry("entry.bad", "", "white")], [_entry("entry.bad", "item.base", "white", 0)], [_entry("entry.same", "", ""), _entry("entry.same", "", "")], [_entry("entry.a", "", "", 2147483647), _entry("entry.b", "", "")]]:
		var entries: Array[Resource] = []
		entries.assign(raw_entries)
		var table: Resource = _table("loot.invalid", entries)
		var loot := Loot.new()
		_check(not loot.configure(f.world, f.streams, "authority.local", [table]).is_empty() and not table.is_frozen(), "Invalid table publication must fail without freezing content.")

	var green: Resource = _table("loot.green", [_entry("entry.green", "item.green", "green")])
	green.source_id = "drop_source.foreign"
	_check(not Loot.new().configure(f.world, f.streams, "authority.local", [green]).is_empty(), "Green loot must reject an unrelated source.")
	green.source_id = "drop_source.fixture"
	var loot := Loot.new()
	_check(loot.configure(f.world, f.streams, "authority.local", [green]).is_empty(), "Correctly sourced green loot must publish.")
	loot.register_owner("authority.local", "actor.player", 0)
	var result: Dictionary = loot.drop("authority.local", "occurrence.green", "drop_source.fixture", "loot.green", "actor.player", 40)
	_check(result.error.is_empty() and result.receipt.item.rarity == "green", "Target-farmed green drops must use the shared affix generator.")
	_check(not loot.pickup("authority.local", "actor.player", result.receipt.item.uid).is_empty(), "Zero-capacity bags cannot pick up items.")


func _test_allocation_failure() -> void:
	var f := _fixture()
	var world := World.new()
	world.configure("profile.exhausted", Fixture.catalog())
	var state: Dictionary = world.snapshot()
	state.next_sequence = "9223372036854775807"
	_check(world.restore(state).is_empty(), "Exhausted identity fixture must restore.")
	var loot := Loot.new()
	_check(loot.configure(world, f.streams, "authority.local", f.tables).is_empty(), "Frozen tables must support reuse.")
	loot.register_owner("authority.local", "actor.player", 1)
	var rng_before: Dictionary = f.streams.snapshot()
	var before: Dictionary = loot.snapshot()
	_check(not loot.drop("authority.local", "occurrence.exhausted", "drop_source.fixture", "loot.white", "actor.player", 40).error.is_empty(), "Failed UID allocation must reject the selected drop.")
	_check(world.snapshot() == state and loot.snapshot() == before and f.streams.snapshot() == rng_before, "UID exhaustion must roll back selection RNG and ownership.")
	for level: Variant in [0, -1, 1.5, 2147483648, "40", NAN]:
		_check(not loot.drop("authority.local", "occurrence.invalid", "drop_source.fixture", "loot.white", "actor.player", level).error.is_empty(), "Invalid item levels must be rejected before generation.")
	_check(not loot.register_owner("authority.local", "actor.player", 10).is_empty(), "Registering an existing owner must not clear its bag.")
	_check(not loot.register_owner("authority.foreign", "actor.other", 10).is_empty(), "Foreign authority cannot register owners.")
	_check(not loot.resize_bag("authority.foreign", "actor.player", 10).is_empty(), "Foreign authority cannot resize bags.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
