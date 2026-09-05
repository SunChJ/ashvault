class_name CombatFeedback
extends Node2D

signal cue_played(kind: String)

const MAX_EFFECTS := 96
const MAX_VOICES := 8
const COLORS := [Color("79e7ee"), Color("b8a0ff"), Color("89b9ff"), Color("78e3bd"), Color("d1aeff"), Color("f6eeae")]
const SKILL_CUES := ["arc", "chain", "nova", "ward", "totem", "dash"]
const SOUNDS := {
	"arc": preload("res://game/presentation/combat/audio/arc.wav"),
	"chain": preload("res://game/presentation/combat/audio/chain.wav"),
	"nova": preload("res://game/presentation/combat/audio/nova.wav"),
	"ward": preload("res://game/presentation/combat/audio/ward.wav"),
	"totem": preload("res://game/presentation/combat/audio/totem.wav"),
	"dash": preload("res://game/presentation/combat/audio/dash.wav"),
	"hit": preload("res://game/presentation/combat/audio/hit.wav"),
	"critical": preload("res://game/presentation/combat/audio/critical.wav"),
	"shock": preload("res://game/presentation/combat/audio/shock.wav"),
	"death": preload("res://game/presentation/combat/audio/death.wav"),
	"telegraph": preload("res://game/presentation/combat/audio/telegraph.wav"),
	"protected": preload("res://game/presentation/combat/audio/protected.wav"),
	"hurt": preload("res://game/presentation/combat/audio/hurt.wav"),
}

var camera_intensity := 0.5
var audio_enabled := true
var presentation_enabled := true
var _entities: Array = []
var _positions: Dictionary = {}
var _alive: Dictionary = {}
var _statuses: Array = []
var _deliveries: Array = []
var _effects: Array = []
var _voices: Array[AudioStreamPlayer] = []
var _last_sound: Dictionary = {}
var _time := 0.0
var _shake := 0.0
var _last_tick := -1
var _telegraph: Dictionary = {}
var _frame_cues: Dictionary = {}


func _ready() -> void:
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -18.0
		add_child(voice)
		_voices.append(voice)


func set_camera_intensity(value: float) -> void:
	camera_intensity = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


func camera_offset() -> Vector2:
	return Vector2(sin(_time * 71.0), cos(_time * 53.0)) * _shake * camera_intensity


func effect_count() -> int:
	return _effects.size()


func active_voice_count() -> int:
	var count := 0
	for voice in _voices:
		if voice.playing:
			count += 1
	return count


func present(snapshot: RefCounted, report: Dictionary) -> void:
	visible = presentation_enabled
	if not presentation_enabled:
		_effects.clear()
		_shake = 0.0
		for voice in _voices:
			voice.stop()
		return
	_entities = snapshot.entities()
	_positions.clear()
	_alive.clear()
	for entity: RefCounted in _entities:
		_positions[entity.runtime_id()] = entity.position()
		_alive[entity.runtime_id()] = entity.is_alive()
	_statuses = report.get("statuses", []).duplicate(true)
	_deliveries = report.get("deliveries", []).duplicate(true)
	if snapshot.tick() == _last_tick:
		queue_redraw()
		return
	_last_tick = snapshot.tick()
	_frame_cues.clear()
	var player: RefCounted = snapshot.entity(1)
	var slot: int = report.get("released_slot", -1)
	if slot >= 0 and player != null:
		add_cue(SKILL_CUES[slot], player.position(), player.position() + player.aim_direction() * 100.0)
	for hit: Array in report.get("hits", []):
		if hit[3] == "delivery.chain_lightning":
			var from: Vector2 = _positions.get(hit[5], Vector2.ZERO)
			# The ordered chain connects each impact to the preceding impact.
			if hit[9] > 0:
				for prior: Array in report.hits:
					if prior[1] == hit[1] and prior[9] == hit[9] - 1:
						from = Vector2(prior[7], prior[8])
			add_cue("chain", from, Vector2(hit[7], hit[8]))
	for damage: Array in report.get("damage", []):
		var kind := "hit"
		if damage[2] == 0:
			kind = "protected"
		elif damage[3]:
			kind = "critical"
		elif damage[1] == 1:
			kind = "hurt"
		var key := "%s:%s" % [kind, damage[1]]
		if not _frame_cues.has(key):
			_frame_cues[key] = true
			add_cue(kind, _positions.get(damage[1], Vector2.ZERO), Vector2.ZERO, damage[2])
	for event: Array in report.get("events", []):
		if event[0] == "event.kill":
			add_cue("death", _positions.get(event[2], Vector2.ZERO))
		elif event[0] == "event.status_applied":
			for status: Array in _statuses:
				if status[0] == event[2] and status[1] == "status.shocked":
					add_cue("shock", _positions.get(event[2], Vector2.ZERO))
	queue_redraw()


