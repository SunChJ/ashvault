class_name CombatHud
extends Control

const Model = preload("res://game/presentation/hud/combat_hud_model.gd")
const SlotScene = preload("res://game/presentation/hud/ability_slot.tscn")
const Loadout = preload("res://game/simulation/abilities/ability_loadout.gd")
const Snapshot = preload("res://game/simulation/snapshots/presentation_snapshot.gd")
const INK := Color("e6edf3")
const MUTED := Color("a4b4c3")
const ACCENT := Color("71dcdf")
const WARNING := Color("f0b77a")

var _loadout: RefCounted
var _slots: Array[Control] = []
var _view: Dictionary = {}


func _ready() -> void:
	add_theme_color_override("font_color", INK)
	%Vitals.add_theme_stylebox_override("panel", _panel(Color("14212c"), Color("334754")))
	_style_bar(%Health, Color("e98786"))
	_style_bar(%Mana, ACCENT)
	_style_bar(%CastProgress, ACCENT)
	for slot in Model.NAMES.size():
		var control: Control = SlotScene.instantiate()
		%Abilities.add_child(control)
		_slots.append(control)
		_style_bar(control.get_node("%Cooldown"), ACCENT)
	visible = false


func configure(loadout: Variant) -> String:
	if _loadout != null:
		return "Combat HUD is already configured."
	if not loadout is Loadout or not loadout.is_configured() or loadout.slots() != [0, 1, 2, 3, 4, 5]:
		return "Combat HUD requires a configured six-slot loadout."
	_loadout = loadout
	return ""


func present(snapshot: Variant, actor_id: int, status_records: Array = []) -> String:
	if not is_node_ready() or _loadout == null:
		return "Combat HUD must be ready and configured before presentation."
	if not snapshot is Snapshot:
		return "Combat HUD requires a PresentationSnapshot."
	var view := Model.read(snapshot, actor_id, _loadout, status_records)
	_view = view
	visible = not view.is_empty()
	if not visible:
		return ""
	%HealthText.text = "Health  %d / %d" % [view.health, view.max_health]
	%ManaText.text = "Mana  %.0f / %.0f" % [view.mana, view.max_mana]
	%Health.value = float(view.health) / maxf(1.0, view.max_health)
	%Mana.value = float(view.mana) / maxf(1.0, view.max_mana)
	%CastText.text = view.cast_text
	%CastProgress.value = view.cast_progress
	var status_labels: Array[String] = []
	for status: Dictionary in view.statuses:
		status_labels.append("%s x%d  %.1fs" % [status.name, status.stacks, status.seconds])
	%Statuses.text = "   /   ".join(status_labels) if not status_labels.is_empty() else "No active effects"
	%Statuses.modulate = ACCENT if not status_labels.is_empty() else MUTED
	for slot in _slots.size():
		var data: Dictionary = view.slots[slot]
		var control: Control = _slots[slot]
		var ready: bool = data.state == "Ready"
		control.add_theme_stylebox_override("panel", _panel(Color("14212c"), ACCENT if ready else Color("42525f")))
		control.get_node("%Binding").text = data.binding
		control.get_node("%Binding").tooltip_text = data.binding
		control.get_node("%Binding").modulate = ACCENT
		control.get_node("%AbilityName").text = data.name
		control.get_node("%Availability").text = "%s  ·  %d MP" % [data.state, data.cost]
		control.get_node("%Availability").modulate = MUTED if ready else WARNING
		control.get_node("%Cooldown").value = data.cooldown_ratio
	return ""


func view_state() -> Dictionary:
	return _view.duplicate(true)


static func _panel(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


static func _style_bar(bar: ProgressBar, color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("253746")
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
