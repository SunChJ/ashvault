class_name ItemWorld
extends RefCounted

const Catalog = preload("res://game/simulation/items/item_catalog.gd")
const Instance = preload("res://game/simulation/items/item_instance.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")
const MAX_SEQUENCE := 9223372036854775807
const SNAPSHOT_FIELDS := ["schema_version", "namespace", "next_sequence", "items"]

var _catalog: RefCounted
var _namespace := ""
var _next_sequence := 1
var _items: Dictionary = {}
var _used := false


func configure(namespace_value: String, catalog: Variant) -> String:
	if _catalog != null:
		return "Item world is already configured."
	if not StableIdContract.is_valid(namespace_value) or namespace_value.length() > 128:
		return "Item UID namespace must be a stable ID of at most 128 characters."
	if not catalog is Catalog or not catalog.is_loaded():
		return "Item world requires a published ItemCatalog."
	_namespace = namespace_value
	_catalog = catalog
	return ""


func get_item(uid_value: String) -> RefCounted:
	return _items.get(uid_value)


func create_item(definition_id: String, fields: Dictionary = {}) -> Dictionary:
	if _catalog == null:
		return _failure("Item world is not configured.")
	var definition: Resource = _catalog.get_definition(definition_id)
	if definition == null:
		return _failure("Unknown item definition '%s'." % definition_id)
	if _next_sequence == MAX_SEQUENCE:
		return _failure("Item UID sequence is exhausted.")
	for field: Variant in fields:
		if not Instance.DEFAULTS.has(field):
			return _failure("Unknown or caller-owned identity field in item payload.")
	var record: Dictionary = Instance.DEFAULTS.duplicate(true)
	record.merge(fields, true)
	record.uid = "%s:%d" % [_namespace, _next_sequence]
	record.definition_id = definition_id
	var error := Instance.validation_error(record, definition)
	if not error.is_empty():
		return _failure(error)
	var item := Instance.new()
	item._initialize(record)
	_items[item.uid()] = item
	_next_sequence += 1
	_used = true
	return {"item": item, "error": ""}


func copy_item(source_uid: String) -> Dictionary:
	var source: RefCounted = get_item(source_uid)
	if source == null:
		return _failure("Cannot copy an unknown item UID.")
	var fields: Dictionary = source.snapshot()
	fields.erase("uid")
	fields.erase("definition_id")
	return create_item(source.definition_id(), fields)


func snapshot() -> Dictionary:
	if _catalog == null:
		return {}
	var records: Array = []
	# Allocation order is preserved in snapshots and validated during restore.
	for item: RefCounted in _items.values():
		records.append(item.snapshot())
	return {"schema_version": 1, "namespace": _namespace, "next_sequence": str(_next_sequence), "items": records}


func restore(value: Variant) -> String:
	if _catalog == null or _used:
		return "Item restore requires a configured, unused world."
	if not value is Dictionary or value.size() != SNAPSHOT_FIELDS.size() or not value.has_all(SNAPSHOT_FIELDS):
		return "Item world snapshot has unexpected or missing fields."
	if not Instance._integer(value.schema_version, 1) or value.schema_version != 1:
		return "Unsupported item world snapshot version."
	if not value.namespace is String or value.namespace != _namespace or not value.items is Array:
		return "Item world namespace or records are invalid."
	var next := _parse_sequence(value.next_sequence)
	if next < 1:
		return "Item world next_sequence must be a positive canonical decimal string."
	var staged: Dictionary = {}
	var previous := 0
	for record: Variant in value.items:
		if not record is Dictionary or not record.get("definition_id") is String or not record.get("uid") is String:
			return "Item record requires string identity fields."
		var definition: Resource = _catalog.get_definition(record.definition_id)
		if definition == null:
			return "Item record references an unknown definition."
		var error := Instance.validation_error(record, definition)
		if not error.is_empty():
			return error
		var prefix := _namespace + ":"
		if not record.uid.begins_with(prefix):
			return "Item UID belongs to a different namespace."
		var sequence := _parse_sequence(record.uid.substr(prefix.length()))
		if sequence <= previous or sequence >= next:
			return "Item UIDs must be unique, ordered, and below next_sequence."
		previous = sequence
		var item := Instance.new()
		item._initialize(record)
		staged[item.uid()] = item
	_items = staged
	_next_sequence = next
	_used = true
	return ""


static func _parse_sequence(value: Variant) -> int:
	if not value is String or value.is_empty() or value.length() > 19 or not value.is_valid_int():
		return -1
	if value.length() == 19 and value > str(MAX_SEQUENCE):
		return -1
	var parsed: int = value.to_int()
	return parsed if parsed > 0 and str(parsed) == value else -1


static func _failure(error: String) -> Dictionary:
	return {"item": null, "error": error}
