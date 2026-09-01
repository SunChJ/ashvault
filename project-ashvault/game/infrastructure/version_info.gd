class_name VersionInfo
extends RefCounted

const CONTENT_VERSION := 1
const SIMULATION_VERSION := 1
const SAVE_SCHEMA_VERSION := 1


static func snapshot() -> Dictionary[String, int]:
	return {
		"content_version": CONTENT_VERSION,
		"simulation_version": SIMULATION_VERSION,
		"save_schema_version": SAVE_SCHEMA_VERSION,
	}
