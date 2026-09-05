extends SceneTree

const Hud = preload("res://game/presentation/hud/combat_hud.tscn")
const Model = preload("res://game/presentation/hud/combat_hud_model.gd")
const Catalog = preload("res://game/simulation/abilities/stormweaver_catalog.gd")
const Entity = preload("res://game/simulation/entities/entity_state.gd")
const World = preload("res://game/simulation/entities/entity_world.gd")
const Command = preload("res://game/simulation/commands/player_command.gd")

var failures: Array[String] = []
var _viewport: SubViewport
var _hud: Control
var _catalog: RefCounted


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_catalog = Catalog.new()
	_check(_catalog.configure().is_empty(), "Catalog must configure.")
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var background := ColorRect.new()
	background.color = Color("0b141c")
	background.size = Vector2(1920, 1080)
	_viewport.add_child(background)
	_hud = Hud.instantiate()
	_viewport.add_child(_hud)
	_check(_hud.configure(_catalog.loadout()).is_empty(), "HUD must configure.")
	await process_frame
	for state in ["normal", "unavailable", "casting", "cooldown", "status"]:
		var world := _fixture(state)
		var records: Array = []
		if state == "status":
			records = [[1, Catalog.SHOCK, 2, 3, 280, 1], [1, Catalog.WARD, 1, 1, 340, 2],
				[2, Catalog.WARD, 2, 1, 340, 3], [1, Catalog.INVULNERABLE, 1, 1, 100, 4]]
		var hash_before: String = world.state_hash()
		_check(_hud.present(world.presentation_snapshot(), 1, records).is_empty(), "HUD must accept a snapshot.")
		await process_frame
		await process_frame
		_check(world.state_hash() == hash_before, "HUD must not mutate simulation state.")
		var view: Dictionary = _hud.view_state()
		_check(view.slots.size() == 6, "HUD must represent six slots.")
		_check(view.health == 720 and view.max_health == 1000, "Health values must match snapshot.")
		match state:
			"normal":
				_check(view.slots[0].state == "Ready", "Normal ability must be ready.")
				_check(view.slots[0].binding == "LMB" and view.slots[5].binding == "Space", "Default bindings must match InputMap.")
			"unavailable":
				_check(view.slots[0].state == "Low mana", "Insufficient mana must show unavailable feedback.")
			"casting":
				_check(view.slots[4].state == "Casting" and view.cast_progress > 0.0 and view.cast_progress < 1.0, "Casting must show partial progress.")
				_check(view.slots[0].state == "Busy" and view.slots[5].state == "Ready", "Dash replacement must remain available while casting.")
			"cooldown":
				_check(view.slots[3].cooldown_ticks == 299, "Cooldown must use snapshot tick time.")
				_check(view.slots[3].state == "5.0s", "Cooldown must show remaining seconds.")
			"status":
				_check(view.statuses.size() == 2 and view.statuses[0].stacks == 3, "Statuses must filter other actors and expired effects.")
		for control in _hud.get_node("%Abilities").get_children():
			_check(is_equal_approx(control.size.x, 200.0), "Ability slot width must remain stable across states.")
		_check_layout(_hud)
		await _capture(state)
	_test_remapping()
	_test_cooldown_boundary()
	var missing := _fixture("normal")
	_check(_hud.present(missing.presentation_snapshot(), 99).is_empty() and not _hud.visible, "Missing actor must clear and hide stale HUD.")
	_viewport.queue_free()
	await process_frame
	if failures.is_empty():
		print("Production combat HUD fixtures passed (1920x1080).")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _fixture(state: String) -> RefCounted:
	var entity := Entity.new()
	_check(entity.configure(1, "actor.stormweaver", true, Vector2.ZERO, 720, 1000,
		1.0 if state == "unavailable" else 40.0, 100.0).is_empty(), "Fixture entity must configure.")
	var world := World.new()
	_check(world.configure([entity], 100, null, {1: _catalog.loadout()}).is_empty(), "Fixture world must configure.")
	if state == "casting":
		_check(world.advance_tick([_command(101, Command.CAST_START, 4, 1)]).is_success(), "Cast start must commit.")
		for tick in 3:
			_check(world.advance_tick([]).is_success(), "Cast progress must advance.")
	elif state == "cooldown":
		_check(world.advance_tick([_command(101, Command.CAST_START, 3, 1),
			_command(101, Command.CAST_RELEASE, 3, 2)]).is_success(), "Ward cast must commit.")
		_check(world.advance_tick([]).is_success(), "Cooldown must advance.")
	return world


func _command(tick: int, type: String, slot: int, sequence: int) -> RefCounted:
	var command := Command.new()
	_check(command.configure(tick, 1, type, Vector2.RIGHT, slot, sequence).is_empty(), "Command must configure.")
	return command


func _test_remapping() -> void:
	var original: Array[InputEvent] = InputMap.action_get_events(Model.ACTIONS[0])
	InputMap.action_erase_events(Model.ACTIONS[0])
	_check(Model.binding_label(Model.ACTIONS[0]) == "Unbound", "Missing binding must be explicit.")
	var unbound := _fixture("normal")
	_check(_hud.present(unbound.presentation_snapshot(), 1).is_empty(), "Unbound snapshot must present.")
	_check(_hud.view_state().slots[0].state == "Unbound", "Unbound slot must be unavailable.")
	_check(_hud.view_state().statuses.is_empty(), "Removed statuses must not linger in the HUD.")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.ctrl_pressed = true
	InputMap.action_add_event(Model.ACTIONS[0], event)
	_check(Model.binding_label(Model.ACTIONS[0]).contains("Ctrl") and Model.binding_label(Model.ACTIONS[0]).contains("F"), "Remapped key modifiers must be visible.")
	var world := _fixture("normal")
	_check(_hud.present(world.presentation_snapshot(), 1).is_empty(), "Remapped snapshot must present.")
	_check(_hud.view_state().slots[0].binding.contains("F"), "HUD must refresh remapped labels.")
	InputMap.action_erase_events(Model.ACTIONS[0])
	for value: InputEvent in original:
		InputMap.action_add_event(Model.ACTIONS[0], value)


func _test_cooldown_boundary() -> void:
	var world := _fixture("cooldown")
	while world.tick() < 400:
		_check(world.advance_tick([]).is_success(), "Cooldown fixture must advance.")
	_check(_hud.present(world.presentation_snapshot(), 1).is_empty(), "Last cooldown tick must present.")
	_check(_hud.view_state().slots[3].state == "0.1s", "Positive cooldown must not display zero seconds.")
	_check(world.advance_tick([]).is_success(), "Cooldown expiry must commit.")
	_check(_hud.present(world.presentation_snapshot(), 1).is_empty(), "Expired cooldown must present.")
	_check(_hud.view_state().slots[3].state == "Ready", "Cooldown must become ready on its exact expiry tick.")


func _check_layout(node: Node) -> void:
	if node is Control and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		_check(Rect2(0, 0, 1920, 1080).encloses(rect), "HUD control must fit 1080p: %s %s" % [node.name, rect])
		if node is Label:
			_check(node.size.x >= node.get_minimum_size().x, "Label must not clip: %s" % node.name)
	for child in node.get_children():
		_check_layout(child)


func _capture(state: String) -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture-dir")
	if index < 0 or index + 1 >= args.size():
		return
	await RenderingServer.frame_post_draw
	var directory: String = args[index + 1]
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Capture directory must be writable.")
	var error := _viewport.get_texture().get_image().save_png(directory.path_join("%s.png" % state))
	_check(error == OK, "HUD screenshot must save.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
