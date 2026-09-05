class_name CombatArenaFixture
extends RefCounted

const Catalog = preload("res://game/simulation/abilities/stormweaver_catalog.gd")
const Combat = preload("res://game/simulation/abilities/stormweaver_combat.gd")
const Entity = preload("res://game/simulation/entities/entity_state.gd")
const Enemy = preload("res://game/simulation/enemies/enemy_definition.gd")
const MovementEnvironment = preload("res://game/simulation/movement/movement_environment.gd")
const Ability = preload("res://game/simulation/abilities/ability_definition.gd")
const Effect = preload("res://game/simulation/abilities/ability_effect_definition.gd")
const Component = preload("res://game/simulation/abilities/ability_damage_component.gd")


static func create(enemy_count: int = 12) -> Dictionary:
	if enemy_count < 1 or enemy_count > 120:
		return {"error": "Arena enemy count must be between 1 and 120."}
	var catalog := Catalog.new()
	Catalog._checked(catalog.configure())
	var environment := MovementEnvironment.new()
	Catalog._checked(environment.configure(Rect2(-820, -380, 1640, 650), [], 8.0, 180.0))
	var player := Entity.new()
	Catalog._checked(player.configure(1, "actor.stormweaver", true, Vector2.ZERO, 3000, 3000, 1000.0, 1000.0))
	var entities: Array = [player]
	var enemies: Dictionary = {}
	for index in enemy_count:
		var angle := TAU * float(index % 24) / minf(enemy_count, 24)
		var radius := 90.0 + 40.0 * floorf(float(index) / 24.0)
		var position := (Vector2(cos(angle), sin(angle)) * radius).snapped(Vector2(0.001, 0.001))
		var enemy := Entity.new()
		var health := 1000 if enemy_count == 120 else 65
		Catalog._checked(enemy.configure(index + 2, "enemy.arena.raider", false, position, health, health, 0.0, 0.0))
		entities.append(enemy)
		var profile := Enemy.new()
		Catalog._checked(profile.configure("enemy.arena.raider", 1000.0, 22.0, 7.0, 24.0, 60, "attack.arena.strike"))
		enemies[index + 2] = profile
	var component := Component.new()
	Catalog._checked(component.configure("damage.physical", 8.0, "", 0.0, "source.arena.raider"))
	var effect := Effect.new()
	Catalog._checked(effect.configure_damage("effect.arena.strike", [], [], [component], []))
	var attack := Ability.new()
	Catalog._checked(attack.configure_ability("ability.arena.strike", [], [], "", 0.0, 0, 0, 0,
		Ability.Targeting.ENTITY, Ability.Delivery.INSTANT, [effect], []))
	var combat := Combat.new()
	var error: String = combat.configure(entities, environment, catalog, 424242, enemies, {"attack.arena.strike": attack})
	return {"error": error, "combat": combat, "catalog": catalog}


static func showcase_slots(tick: int) -> Array:
	var schedule := {1: 0, 40: 1, 80: 2, 120: 3, 160: 4, 200: 5, 260: 0, 300: 1, 340: 2, 430: 3}
	return [schedule[tick]] if schedule.has(tick) else []
