extends SceneTree

const Ownership = preload("res://game/simulation/items/inventory_state.gd")
const Fixture = preload("res://tests/fixtures/items/equipment_fixture.gd")
const Loot = preload("res://game/simulation/items/loot_state.gd")
const Table = preload("res://game/simulation/items/loot_table.gd")
const Entry = preload("res://game/simulation/items/loot_entry.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const View = preload("res://game/presentation/items/gloot_inventory_view.gd")
const AUTH := "authority.local"
const OWNER := "actor.player"
const VENDOR := "vendor.smith"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var f: Dictionary = Fixture.create()
	var state := Ownership.new()
	_check(state.configure(f.world, AUTH).is_empty(), "Inventory must configure.")
	_check(state.register_owner(AUTH, OWNER, 2, 1, 100).is_empty(), "Owner must register bag, stash, and currency.")
	state.register_owner(AUTH, "actor.other", 1)
	var prices := {"item.weapon": {"buy": 60, "sell": 20}, "item.off_hand": {"buy": 40, "sell": 10}}
	_check(state.register_vendor(AUTH, VENDOR, 2, prices).is_empty(), "Vendor must register prices and stock slots.")
	prices["item.weapon"].buy = 0
	var weapon: String = f.items["slot.weapon"].uid()
	var offhand: String = f.items["slot.off_hand"].uid()
	_check(state.place_item(AUTH, VENDOR, "stock", 0, weapon).is_empty(), "Setup must claim a stock UID.")
	_check(state.place_item(AUTH, OWNER, "bag", 0, offhand).is_empty(), "Setup must claim a bag UID.")
	var world_before: Dictionary = f.world.snapshot()
	var before: Dictionary = state.snapshot()
	_check(not state.place_item(AUTH, OWNER, "stash", 0, weapon).is_empty(), "A UID cannot be claimed twice.")
	_check(not state.buy(AUTH, OWNER, VENDOR, 0, 0, weapon).is_empty(), "Buying into an occupied slot must fail without charging.")
	_check(not state.buy(AUTH, OWNER, VENDOR, -1, 1, weapon).is_empty(), "Invalid source slot must fail.")
	_check(not state.buy(AUTH, OWNER, VENDOR, 0, 2, weapon).is_empty(), "Invalid destination slot must fail.")
	_check(not state.buy(AUTH, OWNER, VENDOR, 0, 1, "profile.stale:1").is_empty(), "Unknown UID must fail.")
	_check(not state.buy("authority.foreign", OWNER, VENDOR, 0, 1, weapon).is_empty(), "Foreign authority must fail.")
	_check(state.snapshot() == before, "Rejected trades must preserve stock, bag, locations, and currency.")
	_check(state.buy(AUTH, OWNER, VENDOR, 0, 1, weapon).is_empty(), "Buy must transfer the existing UID.")
	_check(state.snapshot().owners[OWNER].currency == 40 and state.location(weapon).container == "bag", "Buy must use the frozen price and update ownership.")
	before = state.snapshot()
	_check(not state.buy(AUTH, OWNER, VENDOR, 0, 1, weapon).is_empty(), "Repeated buy must reject the stale source UID.")
	_check(not state.move(AUTH, "actor.other", "bag", 1, "stash", 0, weapon).is_empty(), "Other owners cannot move this UID.")
	_check(not state.move(AUTH, OWNER, "bag", 1, "stock", 0, weapon).is_empty(), "Moves cannot bypass vendor prices.")
	_check(not state.move(AUTH, OWNER, "bag", 1, "bag", 0, weapon).is_empty(), "Occupied destinations must reject moves.")
	_check(state.snapshot() == before, "Rejected moves must preserve both containers.")
	_check(state.move(AUTH, OWNER, "bag", 1, "stash", 0, weapon).is_empty(), "Bag-to-stash move must succeed.")
	before = state.snapshot()
	_check(not state.move(AUTH, OWNER, "bag", 0, "stash", 0, offhand).is_empty(), "Full stash must reject transfer.")
	_check(not state.sell(AUTH, OWNER, VENDOR, 1, 0, weapon).is_empty(), "A stale bag UID cannot sell a stashed item.")
	_check(state.snapshot() == before, "Full stash and stale sale must roll back.")
	_check(state.move(AUTH, OWNER, "stash", 0, "bag", 1, weapon).is_empty(), "Stash-to-bag move must succeed.")
	_check(state.sell(AUTH, OWNER, VENDOR, 1, 0, weapon).is_empty(), "Sale must transfer the same UID into vendor stock.")
	_check(state.snapshot().owners[OWNER].currency == 60 and state.location(weapon).holder_id == VENDOR, "Sale must credit the authored amount once.")
	before = state.snapshot()
	_check(not state.sell(AUTH, OWNER, VENDOR, 1, 0, weapon).is_empty(), "Repeated sale must not credit currency.")
	_check(state.snapshot() == before, "Duplicate sale must preserve state.")
	_check(state.move(AUTH, OWNER, "bag", 0, "bag", 1, offhand).is_empty(), "Within-bag move must preserve explicit slot indices.")
	_check(not state.resize_bag(AUTH, OWNER, 1).is_empty(), "Shrink must not discard an occupied high slot.")
	_check(state.buy(AUTH, OWNER, VENDOR, 0, 0, weapon).is_empty(), "Exact-balance purchase must succeed.")
	_check(state.snapshot().owners[OWNER].currency == 0, "Exact-balance purchase must reach zero.")
	var view: Array = View.items(state.container_slots(OWNER, "bag"), f.world)
	before = state.snapshot()
	view[0].set_property("uid", "profile.fake:1")
	view[0].set_property("name", "Changed")
	_check(state.snapshot() == before and f.world.get_item(weapon).uid() == weapon, "GLoot view mutation must not alter simulation.")
	var slots: Array = state.container_slots(OWNER, "bag")
	slots.clear()
	var exposed: Dictionary = state.snapshot()
	exposed.owners.clear()
	_check(state.snapshot() == before, "Inventory observations must be defensive copies.")
	_check(f.world.snapshot() == world_before, "Moves and trades must preserve immutable item records and UID allocation.")
	_test_money_and_stock()
	_test_equipment()
	_test_loot()
	print(JSON.stringify({"fixture": "inventory", "locations": state.snapshot().locations, "currency": state.snapshot().owners[OWNER].currency}))
	if failures.is_empty():
		print("Production inventory contracts passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_money_and_stock() -> void:
	var f: Dictionary = Fixture.create()
	var state := Ownership.new()
	state.configure(f.world, AUTH)
	state.register_owner(AUTH, OWNER, 1, 0, Ownership.MAX_CURRENCY)
	state.register_owner(AUTH, "actor.poor", 1, 0, 5)
	state.register_vendor(AUTH, VENDOR, 1, {"item.weapon": {"buy": 60, "sell": 20}})
	var uid: String = f.items["slot.weapon"].uid()
	state.place_item(AUTH, OWNER, "bag", 0, uid)
	var before: Dictionary = state.snapshot()
	_check(not state.sell(AUTH, OWNER, VENDOR, 0, 0, uid).is_empty() and state.snapshot() == before, "Currency overflow must preserve item and balance.")
	var other: String = f.world.copy_item(uid).item.uid()
	state.place_item(AUTH, VENDOR, "stock", 0, other)
	before = state.snapshot()
	_check(not state.buy(AUTH, "actor.poor", VENDOR, 0, 0, other).is_empty(), "Insufficient currency must reject purchase.")
	var poor_uid: String = f.world.copy_item(uid).item.uid()
	state.place_item(AUTH, "actor.poor", "bag", 0, poor_uid)
	before = state.snapshot()
	_check(not state.sell(AUTH, "actor.poor", VENDOR, 0, 0, poor_uid).is_empty(), "Occupied vendor stock must reject sale without crediting currency.")
	_check(state.snapshot() == before, "Rejected stock and currency operations must preserve state.")
	for amount: Variant in [-1, 1.5, NAN, 2147483648, "1"]:
		_check(not state.register_owner(AUTH, "actor.invalid", 1, 1, amount).is_empty(), "Initial currency must be a bounded integer.")
	for price: Dictionary in [{"buy": 1, "sell": 2}, {"buy": -1, "sell": 0}, {"buy": 1.5, "sell": 0}, {"buy": 1}, {"buy": 1, "sell": 0, "extra": 0}]:
		_check(not state.register_vendor(AUTH, "vendor.invalid", 1, {"item.weapon": price}).is_empty(), "Malformed or arbitrage prices must fail publication.")


func _test_equipment() -> void:
	var f: Dictionary = Fixture.create()
	var state := Ownership.new()
	state.configure(f.world, AUTH)
	state.register_owner(AUTH, OWNER, 2)
	state.configure_equipment(AUTH, OWNER, f.registry, [], f.set_bonuses)
	var weapon: String = f.items["slot.weapon"].uid()
	var offhand: String = f.items["slot.off_hand"].uid()
	state.place_item(AUTH, OWNER, "bag", 0, weapon)
	state.place_item(AUTH, OWNER, "bag", 1, offhand)
	_check(state.equip(AUTH, OWNER, {"slot.weapon": weapon, "slot.off_hand": offhand}, 1).is_empty(), "Owned bag items must equip atomically.")
	_check(state.equipment_stats(OWNER).value("stat.power") == 104, "Owned equipment must use the existing stat resolver.")
	state.place_item(AUTH, OWNER, "bag", 0, f.two_handed.uid())
	state.place_item(AUTH, OWNER, "bag", 1, f.invalid_stat.uid())
	var before: Dictionary = state.snapshot()
	var stats: RefCounted = state.equipment_stats(OWNER)
	_check(not state.equip(AUTH, OWNER, {"slot.weapon": f.two_handed.uid(), "slot.off_hand": ""}, 2).is_empty(), "Two displaced items must fit after removing incoming equipment.")
	_check(not state.equip(AUTH, OWNER, {"slot.weapon": f.invalid_stat.uid()}, 2).is_empty(), "Stat resolution failure must roll back bag changes.")
	_check(not state.equip(AUTH, OWNER, {"slot.unknown": weapon}, 2).is_empty(), "Invalid equipment slots must reject.")
	_check(not state.equip(AUTH, OWNER, {"slot.head": f.items["slot.head"].uid()}, 2).is_empty(), "Unowned world items cannot equip.")
	_check(state.snapshot() == before and state.equipment_stats(OWNER) == stats, "Failed equips must retain ownership and immutable stats.")
	state.resize_bag(AUTH, OWNER, 3)
	_check(state.equip(AUTH, OWNER, {"slot.weapon": f.two_handed.uid(), "slot.off_hand": ""}, 2).is_empty(), "Two-hand replacement must succeed with displacement capacity.")
	_check(state.location(weapon).container == "bag" and state.location(offhand).container == "bag" and state.location(f.two_handed.uid()).container == "equipment", "Replacement must update all three locations.")
	_check(state.equipment_stats(OWNER).value("stat.power") == 110, "Replacement must recompute stats.")


func _test_loot() -> void:
	var f: Dictionary = Fixture.create()
	var state := Ownership.new()
	state.configure(f.world, AUTH)
	state.register_owner(AUTH, OWNER, 1, 1)
	var rng := Streams.new()
	rng.initialize(55)
	var entry := Entry.new()
	entry.entry_id = "entry.weapon"
	entry.definition_id = "item.weapon"
	entry.rarity = "white"
	var table := Table.new()
	table.content_id = "loot.weapon"
	table.source_id = "drop_source.fixture"
	table.entries = [entry]
	var loot := Loot.new()
	_check(loot.configure(f.world, rng, AUTH, [table], state).is_empty(), "Loot must share the same ownership ledger.")
	var result: Dictionary = loot.drop(AUTH, "occurrence.first", table.source_id, table.content_id, OWNER, 1)
	var uid: String = result.receipt.item.uid
	_check(state.location(uid).container == "ground", "Drop must reserve its UID in the shared ledger.")
	_check(not state.place_item(AUTH, OWNER, "stash", 0, uid).is_empty(), "Setup cannot claim a reserved ground UID.")
	_check(loot.pickup(AUTH, OWNER, uid).is_empty(), "Pickup must enter the shared inventory.")
	_check(state.move(AUTH, OWNER, "bag", 0, "stash", 0, uid).is_empty(), "Picked-up UID must move directly to stash.")
	_check(not loot.pickup(AUTH, OWNER, uid).is_empty(), "A stashed UID cannot be picked up again.")
	_check(loot.bag_items(OWNER).is_empty() and state.location(uid).container == "stash", "Loot observations must reflect inventory moves.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