func add_cue(kind: String, position: Vector2, destination: Vector2 = Vector2.ZERO, amount: int = 0) -> void:
	if not presentation_enabled or not SOUNDS.has(kind):
		return
	if _effects.size() >= MAX_EFFECTS:
		var expendable := -1
		for index in _effects.size():
			if not _priority(_effects[index].kind):
				expendable = index
				break
		if expendable >= 0:
			_effects.remove_at(expendable)
		elif _priority(kind):
			_effects.pop_front()
		else:
			return
	_effects.append({"kind": kind, "position": position, "destination": destination,
		"amount": amount, "age": 0.0, "duration": 0.55 if kind in SKILL_CUES else 0.3})
	if kind in ["critical", "nova", "hurt", "death"]:
		_shake = maxf(_shake, 8.0 if kind == "nova" else 4.0)
	cue_played.emit(kind)
	_play_sound(kind)


func show_telegraph(position: Vector2, direction: Vector2, duration: float = 1.0) -> void:
	if not presentation_enabled or not position.is_finite() or direction.is_zero_approx() or duration <= 0.0:
		return
	_telegraph = {"position": position, "direction": direction.normalized(), "remaining": duration, "duration": duration}
	cue_played.emit("telegraph")
	_play_sound("telegraph")


func advance_visuals(delta: float) -> void:
	_time += delta
	_shake = maxf(0.0, _shake - delta * 24.0)
	for effect: Dictionary in _effects:
		effect.age += delta
	_effects = _effects.filter(func(effect: Dictionary) -> bool: return effect.age < effect.duration)
	if not _telegraph.is_empty():
		_telegraph.remaining -= delta
		if _telegraph.remaining <= 0.0:
			_telegraph.clear()
	queue_redraw()


func _play_sound(kind: String) -> void:
	if not audio_enabled or _time - float(_last_sound.get(kind, -10.0)) < 0.08:
		return
	for voice in _voices:
		if not voice.playing:
			voice.stream = SOUNDS[kind]
			voice.play()
			_last_sound[kind] = _time
			return


