class_name LootState
extends RefCounted

const Ownership = preload("res://game/simulation/items/inventory_state.gd")
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
var _inventory: RefCounted
var _receipts: Dictionary = {}
var _drops: Dictionary = {}


func configure(world: Variant, streams: Variant, creator_id: String, tables: Array, inventory: Variant = null) -> String:
	if _world != null:
		return "Loot state is already configured."
	if not world is World or world.item_catalog() == null or not streams is Streams or not streams.is_initialized() or not _valid_id(creator_id):
		return "Loot requires a published item world, initialized RNG, and stable creator ID."
	var ownership: Variant = inventory
	if ownership == null:
		ownership = Ownership.new()
		ownership.configure(world, creator_id)
	if not ownership is Ownership or not ownership.matches(world, creator_id):
		return "Loot requires inventory for the same item world and creator."
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
	_inventory = ownership
	_world = world
	_streams = streams
	_creator_id = creator_id
	_tables = staged
	return ""


func register_owner(creator_id: String, owner_id: String, capacity: int) -> String:
	return _inventory.register_owner(creator_id, owner_id, capacity) if _authorized(creator_id) else "Invalid authority."


func resize_bag(creator_id: String, owner_id: String, capacity: int) -> String:
	return _inventory.resize_bag(creator_id, owner_id, capacity) if _authorized(creator_id) else "Invalid authority."


func drop(creator_id: String, occurrence_id: String, source_id: String, table_id: String, owner_id: String, item_level: Variant) -> Dictionary:
	if not _authorized(creator_id) or not _valid_id(occurrence_id) or _receipts.has(occurrence_id) or not _inventory.has_owner(owner_id):
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
		var reservation_error: String = _inventory.reserve_drop(creator_id, owner_id, item.uid)
		assert(reservation_error.is_empty(), "Freshly allocated drop UID must reserve successfully.")
		_drops[item.uid] = occurrence_id
	return {"error": "", "receipt": receipt.duplicate(true)}


func pickup(creator_id: String, owner_id: String, uid: String) -> String:
	if not _authorized(creator_id) or not _inventory.has_owner(owner_id) or not _drops.has(uid):
		return "Invalid authority, owner, or ground UID."
	var receipt: Dictionary = _receipts[_drops[uid]]
	if receipt.owner_id != owner_id or receipt.creator_id != creator_id:
		return "Pickup must match the drop creator and reserved owner."
	var error: String = _inventory.pickup(creator_id, owner_id, uid)
	if not error.is_empty():
		return error
	return ""


func bag_items(owner_id: String) -> PackedStringArray:
	return _inventory.bag_items(owner_id) if _inventory != null else PackedStringArray()


func snapshot() -> Dictionary:
	var ground: Dictionary = {}
	for uid: String in _drops:
		if _inventory.location(uid).get("container") == "ground":
			ground[uid] = _drops[uid]
	return {"schema_version": 2, "creator_id": _creator_id, "inventory": {} if _inventory == null else _inventory.snapshot(), "receipts": _receipts.duplicate(true), "ground": ground}


func _authorized(creator_id: String) -> bool:
	return _world != null and creator_id == _creator_id


static func _valid_id(value: String) -> bool:
	return value.length() <= 128 and Id.is_valid(value)


static func _failure(error: String) -> Dictionary:
	return {"error": error, "receipt": {}}
