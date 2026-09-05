class_name SaveJson
extends RefCounted

const MAX_BYTES := 16777216
const MAX_VALUES := 500000


static func validate(value: Variant, depth: int = 0, budget: Array = [MAX_VALUES]) -> String:
	budget[0] -= 1
	if depth > 32 or budget[0] < 0:
		return "Save exceeds JSON nesting or value budget."
	if value == null or value is bool:
		return ""
	if value is String:
		return "" if value.length() <= MAX_BYTES else "Save string is too large."
	if value is int or value is float:
		return "" if is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0 else "Save number is not finite or JSON-safe."
	if value is Dictionary:
		var keys: Dictionary = {}
		for key: Variant in value:
			if not (key is String or key is StringName) or str(key).length() > 4096:
				return "Save objects require bounded string keys: %s (%s)." % [str(key), type_string(typeof(key))]
			if keys.has(str(key)):
				return "Duplicate normalized save key."
			keys[str(key)] = true
			var error := validate(value[key], depth + 1, budget)
			if not error.is_empty():
				return error
		return ""
	if value is Array:
		for entry: Variant in value:
			var error := validate(entry, depth + 1, budget)
			if not error.is_empty():
				return error
		return ""
	return "Save contains a non-JSON engine value."


static func encode(value: Dictionary) -> Dictionary:
	var error := validate(value, 0, [MAX_VALUES])
	if not error.is_empty():
		return {"error": error}
	var payload := JSON.stringify(plain_keys(value), "", true, true)
	var encoded := JSON.stringify({"format": "ashvault.save", "checksum": payload.sha256_text(), "payload": payload})
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return {"error": "Save exceeds the 16 MiB limit."}
	return {"error": "", "text": encoded}


static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"error": "Save exceeds the 16 MiB limit."}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"error": "Malformed save envelope JSON."}
	var envelope: Variant = parser.data
	if not envelope is Dictionary or envelope.size() != 3 or not envelope.has_all(["format", "checksum", "payload"]) or envelope.format != "ashvault.save" or not envelope.payload is String or not envelope.checksum is String:
		return {"error": "Invalid save envelope fields."}
	if envelope.checksum != envelope.payload.sha256_text():
		return {"error": "Save checksum mismatch."}
	if parser.parse(envelope.payload) != OK or not parser.data is Dictionary:
		return {"error": "Malformed save payload JSON."}
	var error := validate(parser.data, 0, [MAX_VALUES])
	return {"error": error, "dto": parser.data if error.is_empty() else {}}


static func plain_keys(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[str(key)] = plain_keys(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(plain_keys(entry))
		return result
	return value
