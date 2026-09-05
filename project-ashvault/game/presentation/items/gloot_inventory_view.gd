class_name GlootInventoryView
extends RefCounted

const ViewItem = preload("res://addons/gloot/core/inventory_item.gd")


# Detached display values: GLoot edits never become simulation commands.
static func items(slots: Array, world: RefCounted) -> Array:
	var result: Array = []
	for index in slots.size():
		var uid: String = slots[index]
		if uid.is_empty():
			continue
		var item: RefCounted = world.get_item(uid)
		if item == null:
			continue
		var definition: Resource = world.item_catalog().get_definition(item.definition_id())
		var view := ViewItem.new()
		view.set_property("uid", uid)
		view.set_property("slot_index", index)
		view.set_property("name", definition.display_name)
		view.set_property("definition_id", item.definition_id())
		view.set_property("rarity", item.snapshot().rarity)
		view.set_max_stack_size(1)
		result.append(view)
	return result
