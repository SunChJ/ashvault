class_name LootState
extends RefCounted

const World = preload("res://game/simulation/items/item_world.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const Generator = preload("res://game/simulation/items/item_generator.gd")
const Table = preload("res://game/simulation/items/loot_table.gd")
const Instance = preload("res://game/simulation/items/item_instance.gd")
const Id = preload("res://game/content/stable_id.gd")

var _world: RefCounted
var _streams: RefCounted
var _creator_id := ""
var _tables: Dictionary = {}
var _bags: Dictionary = {}
var _receipts: Dictionary = {}
var _ground: Dictionary = {}


func configure(world: Variant, streams: Variant, creator_id: String, tables: Array) -> String:
	if _world != null:
		return "Loot state is already configured."
	if not world is World or world.item_catalog() == null or not streams is Streams or not streams.is_initialized() or not _valid_id(creator_id):
		return "Loot requires a published item world, initialized RNG, and stable creator ID."
	var staged: Dictionary = {}
	for table: Variant in tables:
		if not table is Table:
			return "Loot accepts only LootTable Resources."
		var error: String = table.validation_error(world.item_catalog())
		if not error.is_empty():
			return error
		if staged.has(table.content_id):
			return "Duplicate loot table ID."
		staged[table.content_id] = table
	for table: Resource in staged.values():
		table.freeze()
	_world = world
	_streams = streams
	_creator_id = creator_id
	_tables = staged
	return ""


func register_owner(creator_id: String, owner_id: String, capacity: int) -> String:
	if not _authorized(creator_id) or not _valid_id(owner_id) or _bags.has(owner_id) or capacity < 0 or capacity > 10000:
		return "Invalid authority, duplicate owner, or capacity outside 0–10000."
	_bags[owner_id] = {"capacity": capacity, "items": []}
	return ""


func resize_bag(creator_id: String, owner_id: String, capacity: int) -> String:
	if not _authorized(creator_id) or not _bags.has(owner_id) or capacity < _bags[owner_id].items.size() or capacity > 10000:
		return "Invalid authority, owner, or capacity below contents or above 10000."
	_bags[owner_id].capacity = capacity
	return ""


func drop(creator_id: String, occurrence_id: String, source_id: String, table_id: String, owner_id: String, item_level: Variant) -> Dictionary:
	if not _authorized(creator_id) or not _valid_id(occurrence_id) or _receipts.has(occurrence_id) or not _bags.has(owner_id):
		return _failure("Invalid authority, occurrence, or reserved owner.")
	var table: Resource = _tables.get(table_id)
	if table == null or table.source_id != source_id or not Instance._integer(item_level, 1) or item_level > 2147483647:
		return _failure("Unknown table, mismatched source, or invalid item level.")
	var staged := Streams.new()
	var errors: PackedStringArray = staged.restore(_streams.snapshot())
	assert(errors.is_empty(), "Live RNG must restore into staged streams.")
	var total: int = 0
	for entry: Resource in table.entries:
		total += entry.weight
	var draw: int = -1
	var selected: Resource
	if total > 0:
		draw = staged.get_stream(Streams.LOOT).next_int(0, total - 1)
		var cumulative: int = 0
		for entry: Resource in table.entries:
			cumulative += entry.weight
			if draw < cumulative:
				selected = entry
				break
	var item: Dictionary = {}
	if selected != null and not selected.definition_id.is_empty():
		var result: Dictionary = Generator.generate(_world, staged, selected.definition_id, item_level, selected.rarity)
		if not result.error.is_empty():
			return _failure(result.error)
		item = result.item.snapshot()
	var receipt := {"occurrence_id": occurrence_id, "creator_id": creator_id, "owner_id": owner_id, "source_id": source_id, "table_id": table_id, "entry_id": "" if selected == null else selected.entry_id, "item_level": int(item_level), "draw": draw, "total_weight": total, "item": item}
	# All fallible validation and item allocation precede the ownership/RNG commit.
	errors = _streams.restore(staged.snapshot())
	assert(errors.is_empty(), "Generated RNG must remain valid.")
	_receipts[occurrence_id] = receipt
	if not item.is_empty():
		_ground[item.uid] = occurrence_id
	return {"error": "", "receipt": receipt.duplicate(true)}


func pickup(creator_id: String, owner_id: String, uid: String) -> String:
	if not _authorized(creator_id) or not _bags.has(owner_id) or not _ground.has(uid):
		return "Invalid authority, owner, or ground UID."
	var receipt: Dictionary = _receipts[_ground[uid]]
	var bag: Dictionary = _bags[owner_id]
	if receipt.owner_id != owner_id or receipt.creator_id != creator_id:
		return "Pickup must match the drop creator and reserved owner."
	if bag.items.size() >= bag.capacity:
		return "Inventory is full."
	bag.items.append(uid)
	_ground.erase(uid)
	return ""


func bag_items(owner_id: String) -> PackedStringArray:
	return PackedStringArray(_bags[owner_id].items) if _bags.has(owner_id) else PackedStringArray()


func snapshot() -> Dictionary:
	return {"schema_version": 1, "creator_id": _creator_id, "bags": _bags.duplicate(true), "receipts": _receipts.duplicate(true), "ground": _ground.duplicate(true)}


func _authorized(creator_id: String) -> bool:
	return _world != null and creator_id == _creator_id


static func _valid_id(value: String) -> bool:
	return value.length() <= 128 and Id.is_valid(value)


static func _failure(error: String) -> Dictionary:
	return {"error": error, "receipt": {}}
