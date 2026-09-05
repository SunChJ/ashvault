class_name CombatHudModel
extends RefCounted

const ACTIONS := ["ability_primary", "ability_secondary", "ability_nova", "ability_ward", "ability_totem", "ability_dash"]
const NAMES := ["Arc Bolt", "Chain Lightning", "Thunder Nova", "Static Ward", "Storm Totem", "Tempest Dash"]
const STATUS_NAMES := {"status.shocked": "Shocked", "status.static_ward": "Static Ward", "status.tempest_guard": "Invulnerable"}


static func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "Unbound"
	var labels: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		var label := event.as_text()
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT: label = "LMB"
				MOUSE_BUTTON_RIGHT: label = "RMB"
				_: label = "Mouse %d" % event.button_index
		elif event is InputEventKey:
			label = OS.get_keycode_string(event.get_physical_keycode_with_modifiers() if event.physical_keycode != 0 else event.get_keycode_with_modifiers())
		if not labels.has(label):
			labels.append(label)
	return " / ".join(labels) if not labels.is_empty() else "Unbound"


static func read(snapshot: RefCounted, actor_id: int, loadout: RefCounted, status_records: Array) -> Dictionary:
	var actor: RefCounted = snapshot.entity(actor_id)
	if actor == null:
		return {}
	var slots: Array = []
	for slot in NAMES.size():
		var ability: Resource = loadout.binding(slot).ability()
		var remaining: int = actor.cooldown_ticks_remaining(slot)
		var label := binding_label(ACTIONS[slot])
		var state := "Ready"
		if not actor.is_alive():
			state = "Defeated"
		elif label == "Unbound":
			state = "Unbound"
		elif actor.ability_slot() == slot and actor.cast_phase() == "cast.started":
			state = "Casting"
		elif remaining > 0:
			state = "%.1fs" % (ceilf(float(remaining) / 6.0) / 10.0)
		elif actor.resource() < ability.cost_amount():
			state = "Low mana"
		elif actor.cast_phase() in ["cast.started", "cast.released", "cast.recovering"]:
			var active: RefCounted = loadout.binding(actor.ability_slot())
			if (
				actor.cast_phase() == "cast.released"
				or not loadout.binding(slot).cancels_active_cast()
				or not active.allows_interruption("interrupt.ability_replaced")
			):
				state = "Busy"
		slots.append({"name": NAMES[slot], "binding": label, "state": state,
			"cost": ability.cost_amount(), "cooldown_ticks": remaining,
			"cooldown_ratio": clampf(float(remaining) / maxf(1.0, ability.cooldown_ticks()), 0.0, 1.0)})
	var cast_text := "Ready"
	var cast_progress := 0.0
	if not actor.is_alive():
		cast_text = "Defeated"
	elif actor.cast_phase() == "cast.started":
		var slot: int = actor.ability_slot()
		var duration: int = loadout.binding(slot).ability().cast_time_ticks()
		cast_progress = 1.0 - float(actor.cast_ticks_remaining()) / maxf(1.0, duration)
		cast_text = "%s  ·  %.2fs" % [NAMES[slot], float(actor.cast_ticks_remaining()) / 60.0]
	elif actor.cast_phase() in ["cast.released", "cast.recovering"]:
		cast_text = "%s  ·  Recovering" % NAMES[actor.ability_slot()]
	elif actor.cast_phase() == "cast.canceled":
		cast_text = "Cast interrupted"
	var statuses: Array = []
	for record: Array in status_records:
		# StatusWorld publishes [target, status, source, stacks, expiry, mutation].
		if record.size() != 6 or record[0] != actor_id or record[4] <= snapshot.tick():
			continue
		statuses.append({"id": record[1], "name": STATUS_NAMES.get(record[1], str(record[1]).trim_prefix("status.").capitalize()),
			"stacks": record[3], "seconds": float(record[4] - snapshot.tick()) / 60.0})
	statuses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return {"tick": snapshot.tick(), "health": actor.health(), "max_health": actor.max_health(),
		"mana": actor.resource(), "max_mana": actor.max_resource(), "slots": slots,
		"cast_text": cast_text, "cast_progress": clampf(cast_progress, 0.0, 1.0), "statuses": statuses}
