class_name SaveStore
extends RefCounted

const Codec = preload("res://game/infrastructure/save/save_game_v1.gd")
const JsonContract = preload("res://game/infrastructure/save/save_json.gd")

var _codec: RefCounted
var _events: Array = []


func configure(codec: RefCounted) -> void:
	_codec = codec


func breadcrumbs() -> Array:
	return _events.duplicate(true)


func load_game(path: String) -> Dictionary:
	_events.clear()
	var primary := _read(path)
	if primary.error.is_empty():
		_event("load_primary", "ok")
		primary.recovered = false
		return primary
	_event("load_primary", primary.error)
	var backup := _read(path + ".bak")
	if backup.error.is_empty():
		_event("recover_backup", "ok")
		backup.recovered = true
		backup.primary_error = primary.error
		return backup
	_event("recover_backup", backup.error)
	return {"error": "Primary: %s Backup: %s" % [primary.error, backup.error]}


func save_game(path: String, dto: Dictionary) -> Dictionary:
	_events.clear()
	if _codec == null or path.is_empty():
		return _failure("validate", "Save store requires a codec and destination.")
	var validated: Dictionary = _codec.reconstruct(dto)
	if not validated.error.is_empty():
		return _failure("validate", validated.error)
	var encoded: Dictionary = JsonContract.encode(dto)
	if not encoded.error.is_empty():
		return _failure("encode", encoded.error)
	var error := _write(path + ".tmp", encoded.text)
	if not error.is_empty():
		return _failure("write_temporary", error)
	var verified := _read(path + ".tmp")
	if not verified.error.is_empty():
		return _failure("verify_temporary", verified.error)
	_event("temporary_ready", "ok")
	if not _continue_after("temporary_ready"):
		return _failure("interrupted", "Stopped after temporary write.")
	var previous := _read(path)
	if previous.error.is_empty():
		error = _replace_backup(path, previous.raw)
		if not error.is_empty():
			return _failure("commit_backup", error)
	elif not _read(path + ".bak").error.is_empty():
		# Seed a recoverable first generation if no validated older generation exists.
		error = _replace_backup(path, encoded.text)
		if not error.is_empty():
			return _failure("commit_backup", error)
	else:
		_event("preserve_backup", previous.error)
	if not _continue_after("backup_ready"):
		return _failure("interrupted", "Stopped before primary replacement.")
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return _failure("commit_primary", "Primary replacement failed.")
	_event("commit_primary", "ok")
	return {"error": ""}


# A test subclass can stop at the two durable boundaries without altering I/O.
func _continue_after(_stage: String) -> bool:
	return true


func _read(path: String) -> Dictionary:
	if _codec == null:
		return {"error": "Save store has no codec."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Save file is unavailable."}
	if file.get_length() > JsonContract.MAX_BYTES:
		file.close()
		return {"error": "Save exceeds the 16 MiB limit."}
	var text := file.get_as_text()
	file.close()
	var decoded := JsonContract.decode(text)
	if not decoded.error.is_empty():
		return decoded
	var migrated := Codec.migrate(decoded.dto)
	if not migrated.error.is_empty():
		return migrated
	var rebuilt: Dictionary = _codec.reconstruct(migrated.dto)
	if not rebuilt.error.is_empty():
		return rebuilt
	rebuilt.dto = migrated.dto
	rebuilt.migrations = migrated.migrations
	rebuilt.raw = text
	return rebuilt


func _write(path: String, text: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Cannot open save destination."
	file.store_string(text)
	file.flush()
	var status := file.get_error()
	file.close()
	return "" if status == OK else "Failed to flush save data."


func _event(stage: String, result: String) -> void:
	_events.append({"stage": stage, "result": result})


func _failure(stage: String, error: String) -> Dictionary:
	_event(stage, error)
	return {"error": error}


func _replace_backup(path: String, text: String) -> String:
	var error := _write(path + ".bak.tmp", text)
	if not error.is_empty():
		return error
	var verified := _read(path + ".bak.tmp")
	if not verified.error.is_empty():
		return verified.error
	if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
		return "Backup replacement failed."
	_event("backup_ready", "ok")
	return ""