func _draw() -> void:
	if not presentation_enabled:
		return
	draw_rect(Rect2(-820, -380, 1640, 650), Color("12212b"))
	for x in range(-800, 821, 80):
		draw_line(Vector2(x, -380), Vector2(x, 270), Color("1b2e39"), 1.0)
	for y in range(-350, 271, 80):
		draw_line(Vector2(-820, y), Vector2(820, y), Color("1b2e39"), 1.0)
	draw_rect(Rect2(-820, -380, 1640, 650), Color("496171"), false, 2.0)
	for value: Array in _deliveries:
		var position := Vector2(value[6], value[7])
		if value[3] == 0:
			var direction := Vector2(value[8], value[9])
			draw_line(position - direction * 22.0, position, COLORS[0], 5.0, true)
			draw_circle(position, 5.0, Color.WHITE)
		elif value[3] == 3:
			draw_colored_polygon(PackedVector2Array([position + Vector2(0, -18), position + Vector2(12, 10), position + Vector2(-12, 10)]), COLORS[4])
			draw_arc(position, 150, 0, TAU, 64, Color(0.7, 0.5, 1.0, 0.18), 1.0, true)
	for entity: RefCounted in _entities:
		if entity.is_player_controlled() or not entity.is_alive():
			continue
		var position: Vector2 = entity.position()
		draw_circle(position + Vector2(0, 3), 10, Color("071017"))
		draw_circle(position, 7, Color("d77e78"))
		draw_arc(position, 10, -PI * 0.5, -PI * 0.5 + TAU * float(entity.health()) / entity.max_health(), 16, Color("f3b4a3"), 2.0, true)
	for status: Array in _statuses:
		if not _alive.get(status[0], false):
			continue
		var position: Vector2 = _positions.get(status[0], Vector2.ZERO)
		if status[1] == "status.shocked":
			draw_polyline(PackedVector2Array([position + Vector2(-4, -25), position + Vector2(2, -19), position + Vector2(-2, -16), position + Vector2(4, -11)]), Color("f5df80"), 2.0, true)
		elif status[1] == "status.static_ward":
			draw_arc(position, 27, 0, TAU, 40, COLORS[3], 3.0, true)
		elif status[1] == "status.tempest_guard":
			draw_arc(position, 20, 0, TAU, 6, COLORS[5], 3.0, true)
	for effect: Dictionary in _effects:
		_draw_effect(effect)
	if not _telegraph.is_empty():
		var center: Vector2 = _telegraph.position
		var facing: Vector2 = _telegraph.direction
		var points := PackedVector2Array([center, center + facing.rotated(-0.42) * 170, center + facing.rotated(0.42) * 170, center])
		draw_colored_polygon(points, Color(1.0, 0.55, 0.22, 0.18))
		draw_polyline(points, Color("ffa460"), 4.0, true)
		draw_arc(center, 24, 0, TAU * (1.0 - _telegraph.remaining / _telegraph.duration), 32, Color("ffa460"), 4.0, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(-55, -30), "ELITE WARNING", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffbd88"))
	# Player silhouette is always drawn last, above crowd effects.
	for entity: RefCounted in _entities:
		if not entity.is_player_controlled():
			continue
		var position: Vector2 = entity.position()
		draw_circle(position, 17, Color("061016"))
		draw_circle(position, 12, Color("8ef4e4") if entity.is_alive() else Color("78838c"))
		draw_arc(position, 17, 0, TAU, 32, Color.WHITE, 2.0, true)
		draw_line(position + entity.aim_direction() * 18, position + entity.aim_direction() * 32, Color.WHITE, 3.0, true)


func _draw_effect(effect: Dictionary) -> void:
	var position: Vector2 = effect.position
	var progress: float = effect.age / effect.duration
	var alpha := 1.0 - progress
	var kind: String = effect.kind
	var index := SKILL_CUES.find(kind)
	var color: Color = COLORS[index] if index >= 0 else Color("93dce4")
	color.a = alpha
	match kind:
		"arc", "dash":
			draw_line(position, effect.destination, color, 4.0 if kind == "arc" else 9.0, true)
		"chain":
			var destination: Vector2 = effect.destination
			var middle: Vector2 = (position + destination) * 0.5 + Vector2(0, -16)
			draw_polyline(PackedVector2Array([position, middle, destination]), color, 3.0, true)
		"nova":
			draw_arc(position, maxf(1, progress * 100), 0, TAU, 64, color, 5.0, true)
		"ward", "totem":
			draw_arc(effect.destination if kind == "totem" else position, 15 + 25 * progress, 0, TAU, 6 if kind == "totem" else 40, color, 3.0, true)
		"death":
			for ray in 6:
				var direction := Vector2.RIGHT.rotated(TAU * ray / 6.0)
				draw_line(position + direction * (5 + progress * 12), position + direction * (10 + progress * 24), Color(0.9, 0.7, 0.6, alpha), 2.0, true)
		"critical":
			draw_arc(position, 10 + progress * 20, 0, TAU, 4, Color(1, 0.84, 0.4, alpha), 4.0, true)
			draw_string(ThemeDB.fallback_font, position + Vector2(-10, -30 - progress * 18), str(effect.amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.84, 0.4, alpha))
		"hurt", "protected":
			draw_arc(position, 18 + progress * 16, 0, TAU, 6 if kind == "protected" else 32, Color(0.5, 0.8, 1, alpha) if kind == "protected" else Color(1, 0.35, 0.4, alpha), 4.0, true)
		"shock", "hit":
			draw_line(position - Vector2(9, 9), position + Vector2(9, 9), Color(1, 0.85, 0.4, alpha) if kind == "shock" else color, 2.0, true)
			draw_line(position - Vector2(-9, 9), position + Vector2(-9, 9), color, 2.0, true)


static func _priority(kind: String) -> bool:
	return kind in SKILL_CUES or kind in ["critical", "hurt", "protected"]


func set_audio_enabled(value: bool) -> void:
	audio_enabled = value
	if not value:
		for voice in _voices:
			voice.stop()


func _exit_tree() -> void:
	for voice in _voices:
		voice.stop()
		voice.stream = null
