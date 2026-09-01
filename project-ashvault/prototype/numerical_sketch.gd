extends Node2D

const CombatMath = preload("res://prototype/core/combat_math.gd")
const ProgressionMath = preload("res://prototype/core/progression_math.gd")

const BACKGROUND := Color("09101b")
const GRID := Color("16263a")
const PLAYER_COLOR := Color("65e6ff")
const PROJECTILE_COLOR := Color("b9f6ff")
const XP_COLOR := Color("61f2ad")
const FODDER_COLOR := Color("f15b64")
const ELITE_COLOR := Color("b66cff")
const BOSS_COLOR := Color("ffb84a")
const MAX_ENEMIES := 180

var rng := RandomNumberGenerator.new()
var font: Font
var arena_size := Vector2.ZERO
var player_position := Vector2.ZERO
var player_radius := 13.0
var player_speed := 235.0
var player_health := 100.0
var player_max_health := 100.0
var player_invulnerability := 0.0

var elapsed := 0.0
var level := 1
var experience := 0
var total_experience := 0
var kills := 0
var combo := 0
var combo_timer := 0.0
var charge := 0
var overdrive_timer := 0.0
var game_over := false
var first_upgrade_time := -1.0
var first_overdrive_time := -1.0
var first_boss_time := -1.0
var peak_enemies := 0

var storm_rank := 2
var nova_rank := 1
var increased_damage := 0.0
var raw_haste := 0.0
var critical_chance := 0.06
var critical_multiplier := 1.6
var magnet_radius := 240.0

var spawn_progress := 0.0
var enemy_serial := 0
var next_boss_time := 120.0
var attack_timer := 0.0
var nova_timer := 2.2
var pending_levels := 0
var choosing_upgrade := false
var upgrade_options: Array[String] = []
var charge_release_pending := false

var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var damage_events: Array[Dictionary] = []


func _ready() -> void:
	rng.seed = 0xA55A_17
	font = ThemeDB.fallback_font
	arena_size = get_viewport_rect().size
	player_position = arena_size * 0.5
	queue_redraw()


func _physics_process(delta: float) -> void:
	if game_over or choosing_upgrade:
		queue_redraw()
		return

	elapsed += delta
	player_invulnerability = maxf(0.0, player_invulnerability - delta)
	overdrive_timer = maxf(0.0, overdrive_timer - delta)
	_update_combo(delta)
	_update_player(delta)
	_spawn_wave(delta)
	peak_enemies = maxi(peak_enemies, enemies.size())
	_update_attacks(delta)
	_update_projectiles(delta)
	_update_enemies(delta)
	if charge_release_pending:
		charge_release_pending = false
		_cast_nova(true)
	_update_drops(delta)
	_update_effects(delta)
	_trim_damage_window()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	if event.keycode == KEY_R and game_over:
		get_tree().reload_current_scene()
		return

	if not choosing_upgrade:
		return

	var selected := -1
	match event.keycode:
		KEY_1, KEY_KP_1:
			selected = 0
		KEY_2, KEY_KP_2:
			selected = 1
		KEY_3, KEY_KP_3:
			selected = 2

	if selected >= 0 and selected < upgrade_options.size():
		_apply_upgrade(upgrade_options[selected])


func _update_player(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed_bonus := 1.16 if overdrive_timer > 0.0 else 1.0
	player_position += direction * player_speed * speed_bonus * delta
	player_position.x = clampf(player_position.x, 24.0, arena_size.x - 24.0)
	player_position.y = clampf(player_position.y, 24.0, arena_size.y - 24.0)


func _spawn_wave(delta: float) -> void:
	var spawn_rate := minf(14.0, 2.0 + elapsed / 12.0)
	spawn_progress += spawn_rate * delta
	while spawn_progress >= 1.0 and enemies.size() < MAX_ENEMIES:
		spawn_progress -= 1.0
		enemy_serial += 1
		_spawn_enemy(1 if enemy_serial % 21 == 0 else 0)

	if elapsed >= next_boss_time and enemies.size() < MAX_ENEMIES:
		next_boss_time += 120.0
		_spawn_enemy(2)
		if first_boss_time < 0.0:
			first_boss_time = elapsed


func _spawn_enemy(kind: int) -> void:
	var edge := rng.randi_range(0, 3)
	var position := Vector2.ZERO
	match edge:
		0:
			position = Vector2(rng.randf_range(0.0, arena_size.x), -30.0)
		1:
			position = Vector2(arena_size.x + 30.0, rng.randf_range(0.0, arena_size.y))
		2:
			position = Vector2(rng.randf_range(0.0, arena_size.x), arena_size.y + 30.0)
		_:
			position = Vector2(-30.0, rng.randf_range(0.0, arena_size.y))

	var minute := elapsed / 60.0
	var health_scale := 1.0 + 0.13 * minute + 0.02 * minute * minute
	var health := 28.0 * health_scale
	var radius := 10.0
	var speed := rng.randf_range(55.0, 78.0) * (1.0 + minf(0.35, minute * 0.04))
	var contact_damage := 8.0
	var xp_value := 6

	if kind == 1:
		health *= 7.5
		radius = 18.0
		speed *= 0.82
		contact_damage = 16.0
		xp_value = 65
	elif kind == 2:
		health *= 36.0
		radius = 31.0
		speed *= 0.68
		contact_damage = 28.0
		xp_value = 700

	enemies.append({
		"id": enemy_serial,
		"kind": kind,
		"pos": position,
		"hp": health,
		"max_hp": health,
		"radius": radius,
		"speed": speed,
		"damage": contact_damage,
		"xp": xp_value,
		"contact_timer": 0.0,
		"flash": 0.0,
	})


func _update_attacks(delta: float) -> void:
	var overdrive_haste := 0.9 if overdrive_timer > 0.0 else 0.0
	attack_timer -= delta
	if attack_timer <= 0.0 and not enemies.is_empty():
		attack_timer += CombatMath.interval_after_haste(0.62, raw_haste + overdrive_haste)
		_cast_storm_bolt()

	nova_timer -= delta
	if nova_timer <= 0.0:
		nova_timer += ProgressionMath.nova_interval(nova_rank)
		_cast_nova(false)


func _cast_storm_bolt() -> void:
	var target_index := _nearest_enemy_index(player_position)
	if target_index < 0:
		return

	var target_position: Vector2 = enemies[target_index]["pos"]
	var base_direction := player_position.direction_to(target_position)
	var count := ProgressionMath.projectile_count(storm_rank)
	var spread_step := 0.16
	for projectile_index in count:
		var offset := (float(projectile_index) - float(count - 1) * 0.5) * spread_step
		var is_critical := CombatMath.rolls_critical(rng, critical_chance)
		var more_modifiers: Array[float] = []
		if overdrive_timer > 0.0:
			more_modifiers.append(1.18)
		var damage := CombatMath.resolve_hit(
			34.0 * ProgressionMath.skill_damage_multiplier(storm_rank),
			0.0,
			0.0,
			increased_damage,
			more_modifiers,
			is_critical,
			critical_multiplier
		)
		projectiles.append({
			"pos": player_position,
			"velocity": base_direction.rotated(offset) * 650.0,
			"damage": damage,
			"radius": 5.0 if not is_critical else 7.0,
			"life": 1.4,
			"chains": ProgressionMath.chain_count(storm_rank),
		})


func _cast_nova(charged: bool) -> void:
	var radius := ProgressionMath.nova_radius(nova_rank)
	var base_damage := 20.0 * ProgressionMath.skill_damage_multiplier(nova_rank)
	if charged:
		radius *= 1.85
		base_damage *= 2.8

	var damage := CombatMath.resolve_hit(
		base_damage,
		0.0,
		0.0,
		increased_damage,
		[],
		false,
		critical_multiplier,
		0.0,
		0.0,
		0.25 if overdrive_timer > 0.0 else 0.0
	)
	for enemy_index in range(enemies.size() - 1, -1, -1):
		var enemy_position: Vector2 = enemies[enemy_index]["pos"]
		if player_position.distance_to(enemy_position) <= radius:
			_damage_enemy(enemy_index, damage)

	effects.append({
		"pos": player_position,
		"radius": 18.0,
		"max_radius": radius,
		"life": 0.32 if not charged else 0.48,
		"max_life": 0.32 if not charged else 0.48,
		"charged": charged,
	})


func _update_projectiles(delta: float) -> void:
	for projectile_index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[projectile_index]
		projectile["pos"] = (projectile["pos"] as Vector2) + (projectile["velocity"] as Vector2) * delta
		projectile["life"] = float(projectile["life"]) - delta
		if float(projectile["life"]) <= 0.0:
			projectiles.remove_at(projectile_index)
			continue

		var hit_index := -1
		for enemy_index in range(enemies.size() - 1, -1, -1):
			var enemy_position: Vector2 = enemies[enemy_index]["pos"]
			var collision_radius := float(projectile["radius"]) + float(enemies[enemy_index]["radius"])
			if (projectile["pos"] as Vector2).distance_squared_to(enemy_position) <= collision_radius * collision_radius:
				hit_index = enemy_index
				break

		if hit_index < 0:
			projectiles[projectile_index] = projectile
			continue

		var impact_position: Vector2 = enemies[hit_index]["pos"]
		var hit_enemy_id := int(enemies[hit_index]["id"])
		_damage_enemy(hit_index, float(projectile["damage"]))
		if int(projectile["chains"]) > 0:
			_spawn_chain(
				impact_position,
				float(projectile["damage"]) * 0.72,
				int(projectile["chains"]) - 1,
				hit_enemy_id
			)
		projectiles.remove_at(projectile_index)


func _spawn_chain(origin: Vector2, damage: float, chains: int, excluded_id: int) -> void:
	var target_index := _nearest_enemy_index(origin, excluded_id, 240.0)
	if target_index < 0:
		return
	var target_position: Vector2 = enemies[target_index]["pos"]
	projectiles.append({
		"pos": origin,
		"velocity": origin.direction_to(target_position) * 760.0,
		"damage": damage,
		"radius": 4.0,
		"life": 0.45,
		"chains": chains,
	})


func _nearest_enemy_index(origin: Vector2, excluded_id: int = -1, limit: float = INF) -> int:
	var nearest_index := -1
	var nearest_distance := limit * limit
	for enemy_index in enemies.size():
		if int(enemies[enemy_index]["id"]) == excluded_id:
			continue
		var enemy_position: Vector2 = enemies[enemy_index]["pos"]
		var distance := origin.distance_squared_to(enemy_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = enemy_index
	return nearest_index


func _update_enemies(delta: float) -> void:
	for enemy_index in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[enemy_index]
		var enemy_position: Vector2 = enemy["pos"]
		var direction := enemy_position.direction_to(player_position)
		enemy_position += direction * float(enemy["speed"]) * delta
		enemy["pos"] = enemy_position
		enemy["contact_timer"] = maxf(0.0, float(enemy["contact_timer"]) - delta)
		enemy["flash"] = maxf(0.0, float(enemy["flash"]) - delta)

		var contact_radius := player_radius + float(enemy["radius"])
		if enemy_position.distance_squared_to(player_position) <= contact_radius * contact_radius:
			if float(enemy["contact_timer"]) <= 0.0:
				enemy["contact_timer"] = 0.75
				_take_damage(float(enemy["damage"]))
			enemy["pos"] = enemy_position - direction * 24.0 * delta

		enemies[enemy_index] = enemy


func _damage_enemy(enemy_index: int, amount: float) -> void:
	if enemy_index < 0 or enemy_index >= enemies.size():
		return
	var enemy := enemies[enemy_index]
	enemy["hp"] = float(enemy["hp"]) - amount
	enemy["flash"] = 0.08
	_record_damage(amount)
	if float(enemy["hp"]) > 0.0:
		enemies[enemy_index] = enemy
		return

	var death_position: Vector2 = enemy["pos"]
	var xp_value := int(enemy["xp"])
	var kind := int(enemy["kind"])
	enemies.remove_at(enemy_index)
	_spawn_drop(death_position, xp_value, kind)
	kills += 1
	combo += 1
	combo_timer = 2.35
	charge += 1
	if charge >= 12:
		charge -= 12
		charge_release_pending = true
	if combo >= 22 and overdrive_timer <= 0.0:
		combo = 0
		overdrive_timer = 5.0
		if first_overdrive_time < 0.0:
			first_overdrive_time = elapsed


func _take_damage(amount: float) -> void:
	if player_invulnerability > 0.0 or game_over:
		return
	player_health -= amount
	player_invulnerability = 0.55
	effects.append({
		"pos": player_position,
		"radius": player_radius,
		"max_radius": 54.0,
		"life": 0.22,
		"max_life": 0.22,
		"charged": false,
	})
	if player_health <= 0.0:
		player_health = 0.0
		game_over = true


func _spawn_drop(position: Vector2, value: int, kind: int) -> void:
	drops.append({
		"pos": position,
		"value": value,
		"radius": 4.0 + float(kind) * 1.5,
	})


func _update_drops(delta: float) -> void:
	for drop_index in range(drops.size() - 1, -1, -1):
		var drop := drops[drop_index]
		var drop_position: Vector2 = drop["pos"]
		var distance := drop_position.distance_to(player_position)
		if distance < magnet_radius:
			var pull := lerpf(150.0, 720.0, 1.0 - distance / magnet_radius)
			drop_position = drop_position.move_toward(player_position, pull * delta)
			drop["pos"] = drop_position
		if drop_position.distance_to(player_position) <= player_radius + float(drop["radius"]):
			_gain_experience(int(drop["value"]))
			drops.remove_at(drop_index)
		else:
			drops[drop_index] = drop


func _gain_experience(amount: int) -> void:
	experience += amount
	total_experience += amount
	while experience >= ProgressionMath.xp_to_next(level):
		experience -= ProgressionMath.xp_to_next(level)
		level += 1
		pending_levels += 1
		if first_upgrade_time < 0.0:
			first_upgrade_time = elapsed
	if pending_levels > 0 and not choosing_upgrade:
		_begin_level_up()


func _begin_level_up() -> void:
	choosing_upgrade = true
	upgrade_options.clear()
	var pool: Array[String] = [
		"storm_rank",
		"nova_rank",
		"power",
		"haste",
		"critical_chance",
		"critical_damage",
		"move_speed",
		"vitality",
		"magnet",
	]
	if storm_rank < 3:
		upgrade_options.append("storm_rank")
		pool.erase("storm_rank")
	while upgrade_options.size() < 3 and not pool.is_empty():
		var pool_index := rng.randi_range(0, pool.size() - 1)
		upgrade_options.append(pool.pop_at(pool_index))


func _apply_upgrade(upgrade: String) -> void:
	match upgrade:
		"storm_rank":
			storm_rank += 1
		"nova_rank":
			nova_rank += 1
		"power":
			increased_damage += 0.18
		"haste":
			raw_haste += 0.22
		"critical_chance":
			critical_chance = minf(CombatMath.MAX_CRITICAL_CHANCE, critical_chance + 0.09)
		"critical_damage":
			critical_multiplier += 0.28
		"move_speed":
			player_speed += 22.0
		"vitality":
			player_max_health += 22.0
			player_health = minf(player_max_health, player_health + 35.0)
		"magnet":
			magnet_radius += 45.0

	pending_levels -= 1
	if pending_levels > 0:
		_begin_level_up()
	else:
		choosing_upgrade = false
		upgrade_options.clear()


func _update_combo(delta: float) -> void:
	if combo <= 0:
		return
	combo_timer -= delta
	if combo_timer <= 0.0:
		combo = 0


func _update_effects(delta: float) -> void:
	for effect_index in range(effects.size() - 1, -1, -1):
		var effect := effects[effect_index]
		effect["life"] = float(effect["life"]) - delta
		if float(effect["life"]) <= 0.0:
			effects.remove_at(effect_index)
			continue
		var progress := 1.0 - float(effect["life"]) / float(effect["max_life"])
		effect["radius"] = lerpf(float(effect["radius"]), float(effect["max_radius"]), progress)
		effects[effect_index] = effect


func _record_damage(amount: float) -> void:
	damage_events.append({"time": elapsed, "amount": amount})


func _trim_damage_window() -> void:
	while not damage_events.is_empty() and float(damage_events[0]["time"]) < elapsed - 5.0:
		damage_events.pop_front()


func _current_dps() -> float:
	var total := 0.0
	for event in damage_events:
		total += float(event["amount"])
	return total / maxf(1.0, minf(5.0, elapsed))


func _upgrade_title(upgrade: String) -> String:
	match upgrade:
		"storm_rank":
			return "Storm Bolt +1"
		"nova_rank":
			return "Arc Nova +1"
		"power":
			return "+18% increased damage"
		"haste":
			return "+22% raw haste"
		"critical_chance":
			return "+9% critical chance"
		"critical_damage":
			return "+28% critical damage"
		"move_speed":
			return "+22 movement speed"
		"vitality":
			return "+22 max health, heal 35"
		"magnet":
			return "+45 pickup radius"
	return upgrade


func _upgrade_detail(upgrade: String) -> String:
	if upgrade == "storm_rank":
		if storm_rank == 2:
			return "Milestone: add a second projectile"
		if storm_rank == 4:
			return "Next rank unlocks chain lightning"
		return "More damage; milestones at ranks 3 and 5"
	if upgrade == "nova_rank":
		return "More damage, radius, and cast frequency"
	if upgrade == "haste":
		return "Diminishing returns; always lowers interval"
	return "Immediate permanent run power"


func _draw() -> void:
	_draw_arena()
	_draw_drops()
	_draw_effects()
	_draw_enemies()
	_draw_projectiles()
	_draw_player()
	_draw_hud()
	if choosing_upgrade:
		_draw_upgrade_overlay()
	elif game_over:
		_draw_game_over()


func _draw_arena() -> void:
	draw_rect(Rect2(Vector2.ZERO, arena_size), BACKGROUND)
	var spacing := 48
	for x in range(0, int(arena_size.x) + spacing, spacing):
		draw_line(Vector2(x, 0), Vector2(x, arena_size.y), GRID, 1.0)
	for y in range(0, int(arena_size.y) + spacing, spacing):
		draw_line(Vector2(0, y), Vector2(arena_size.x, y), GRID, 1.0)


func _draw_drops() -> void:
	for drop in drops:
		var position: Vector2 = drop["pos"]
		var radius := float(drop["radius"])
		draw_colored_polygon(PackedVector2Array([
			position + Vector2(0.0, -radius),
			position + Vector2(radius, 0.0),
			position + Vector2(0.0, radius),
			position + Vector2(-radius, 0.0),
		]), XP_COLOR)


func _draw_effects() -> void:
	for effect in effects:
		var alpha := float(effect["life"]) / float(effect["max_life"])
		var color := Color("ffd166") if bool(effect["charged"]) else Color("65e6ff")
		color.a = alpha
		draw_arc(effect["pos"], float(effect["radius"]), 0.0, TAU, 64, color, 4.0)


func _draw_enemies() -> void:
	for enemy in enemies:
		var position: Vector2 = enemy["pos"]
		var kind := int(enemy["kind"])
		var color := FODDER_COLOR
		if kind == 1:
			color = ELITE_COLOR
		elif kind == 2:
			color = BOSS_COLOR
		if float(enemy["flash"]) > 0.0:
			color = Color.WHITE
		draw_circle(position, float(enemy["radius"]), color)
		draw_circle(position, float(enemy["radius"]) * 0.45, BACKGROUND)
		if kind > 0:
			var width := float(enemy["radius"]) * 2.2
			var ratio := clampf(float(enemy["hp"]) / float(enemy["max_hp"]), 0.0, 1.0)
			draw_rect(Rect2(position + Vector2(-width * 0.5, -float(enemy["radius"]) - 9.0), Vector2(width, 4.0)), Color("402637"))
			draw_rect(Rect2(position + Vector2(-width * 0.5, -float(enemy["radius"]) - 9.0), Vector2(width * ratio, 4.0)), color)


func _draw_projectiles() -> void:
	for projectile in projectiles:
		var position: Vector2 = projectile["pos"]
		var radius := float(projectile["radius"])
		draw_circle(position, radius + 3.0, Color(0.2, 0.8, 1.0, 0.22))
		draw_circle(position, radius, PROJECTILE_COLOR)


func _draw_player() -> void:
	if player_invulnerability > 0.0 and int(player_invulnerability * 18.0) % 2 == 0:
		return
	if overdrive_timer > 0.0:
		draw_arc(player_position, 23.0, 0.0, TAU, 32, Color("ffd166"), 4.0)
	draw_circle(player_position, player_radius + 4.0, Color(0.1, 0.8, 1.0, 0.22))
	draw_circle(player_position, player_radius, PLAYER_COLOR)
	draw_circle(player_position, 5.0, BACKGROUND)


func _draw_hud() -> void:
	var xp_required := ProgressionMath.xp_to_next(level)
	var xp_ratio := float(experience) / float(xp_required)
	var hp_ratio := player_health / player_max_health
	draw_rect(Rect2(22.0, 20.0, 286.0, 14.0), Color("241c2b"))
	draw_rect(Rect2(22.0, 20.0, 286.0 * hp_ratio, 14.0), Color("f15b64"))
	draw_rect(Rect2(22.0, 40.0, 286.0, 10.0), Color("183229"))
	draw_rect(Rect2(22.0, 40.0, 286.0 * xp_ratio, 10.0), XP_COLOR)
	draw_string(font, Vector2(22.0, 72.0), "LV %d   HP %d/%d   XP %d/%d" % [level, int(player_health), int(player_max_health), experience, xp_required], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color.WHITE)
	draw_string(font, Vector2(22.0, 96.0), "%s   Kills %d   DPS %.0f   Alive %d" % [_format_time(elapsed), kills, _current_dps(), enemies.size()], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color("b8c5d6"))
	draw_string(font, Vector2(22.0, 120.0), "Storm R%d  Nova R%d  Charge %d/12" % [storm_rank, nova_rank, charge], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color("78dcff"))
	if combo > 0:
		draw_string(font, Vector2(arena_size.x - 180.0, 42.0), "COMBO %d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color("ffd166"))
	if overdrive_timer > 0.0:
		draw_string(font, Vector2(arena_size.x * 0.5 - 95.0, 42.0), "OVERDRIVE %.1fs" % overdrive_timer, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 23, Color("ffd166"))


func _draw_upgrade_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, arena_size), Color(0.01, 0.02, 0.04, 0.78))
	var panel_size := Vector2(minf(830.0, arena_size.x - 80.0), 330.0)
	var panel_position := (arena_size - panel_size) * 0.5
	draw_rect(Rect2(panel_position, panel_size), Color("111d2d"), true)
	draw_rect(Rect2(panel_position, panel_size), Color("65e6ff"), false, 2.0)
	draw_string(font, panel_position + Vector2(28.0, 48.0), "LEVEL %d — CHOOSE POWER" % level, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, Color.WHITE)
	for option_index in upgrade_options.size():
		var card_position := panel_position + Vector2(28.0, 78.0 + option_index * 76.0)
		draw_rect(Rect2(card_position, Vector2(panel_size.x - 56.0, 62.0)), Color("192b40"), true)
		draw_string(font, card_position + Vector2(16.0, 26.0), "%d   %s" % [option_index + 1, _upgrade_title(upgrade_options[option_index])], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color("b9f6ff"))
		draw_string(font, card_position + Vector2(48.0, 49.0), _upgrade_detail(upgrade_options[option_index]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color("9baabd"))


func _draw_game_over() -> void:
	draw_rect(Rect2(Vector2.ZERO, arena_size), Color(0.01, 0.02, 0.04, 0.72))
	draw_string(font, arena_size * 0.5 + Vector2(-92.0, -28.0), "RUN ENDED", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32, Color("f15b64"))
	draw_string(font, arena_size * 0.5 + Vector2(-128.0, 12.0), "%s  •  Level %d  •  %d kills" % [_format_time(elapsed), level, kills], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color.WHITE)
	draw_string(font, arena_size * 0.5 + Vector2(-72.0, 50.0), "Press R to restart", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color("b8c5d6"))


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func debug_snapshot() -> Dictionary:
	return {
		"elapsed": elapsed,
		"level": level,
		"kills": kills,
		"alive": enemies.size(),
		"peak_enemies": peak_enemies,
		"first_upgrade_time": first_upgrade_time,
		"first_overdrive_time": first_overdrive_time,
		"first_boss_time": first_boss_time,
		"storm_rank": storm_rank,
		"nova_rank": nova_rank,
		"game_over": game_over,
	}
