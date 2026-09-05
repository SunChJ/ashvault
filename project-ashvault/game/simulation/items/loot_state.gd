class_name LootState
extends RefCounted

const Ownership = preload("res://game/simulation/items/inventory_state.gd")
const World = preload("res://game/simulation/items/item_world.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const Generator = preload("res://game/simulation/items/item_generator.gd")
const Table = preload("res://game/simulation/items/loot_table.gd")
const Instance = preload("res://game/simulation/items/item_instance.gd")
const Id = preload("res://game/content/stable_id.gd")

var _used := false
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
	_used = true
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


func restore(value: Variant) -> String:
	if _world == null or _used:
		return "Loot restore requires configured unused state."
	if not Ownership._fields(value, ["schema_version", "creator_id", "receipts", "ground"]) or value.schema_version != 2 or value.creator_id != _creator_id or not value.receipts is Dictionary or not value.ground is Dictionary:
		return "Invalid loot restore sections or creator."
	var receipts: Dictionary = {}
	var drops: Dictionary = {}
	var ground: Dictionary = {}
	for occurrence: Variant in value.receipts:
		var data: Variant = value.receipts[occurrence]
		if not occurrence is String or not _valid_id(occurrence) or not Ownership._fields(data, ["occurrence_id", "creator_id", "owner_id", "source_id", "table_id", "entry_id", "item_level", "draw", "total_weight", "item"]):
			return "Invalid drop receipt fields."
		for field: String in ["occurrence_id", "creator_id", "owner_id", "source_id", "table_id", "entry_id"]:
			if not data[field] is String:
				return "Drop identities must be strings."
		var table: Resource = _tables.get(data.table_id)
		if data.occurrence_id != occurrence or data.creator_id != _creator_id or not _inventory.has_owner(data.owner_id) or table == null or table.source_id != data.source_id or not Instance._integer(data.item_level, 1) or data.item_level > 2147483647 or not data.item is Dictionary:
			return "Invalid drop source, owner, table, level, or item."
		var total := 0
		for entry: Resource in table.entries:
			total += entry.weight
		if not Instance._integer(data.total_weight, 0) or data.total_weight != total or not Instance._integer(data.draw, -1) or (total == 0 and data.draw != -1) or (total > 0 and (data.draw < 0 or data.draw >= total)):
			return "Drop selection evidence does not match the table."
		var selected: Resource
		var cumulative := 0
		for entry: Resource in table.entries:
			cumulative += entry.weight
			if data.draw >= 0 and data.draw < cumulative:
				selected = entry
				break
		if data.entry_id != ("" if selected == null else selected.entry_id):
			return "Drop entry does not match its selection draw."
		if selected == null or selected.definition_id.is_empty():
			if not data.item.is_empty():
				return "No-drop receipt cannot contain an item."
		else:
			var error: String = _world.item_catalog().validate_record(data.item)
			if not error.is_empty():
				return error
			var item: RefCounted = _world.get_item(data.item.uid)
			if item == null or drops.has(data.item.uid) or item.definition_id() != selected.definition_id or data.item.definition_id != selected.definition_id or data.item.rarity != selected.rarity or data.item.item_level != data.item_level:
				return "Drop UID or generated provenance is inconsistent."
			drops[data.item.uid] = occurrence
			var location: Dictionary = _inventory.location(data.item.uid)
			if location.get("container") == "ground":
				if location.holder_id != data.owner_id:
					return "Reserved ground owner disagrees with receipt."
				ground[data.item.uid] = occurrence
		var normalized: Dictionary = data.duplicate(true)
		for field: String in ["item_level", "draw", "total_weight"]:
			normalized[field] = int(normalized[field])
		if not normalized.item.is_empty():
			var original := Instance.new()
			original._initialize(normalized.item)
			normalized.item = original.snapshot()
		receipts[occurrence] = normalized
	if ground != value.ground:
		return "Ground receipt index disagrees with inventory."
	for uid: String in _inventory.snapshot().locations:
		if _inventory.location(uid).container == "ground" and not ground.has(uid):
			return "Ground UID has no source receipt."
	_receipts = receipts
	_drops = drops
	_used = true
	return ""
