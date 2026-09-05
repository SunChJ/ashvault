extends SceneTree

const Definition = preload("res://game/simulation/items/item_definition.gd")
const Catalog = preload("res://game/simulation/items/item_catalog.gd")
const World = preload("res://game/simulation/items/item_world.gd")
const Affixes = preload("res://game/simulation/items/affix_catalog.gd")
const Tags = preload("res://game/content/tag_registry.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := Catalog.new()
	var affixes := Affixes.new()
	_check(affixes.load_definitions([load("res://tests/fixtures/items/power_affix.tres")]).is_empty(), "Authored affix/tier Resources must publish.")
	var definition := load("res://tests/fixtures/items/training_wand.tres") as Resource
	_check(definition is Definition, "Authored item must load as a native Resource.")
	_check(catalog.load_definitions([definition], Tags.new(), affixes).is_empty(), "Item catalog must publish.")
	definition.display_name = "Changed"
	definition.max_sockets = 100
	definition.content_id = "item.changed"
	_check(definition.display_name == "Training Wand" and definition.max_sockets == 2, "Published item fields must freeze.")
	_check(catalog.get_definition("item.training_wand") == definition and catalog.get_definition("item.missing") == null, "Catalog lookup must use stable IDs.")
	var invalid := Definition.new()
	invalid.content_id = "item.invalid"
	var rejected := Catalog.new()
	_check(not rejected.load_definitions([invalid], Tags.new()).is_empty() and not invalid.is_frozen(), "Invalid publication must remain atomic.")
	var world := World.new()
	_check(world.configure("profile.fixture", catalog).is_empty(), "World must configure.")
	var data := {"item_level": 12, "rarity": "blue", "affixes": ["affix.power"],
		"rolls": [{"affix_id": "affix.power", "tier": 2, "value": 3.123456789012345}],
		"sockets": ["", "rune.spark"], "quality": 5, "metadata": {"origin": {"zone": "zone.test"}}}
	var created: Dictionary = world.create_item("item.training_wand", data)
	_check(created.error.is_empty(), "Valid item must be created.")
	var item: RefCounted = created.item
	_check(world.get_item(item.uid()) == item, "UID lookup must return the published instance.")
	data.metadata.origin.zone = "changed"
	var exposed: Dictionary = item.snapshot()
	exposed.rolls[0].value = 999
	_check(item.snapshot().rolls[0].value == 3.123456789012345 and item.snapshot().metadata.origin.zone == "zone.test", "Inputs and outputs must not alias instance data.")
	var copied: Dictionary = world.copy_item(item.uid())
	_check(copied.error.is_empty() and copied.item.uid() != item.uid(), "Copy must allocate a fresh UID.")
	var copy_data: Dictionary = copied.item.snapshot()
	copy_data.uid = item.uid()
	_check(copy_data == item.snapshot(), "Copy must retain all non-identity fields.")
	for index in 1000:
		var next: Dictionary = world.create_item("item.training_wand")
		_check(next.error.is_empty() and next.item.uid() == "profile.fixture:%d" % (index + 3), "UID sequence must be unique and deterministic.")
	var saved: Dictionary = world.snapshot()
	var restored := World.new()
	_check(restored.configure("profile.fixture", catalog).is_empty(), "Restore world must configure.")
	_check(restored.restore(JSON.parse_string(JSON.stringify(saved, "", true, true))).is_empty(), "JSON round-trip must restore.")
	_check(restored.snapshot() == saved, "Round-trip must preserve exact item data and counter.")
	_check(restored.create_item("item.training_wand").item.uid() == "profile.fixture:1003", "Restored counter must continue beyond all issued UIDs.")
	_check(not restored.restore(saved).is_empty(), "Used world must not rewind UIDs.")
	var baseline: Dictionary = world.snapshot()
	for payload in [{"quality": -1}, {"rarity": "unknown"}, {"sockets": ["", "", ""]},
		{"affixes": ["affix.power", "affix.power"]}, {"rolls": [{"affix_id": "affix.missing", "tier": 1, "value": 1}]},
		{"metadata": {"resource": definition}}, {"metadata": {"nan": NAN}}, {"metadata": {1: "invalid"}},
		{"metadata": {"unsafe": 9007199254740992}}, {"item_level": 1.5}, {"extra": true}, {"uid": "profile.fixture:1"}, {"definition_id": "item.training_wand"}]:
		_check(not world.create_item("item.training_wand", payload).error.is_empty(), "Malformed item payload must fail.")
	_check(not world.create_item("item.missing").error.is_empty(), "Missing definition must fail.")
	_check(not world.copy_item("profile.fixture:99999").error.is_empty(), "Missing copy source must fail.")
	_check(world.snapshot() == baseline, "Failed creation must not consume IDs or mutate items.")
	for mutation in ["duplicate", "counter", "namespace", "unknown", "fraction", "extra"]:
		var broken: Dictionary = saved.duplicate(true)
		match mutation:
			"duplicate": broken.items.append(broken.items[0].duplicate(true))
			"counter": broken.next_sequence = "1"
			"namespace": broken.items[0].uid = "profile.other:1"
			"unknown": broken.items[0].definition_id = "item.missing"
			"fraction": broken.items[0].item_level = 1.25
			"extra": broken.unexpected = true
		var target := World.new()
		target.configure("profile.fixture", catalog)
		var before: Dictionary = target.snapshot()
		_check(not target.restore(broken).is_empty() and target.snapshot() == before, "Invalid restore must publish nothing: %s" % mutation)
	var exhausted := World.new()
	exhausted.configure("profile.fixture", catalog)
	var end: Dictionary = exhausted.snapshot()
	end.next_sequence = "9223372036854775807"
	_check(exhausted.restore(end).is_empty(), "Exhaustion sentinel must round-trip.")
	_check(not exhausted.create_item("item.training_wand").error.is_empty() and exhausted.snapshot() == end, "UID exhaustion must not overflow.")
	for invalid_counter in ["9223372036854775808", "01", "+1", "0", "-1", "1.0", 1]:
		var malformed: Dictionary = saved.duplicate(true)
		malformed.next_sequence = invalid_counter
		var target := World.new()
		target.configure("profile.fixture", catalog)
		_check(not target.restore(malformed).is_empty(), "Noncanonical or overflowing counter must be rejected.")
	var large := World.new()
	large.configure("profile.fixture", catalog)
	var large_save: Dictionary = large.snapshot()
	large_save.next_sequence = "9007199254740993"
	_check(large.restore(JSON.parse_string(JSON.stringify(large_save))).is_empty(), "Counter strings must survive beyond JSON integer precision.")
	_check(large.create_item("item.training_wand").item.uid() == "profile.fixture:9007199254740993", "Large UID allocation must remain exact.")
	var other := World.new()
	other.configure("profile.other", catalog)
	_check(other.create_item("item.training_wand").item.uid() != item.uid(), "Independent persistent namespaces must not collide.")
	var nested: Array = []
	nested.append(nested)
	_check(not world.create_item("item.training_wand", {"metadata": {"cycle": nested}}).error.is_empty(), "Recursive metadata must be rejected before copying.")
	nested.clear()
	print(JSON.stringify({"fixture": "items", "issued": saved.items.size(), "next_sequence": saved.next_sequence}))
	if failures.is_empty():
		print("Production item contracts passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
