extends Node2D

const Fixture = preload("res://game/infrastructure/arena/combat_arena_fixture.gd")
const InputAdapter = preload("res://game/presentation/input/keyboard_mouse_command_adapter.gd")
const HudModel = preload("res://game/presentation/hud/combat_hud_model.gd")

var _combat: RefCounted
var _catalog: RefCounted
var _input: Node
var _showcase := false
var _enemy_count := 0
var _limit := 0
var _capture_tick := 0
var _capture_path := ""
var _finishing := false
var _disabled := false
var _tick_times: Array = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("0b141c"))
	var args := OS.get_cmdline_user_args()
	var enemy_count := int(_argument(args, "--enemies", "12"))
	_enemy_count = enemy_count
	_showcase = args.has("--showcase")
	_disabled = args.has("--presentation-disabled")
	_limit = int(_argument(args, "--ticks", "0"))
	_capture_tick = int(_argument(args, "--capture-tick", "0"))
	_capture_path = _argument(args, "--capture-path", "")
	var fixture := Fixture.create(enemy_count)
	if not fixture.error.is_empty():
		push_error(fixture.error)
		get_tree().quit(1)
		return
	_combat = fixture.combat
	_catalog = fixture.catalog
	_input = InputAdapter.new()
	add_child(_input)
	Fixture.Catalog._checked(_input.configure(1))
	Fixture.Catalog._checked(%CombatHud.configure(_catalog.loadout()))
	%Feedback.presentation_enabled = not _disabled
	%CameraIntensity.value_changed.connect(func(value: float) -> void: %Feedback.set_camera_intensity(value / 100.0))
	%AudioEnabled.toggled.connect(func(value: bool) -> void: %Feedback.set_audio_enabled(value))
	%Encounter.text = "%d enemies  ·  %s" % [enemy_count, "Showcase replay" if _showcase else "Live encounter"]
	if _disabled:
		%Interface.visible = false


func _physics_process(_delta: float) -> void:
	if _combat == null or _finishing:
		return
	var tick: int = _combat.tick() + 1
	var snapshot: RefCounted = _combat.presentation_snapshot()
	var actor: RefCounted = snapshot.entity(1)
	var movement := Vector2.ZERO
	var mouse_position: Vector2 = actor.position() + Vector2.RIGHT * 100.0
	var slots: Array = []
	if _showcase:
		slots = Fixture.showcase_slots(tick)
	else:
		movement = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		# Camera shake must not feed back into authoritative aiming commands.
		mouse_position = get_viewport().get_mouse_position() - Vector2(960, 540) + %Camera.position
		for slot in HudModel.ACTIONS.size():
			if Input.is_action_just_pressed(HudModel.ACTIONS[slot]) and (slot > 1 or get_viewport().gui_get_hovered_control() == null):
				slots.append(slot)
	var sampled: Dictionary = _input.combat_commands_from_sample(tick, actor, _catalog.loadout(), movement, mouse_position, slots)
	if not sampled.error.is_empty():
		push_error(sampled.error)
		get_tree().quit(1)
		return
	var started := Time.get_ticks_usec()
	var error: String = _combat.advance_tick(sampled.commands)
	if _limit > 0:
		_tick_times.append(Time.get_ticks_usec() - started)
	if not error.is_empty():
		push_error(error)
		get_tree().quit(1)
		return
	var report: Dictionary = _combat.report()
	snapshot = _combat.presentation_snapshot()
	if not _disabled:
		var alive := 0
		for entity: RefCounted in snapshot.entities():
			if not entity.is_player_controlled() and entity.is_alive():
				alive += 1
		%Encounter.text = "%d / %d enemies  ·  %s" % [alive, _enemy_count, "Showcase replay" if _showcase else "Live encounter"]
		%Feedback.present(snapshot, report)
		Fixture.Catalog._checked(%CombatHud.present(snapshot, 1, report.statuses))
	if _showcase and tick == 150:
		%Feedback.show_telegraph(Vector2(-120, -80), Vector2(1, 0.3), 1.3)
	if tick == _capture_tick and not _capture_path.is_empty():
		_capture()
	if _limit > 0 and tick >= _limit:
		_finishing = true
		_finish()


func _process(delta: float) -> void:
	%Feedback.advance_visuals(delta)
	%Camera.offset = %Feedback.camera_offset()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F5:
		get_tree().reload_current_scene()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error := image.save_png(_capture_path)
	if error != OK:
		push_error("Could not write arena screenshot: %s" % error)


func _finish() -> void:
	%Feedback.set_audio_enabled(false)
	# Let the audio mixer retire stopped playback before shutting down the tree.
	await get_tree().create_timer(0.05).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	_tick_times.sort()
	print(JSON.stringify({"fixture": "combat_arena", "ticks": _combat.tick(), "state_hash": _combat.state_hash(),
		"presentation_enabled": not _disabled, "simulation_p95_us": _tick_times[floori((_tick_times.size() - 1) * 0.95)]}))
	get_tree().quit(0)


static func _argument(args: PackedStringArray, key: String, fallback: String) -> String:
	var index := args.find(key)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback
