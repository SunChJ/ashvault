extends SceneTree

const Fixture = preload("res://game/infrastructure/arena/combat_arena_fixture.gd")
const Feedback = preload("res://game/presentation/combat/combat_feedback.gd")
const Adapter = preload("res://game/presentation/input/keyboard_mouse_command_adapter.gd")

const REPLAY_HASHES := {12: "c698e353b88a959a52aa8e7cf1bb16f751bb04b9b7579f36f273c5f075944396",
	120: "23fea8f5e12e409f49d2da5b6d5db687eb04b31c6ae652c7d6213c5a457ff8c6"}

var failures: Array[String] = []
var cues: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var feedback := Feedback.new()
	root.add_child(feedback)
	feedback.cue_played.connect(func(kind: String) -> void: cues[kind] = true)
	await process_frame
	for count in [12, 120]:
		var enabled := _replay(count, feedback)
		feedback.presentation_enabled = false
		var disabled := _replay(count, feedback)
		_check(enabled == disabled, "Presentation must not alter the %d-enemy replay." % count)
		_check(enabled == REPLAY_HASHES[count], "Desktop replay hash must match the shared fixture.")
		feedback.presentation_enabled = true
		print(JSON.stringify({"fixture": "combat_feedback", "enemies": count, "ticks": 480, "state_hash": enabled}))
	for kind: String in Feedback.SKILL_CUES:
		_check(cues.has(kind), "Showcase must cover ability cue: %s" % kind)
	for kind: String in ["hit", "critical", "shock", "death", "protected", "hurt"]:
		_check(cues.has(kind), "Showcase must cover hit/status cue: %s" % kind)
	feedback.show_telegraph(Vector2.ZERO, Vector2.RIGHT)
	_check(cues.has("telegraph"), "Elite warning cue must emit.")
	for index in 300:
		feedback.add_cue("hit", Vector2(index, 0))
	_check(feedback.effect_count() <= Feedback.MAX_EFFECTS, "Transient effects must respect the cap.")
	_check(feedback.active_voice_count() <= Feedback.MAX_VOICES, "Audio voices must respect the cap.")
	feedback.add_cue("nova", Vector2.ZERO)
	feedback.set_camera_intensity(0)
	_check(feedback.camera_offset() == Vector2.ZERO, "Zero intensity must eliminate camera motion immediately.")
	feedback.set_camera_intensity(10)
	_check(feedback.camera_offset().length() <= sqrt(2.0) * 8.0, "Camera intensity and displacement must be bounded.")
	feedback.advance_visuals(5.0)
	_check(feedback.effect_count() == 0 and feedback.camera_offset() == Vector2.ZERO, "Expired feedback must retire.")
	for name: String in Feedback.SOUNDS:
		var sound: AudioStreamWAV = Feedback.SOUNDS[name]
		_check(sound.get_length() > 0.05 and sound.get_length() < 0.6, "Sound duration must be bounded: %s" % name)
	_test_input_lifecycle()
	# Flush deferred playback starts before testing immediate mute and teardown.
	await process_frame
	await process_frame
	feedback.set_audio_enabled(false)
	_check(feedback.active_voice_count() == 0, "Muting must stop active voices immediately.")
	feedback.queue_free()
	await create_timer(0.05).timeout
	if failures.is_empty():
		print("Production combat feedback tests passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _replay(count: int, feedback: Node2D) -> String:
	var fixture := Fixture.create(count)
	_check(fixture.error.is_empty(), "Arena fixture must configure.")
	var combat: RefCounted = fixture.combat
	var input := Adapter.new()
	_check(input.configure(1).is_empty(), "Input adapter must configure.")
	for tick in range(1, 481):
		var actor: RefCounted = combat.presentation_snapshot().entity(1)
		var sample: Dictionary = input.combat_commands_from_sample(tick, actor, fixture.catalog.loadout(),
			Vector2.ZERO, actor.position() + Vector2.RIGHT * 100.0, Fixture.showcase_slots(tick))
		_check(sample.error.is_empty(), "Showcase input must be valid.")
		var error: String = combat.advance_tick(sample.commands)
		if not error.is_empty():
			_check(false, "Showcase tick %d failed: %s" % [tick, error])
			break
		feedback.present(combat.presentation_snapshot(), combat.report())
		feedback.advance_visuals(1.0 / 60.0)
		_check(feedback.effect_count() <= Feedback.MAX_EFFECTS, "Density effects must remain bounded.")
	input.free()
	return combat.state_hash()


func _test_input_lifecycle() -> void:
	var fixture := Fixture.create()
	var combat: RefCounted = fixture.combat
	var input := Adapter.new()
	_check(input.configure(1).is_empty(), "Lifecycle adapter must configure.")
	for tick in range(1, 50):
		var slots: Array = [4] if tick == 1 else ([5] if tick == 3 else [])
		var movement := Vector2.RIGHT if tick >= 2 else Vector2.ZERO
		var actor: RefCounted = combat.presentation_snapshot().entity(1)
		var result: Dictionary = input.combat_commands_from_sample(tick, actor, fixture.catalog.loadout(), movement, Vector2(500, 0), slots)
		_check(result.error.is_empty(), "Lifecycle sample must configure.")
		var error: String = combat.advance_tick(result.commands)
		_check(error.is_empty(), "Movement cancellation/dash recovery must remain valid: %s" % error)
	_check(combat.entity_state(1).position().x > 150.0, "Held movement must resume after dash recovery.")
	input.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
