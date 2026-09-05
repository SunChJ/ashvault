class_name InventoryState
extends RefCounted

const World = preload("res://game/simulation/items/item_world.gd")
const Equipment = preload("res://game/simulation/items/equipment_state.gd")
const Instance = preload("res://game/simulation/items/item_instance.gd")
const Id = preload("res://game/content/stable_id.gd")
const MAX_CURRENCY := 2147483647

var _world: RefCounted
var _creator := ""
var _owners: Dictionary = {}
var _vendors: Dictionary = {}
var _locations: Dictionary = {}
var _equipment: Dictionary = {}


func configure(world: Variant, creator_id: String) -> String:
	if _world != null or not world is World or world.item_catalog() == null or not _id(creator_id):
		return "Inventory requires an unused state, published item world, and stable creator ID."
	_world = world
	_creator = creator_id
	return ""


func matches(world: RefCounted, creator_id: String) -> bool:
	return _world == world and authorized(creator_id)


func authorized(creator_id: String) -> bool:
	return _world != null and _creator == creator_id


func has_owner(owner_id: String) -> bool:
	return _owners.has(owner_id)


func register_owner(creator_id: String, owner_id: String, bag_capacity: int, stash_capacity: int = 0, currency: Variant = 0) -> String:
	if not authorized(creator_id) or not _id(owner_id) or has_owner(owner_id) or not _capacity(bag_capacity) or not _capacity(stash_capacity) or not _money(currency):
		return "Invalid authority, owner, capacity, or initial currency."
	_owners[owner_id] = {"bag": _slots(bag_capacity), "stash": _slots(stash_capacity), "currency": int(currency)}
	return ""


func resize_bag(creator_id: String, owner_id: String, capacity: int) -> String:
	if not authorized(creator_id) or not has_owner(owner_id) or not _capacity(capacity):
		return "Invalid authority, owner, or capacity."
	var slots: Array = _owners[owner_id].bag
	for index in range(capacity, slots.size()):
		if not slots[index].is_empty():
			return "Shrinking would remove an occupied slot."
	var old_size: int = slots.size()
	slots.resize(capacity)
	for index in range(old_size, capacity):
		slots[index] = ""
	return ""


func register_vendor(creator_id: String, vendor_id: String, capacity: int, prices: Dictionary) -> String:
	if not authorized(creator_id) or not _id(vendor_id) or _vendors.has(vendor_id) or not _capacity(capacity):
		return "Invalid authority, vendor, or stock capacity."
	var staged: Dictionary = {}
	for id: Variant in prices:
		var price: Variant = prices[id]
		if not id is String or _world.item_catalog().get_definition(id) == null or not price is Dictionary or price.size() != 2 or not price.has_all(["buy", "sell"]):
			return "Prices require known item definitions and exactly buy/sell amounts."
		if not _money(price.buy) or not _money(price.sell) or price.sell > price.buy:
			return "Prices must be bounded currency amounts with sell no greater than buy."
		staged[id] = {"buy": int(price.buy), "sell": int(price.sell)}
	_vendors[vendor_id] = {"stock": _slots(capacity), "prices": staged}
	return ""


# Trusted setup/reward paths claim only previously unlocated ItemWorld UIDs.
func place_item(creator_id: String, holder_id: String, container: String, slot: int, uid: String) -> String:
	if not authorized(creator_id) or _world.get_item(uid) == null or _locations.has(uid):
		return "Only known unlocated UIDs can be placed by authority."
	var slots: Array = _container(holder_id, container)
	if not _empty_slot(slots, slot):
		return "Invalid or occupied destination slot."
	slots[slot] = uid
	_locations[uid] = _location(holder_id, container, slot)
	return ""


func reserve_drop(creator_id: String, owner_id: String, uid: String) -> String:
	if not authorized(creator_id) or not has_owner(owner_id) or _world.get_item(uid) == null or _locations.has(uid):
		return "Ground reservations require authority, an owner, and a fresh known UID."
	_locations[uid] = _location(owner_id, "ground", -1)
	return ""


func pickup(creator_id: String, owner_id: String, uid: String) -> String:
	if not authorized(creator_id) or not has_owner(owner_id) or location(uid) != _location(owner_id, "ground", -1):
		return "Pickup requires a ground UID reserved for this owner."
	var slots: Array = _owners[owner_id].bag
	var slot: int = slots.find("")
	if slot < 0:
		return "Inventory is full."
	slots[slot] = uid
	_locations[uid] = _location(owner_id, "bag", slot)
	return ""


func move(creator_id: String, owner_id: String, source: String, source_slot: int, destination: String, destination_slot: int, uid: String) -> String:
	if not authorized(creator_id) or not has_owner(owner_id) or source not in ["bag", "stash"] or destination not in ["bag", "stash"]:
		return "Moves require authority and this owner's bag or stash."
	return _transfer(owner_id, source, source_slot, owner_id, destination, destination_slot, uid)


func buy(creator_id: String, owner_id: String, vendor_id: String, stock_slot: int, bag_slot: int, uid: String) -> String:
	return _trade(creator_id, owner_id, vendor_id, stock_slot, bag_slot, uid, true)


func sell(creator_id: String, owner_id: String, vendor_id: String, bag_slot: int, stock_slot: int, uid: String) -> String:
	return _trade(creator_id, owner_id, vendor_id, stock_slot, bag_slot, uid, false)


func configure_equipment(creator_id: String, owner_id: String, registry: Variant, base_modifiers: Array = [], set_bonuses: Array = []) -> String:
	if not authorized(creator_id) or not has_owner(owner_id) or _equipment.has(owner_id):
		return "Equipment requires authority and an owner without configured equipment."
	var gear := Equipment.new()
	var error: String = gear.configure(_world, registry, base_modifiers, set_bonuses)
	if not error.is_empty():
		return error
	_equipment[owner_id] = gear
	return ""


func equip(creator_id: String, owner_id: String, changes: Dictionary, tick: int, conditions: PackedStringArray = PackedStringArray()) -> String:
	if not authorized(creator_id) or not _equipment.has(owner_id):
		return "Equipment transaction requires authority and configured owner equipment."
	var gear: RefCounted = _equipment[owner_id]
	var old: Dictionary = gear.snapshot().slots
	var target: Dictionary = old.duplicate()
	for slot: Variant in changes:
		if not slot is String or not Equipment.SLOTS.has(slot) or not changes[slot] is String:
			return "Equipment requires known slots and string UIDs."
		target[slot] = changes[slot]
	var bag: Array = _owners[owner_id].bag.duplicate()
	var seen: Dictionary = {}
	for uid: String in target.values():
		if uid.is_empty():
			continue
		if seen.has(uid):
			return "Equipment UIDs must be distinct."
		seen[uid] = true
		if old.values().has(uid):
			continue
		var position: int = bag.find(uid)
		if position < 0:
			return "Incoming equipment must be in the owner's bag."
		bag[position] = ""
	for uid: String in old.values():
		if uid.is_empty() or target.values().has(uid):
			continue
		var position: int = bag.find("")
		if position < 0:
			return "Displaced equipment does not fit in the bag."
		bag[position] = uid
	var result: Dictionary = gear.transact(changes, tick, conditions)
	if not result.error.is_empty():
		return result.error
	_owners[owner_id].bag = bag
	for index in bag.size():
		if not bag[index].is_empty():
			_locations[bag[index]] = _location(owner_id, "bag", index)
	for slot: String in Equipment.SLOTS:
		if not target[slot].is_empty():
			_locations[target[slot]] = {"holder_id": owner_id, "container": "equipment", "slot": slot}
	return ""


func equipment_stats(owner_id: String) -> RefCounted:
	return _equipment[owner_id].stats() if _equipment.has(owner_id) else null


func location(uid: String) -> Dictionary:
	return _locations.get(uid, {}).duplicate()


func container_slots(holder_id: String, container: String) -> Array:
	return _container(holder_id, container).duplicate()


func bag_items(owner_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	for uid: String in _container(owner_id, "bag"):
		if not uid.is_empty():
			result.append(uid)
	return result


func snapshot() -> Dictionary:
	var equipment: Dictionary = {}
	for owner: String in _equipment:
		equipment[owner] = _equipment[owner].snapshot()
	return {"schema_version": 1, "creator_id": _creator, "owners": _owners.duplicate(true), "vendors": _vendors.duplicate(true), "locations": _locations.duplicate(true), "equipment": equipment}


func _trade(creator_id: String, owner_id: String, vendor_id: String, stock_slot: int, bag_slot: int, uid: String, buying: bool) -> String:
	if not authorized(creator_id) or not has_owner(owner_id) or not _vendors.has(vendor_id):
		return "Trade requires authority, owner, and vendor."
	var item: RefCounted = _world.get_item(uid)
	if item == null or not _vendors[vendor_id].prices.has(item.definition_id()):
		return "Vendor does not trade this item definition."
	var price: Dictionary = _vendors[vendor_id].prices[item.definition_id()]
	var amount: int = price.buy if buying else price.sell
	var balance: int = _owners[owner_id].currency
	if (buying and balance < amount) or (not buying and balance > MAX_CURRENCY - amount):
		return "Insufficient currency or currency overflow."
	var error: String
	if buying:
		error = _transfer(vendor_id, "stock", stock_slot, owner_id, "bag", bag_slot, uid)
	else:
		error = _transfer(owner_id, "bag", bag_slot, vendor_id, "stock", stock_slot, uid)
	if not error.is_empty():
		return error
	_owners[owner_id].currency = balance - amount if buying else balance + amount
	return ""


func _transfer(source_id: String, source: String, source_slot: int, destination_id: String, destination: String, destination_slot: int, uid: String) -> String:
	var from: Array = _container(source_id, source)
	var to: Array = _container(destination_id, destination)
	if uid.is_empty() or source_slot < 0 or source_slot >= from.size() or from[source_slot] != uid or location(uid) != _location(source_id, source, source_slot):
		return "Stale UID or invalid source slot."
	if not _empty_slot(to, destination_slot):
		return "Invalid or occupied destination slot."
	from[source_slot] = ""
	to[destination_slot] = uid
	_locations[uid] = _location(destination_id, destination, destination_slot)
	return ""


func _container(holder_id: String, container: String) -> Array:
	if container in ["bag", "stash"] and has_owner(holder_id):
		return _owners[holder_id][container]
	if container == "stock" and _vendors.has(holder_id):
		return _vendors[holder_id].stock
	return []


static func _location(holder_id: String, container: String, slot: int) -> Dictionary:
	return {"holder_id": holder_id, "container": container, "slot": slot}


static func _empty_slot(slots: Array, slot: int) -> bool:
	return slot >= 0 and slot < slots.size() and slots[slot].is_empty()


static func _slots(capacity: int) -> Array:
	var slots: Array = []
	slots.resize(capacity)
	slots.fill("")
	return slots


static func _capacity(value: int) -> bool:
	return value >= 0 and value <= 10000


static func _money(value: Variant) -> bool:
	return Instance._integer(value, 0) and value <= MAX_CURRENCY


static func _id(value: String) -> bool:
	return value.length() <= 128 and Id.is_valid(value)
