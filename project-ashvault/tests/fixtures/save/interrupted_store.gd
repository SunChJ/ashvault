extends "res://game/infrastructure/save/save_store.gd"

var stop_at := ""


func _continue_after(stage: String) -> bool:
	return stage != stop_at
