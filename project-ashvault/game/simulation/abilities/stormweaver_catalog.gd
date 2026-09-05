class_name StormweaverCatalog
extends RefCounted

const Ability = preload("res://game/simulation/abilities/ability_definition.gd")
const Effect = preload("res://game/simulation/abilities/ability_effect_definition.gd")
const Component = preload("res://game/simulation/abilities/ability_damage_component.gd")
const Transform = preload("res://game/simulation/abilities/ability_effect_transform.gd")
const Milestone = preload("res://game/simulation/abilities/ability_rank_milestone.gd")
const Binding = preload("res://game/simulation/abilities/ability_cast_binding.gd")
const Loadout = preload("res://game/simulation/abilities/ability_loadout.gd")
const Delivery = preload("res://game/simulation/delivery/delivery_definition.gd")
const Status = preload("res://game/simulation/statuses/status_definition.gd")
const Modifier = preload("res://game/simulation/statuses/status_damage_modifier_template.gd")
const Stat = preload("res://game/simulation/stats/stat_definition.gd")
const Registry = preload("res://game/simulation/stats/stat_registry.gd")
const Resolver = preload("res://game/simulation/stats/stat_resolver.gd")

const ARC_BOLT := 0
const CHAIN_LIGHTNING := 1
const THUNDER_NOVA := 2
const STATIC_WARD := 3
const STORM_TOTEM := 4
const TEMPEST_DASH := 5
const SHOCK := "status.shocked"
const WARD := "status.static_ward"
const INVULNERABLE := "status.tempest_guard"
const POWER := "stat.offense.power"
const CRIT := "stat.critical.chance"
const CRIT_MULTIPLIER := "stat.critical.multiplier"
const DAMAGE_TYPES := ["damage.physical", "damage.fire", "damage.cold", "damage.lightning", "damage.poison"]
# Fixed slice content; timing is in 60 Hz ticks, distances in world units.
const SKILLS := [
	{"id": "arc_bolt", "cost": 3.0, "cooldown": 12, "cast": 3, "recovery": 3, "damage": 20.0},
	{"id": "chain_lightning", "cost": 12.0, "cooldown": 60, "cast": 6, "recovery": 6, "damage": 24.0},
	{"id": "thunder_nova", "cost": 16.0, "cooldown": 90, "cast": 6, "recovery": 6, "damage": 32.0},
	{"id": "static_ward", "cost": 10.0, "cooldown": 300, "cast": 0, "recovery": 3, "damage": 0.0},
	{"id": "storm_totem", "cost": 20.0, "cooldown": 240, "cast": 9, "recovery": 6, "damage": 12.0},
	{"id": "tempest_dash", "cost": 8.0, "cooldown": 90, "cast": 0, "recovery": 12, "damage": 0.0},
]

var _activations: Array = []
var _impacts: Array = []
var _deliveries: Array = []
var _ranks: Array = []
var _loadout: RefCounted
var _configured := false


func configure(ranks: Dictionary = {}, item_transforms: Dictionary = {}) -> String:
	if _configured:
		return "Stormweaver catalog is immutable."
	for values in [ranks, item_transforms]:
		for slot: Variant in values:
			if not slot is int or slot < 0 or slot >= SKILLS.size():
				return "Stormweaver slots must be integers from 0 to 5."
	for slot: int in ranks:
		if not ranks[slot] is int or ranks[slot] < 1 or ranks[slot] > 20:
			return "Stormweaver ranks must be integers from 1 to 20."
	var activations: Array = []
	var impacts: Array = []
	var deliveries: Array = []
	var rank_values: Array = []
	var bindings: Array = []
	for slot in SKILLS.size():
		var row: Dictionary = SKILLS[slot]
		var rank_value: int = ranks.get(slot, 1)
		var activation := _activation(slot)
		var impact: Resource = null
		var replacements: Variant = item_transforms.get(slot, [])
		if not replacements is Array:
			return "Item transforms must be Arrays of AbilityEffectTransform."
		if row.damage > 0.0:
			var authored_impact := _authored_impact(slot)
			var effects: Array = authored_impact.effects_for_rank(rank_value)
			var observed: Dictionary = {}
			for replacement: Variant in replacements:
				if not replacement is Transform or not replacement.is_configured():
					return "Item transform must be a configured AbilityEffectTransform."
				if replacement.target_effect_id() != effects[0].effect_id() or observed.has(replacement.target_effect_id()):
					return "Item transforms must uniquely replace this ability's damage effect."
				if replacement.replacement().kind() != Effect.Kind.DAMAGE:
					return "Item transforms must preserve the damage effect kind."
				observed[replacement.target_effect_id()] = true
				effects[0] = replacement.replacement()
			# Materialize the selected rank, then item replacements, into a validated graph.
			impact = Ability.new()
			var impact_error: String = impact.configure_ability(
				"ability.stormweaver.%s.hit" % row.id, ["ability.stormweaver"], [],
				"", 0.0, 0, 0, 0, Ability.Targeting.ENTITY, Ability.Delivery.INSTANT,
				effects, []
			)
			if not impact_error.is_empty():
				return impact_error
			impact.freeze()
		elif not replacements.is_empty():
			return "Defensive and movement abilities do not accept damage transforms."
		var binding := Binding.new()
		_checked(binding.configure(slot, activation,
			Binding.MovementPolicy.LOCK if slot == TEMPEST_DASH else Binding.MovementPolicy.CANCEL_CAST,
			true, ["interrupt.ability_replaced", "interrupt.stun", "interrupt.silence"], slot == TEMPEST_DASH))
		activations.append(activation)
		impacts.append(impact)
		deliveries.append(_delivery(slot, activation.effects_for_rank(rank_value)))
		rank_values.append(rank_value)
		bindings.append(binding)
	var loadout_value := Loadout.new()
	_checked(loadout_value.configure("resource.mana", bindings))
	_activations = activations
	_impacts = impacts
	_deliveries = deliveries
	_ranks = rank_values
	_loadout = loadout_value
	_configured = true
	return ""


func is_configured() -> bool:
	return _configured


func activation(slot: int) -> Resource:
	return _activations[slot]


func impact(slot: int) -> Resource:
	return _impacts[slot]


func delivery(slot: int) -> Resource:
	return _deliveries[slot]


func rank_for(slot: int) -> int:
	return _ranks[slot]


func loadout() -> RefCounted:
	return _loadout


static func default_stats(tick_value: int = 0) -> RefCounted:
	var registry := Registry.new()
	var definitions: Array = []
	for row in [[POWER, 10.0], [CRIT, 0.1], [CRIT_MULTIPLIER, 1.5]]:
		var definition := Stat.new()
		_checked(definition.configure(row[0], row[1]))
		definitions.append(definition)
	var errors: PackedStringArray = registry.load_definitions(definitions)
	assert(errors.is_empty())
	return Resolver.resolve(registry, [], PackedStringArray(), tick_value).snapshot()


static func statuses(damage_types: Array = DAMAGE_TYPES) -> Array:
	var result: Array = []
	for row in [[SHOCK, 3, 0.1], [WARD, 1, -0.3], [INVULNERABLE, 1, -1.0]]:
		var templates: Array = []
		for damage_type: String in damage_types:
			var template := Modifier.new()
			_checked(template.configure(damage_type, row[2], "source.%s.%s" % [row[0], damage_type]))
			templates.append(template)
		var definition := Status.new()
		_checked(definition.configure(row[0], ["status.stormweaver"], 1, 600, row[1],
			Status.StackPolicy.ADD, Status.RefreshPolicy.RESET,
			Status.RemovalPolicy.PROTECTED if row[0] == INVULNERABLE else Status.RemovalPolicy.CLEANSABLE,
			templates))
		result.append(definition)
	return result


static func _activation(slot: int) -> Resource:
	var row: Dictionary = SKILLS[slot]
	var effect := Effect.new()
	var targeting := Ability.Targeting.DIRECTION
	var delivery_kind := Ability.Delivery.INSTANT
	var milestones: Array = []
	match slot:
		ARC_BOLT:
			delivery_kind = Ability.Delivery.PROJECTILE
			_checked(effect.configure_projectile("effect.arc_bolt.launch", [], [], "delivery.arc_bolt", 600.0, 60))
		CHAIN_LIGHTNING, THUNDER_NOVA:
			delivery_kind = Ability.Delivery.CHAIN if slot == CHAIN_LIGHTNING else Ability.Delivery.AREA
			targeting = Ability.Targeting.ENTITY if slot == CHAIN_LIGHTNING else Ability.Targeting.SELF
			_checked(effect.configure_event("effect.%s.activate" % row.id, [], [], "event.ability_released", {}))
		STATIC_WARD:
			targeting = Ability.Targeting.SELF
			effect = _status_effect(row.id, WARD, 240)
			milestones = [_milestone(effect, _status_effect(row.id, WARD, 360))]
		STORM_TOTEM:
			targeting = Ability.Targeting.POINT
			delivery_kind = Ability.Delivery.PERSISTENT
			_checked(effect.configure_persistent_entity("effect.storm_totem.spawn", [], [], "delivery.storm_totem", 180))
		TEMPEST_DASH:
			delivery_kind = Ability.Delivery.MOVEMENT
			_checked(effect.configure_movement("effect.tempest_dash.move", [], [], "movement.dash", 120.0, 12))
			var upgraded := Effect.new()
			_checked(upgraded.configure_movement("effect.tempest_dash.move", [], [], "movement.dash", 180.0, 12))
			milestones = [_milestone(effect, upgraded)]
	var effects: Array = [effect]
	if slot == TEMPEST_DASH:
		effects.append(_status_effect(row.id, INVULNERABLE, 12, [effect.effect_id()]))
	var ability := Ability.new()
	_checked(ability.configure_ability("ability.stormweaver.%s" % row.id, ["ability.stormweaver"], [],
		"resource.mana", row.cost, row.cooldown, row.cast, row.recovery,
		targeting, delivery_kind, effects, milestones))
	return ability


static func _delivery(slot: int, effects: Array) -> Resource:
	var definition := Delivery.new()
	match slot:
		ARC_BOLT:
			_checked(definition.configure_projectile("delivery.arc_bolt", 3.0, effects[0].speed(), effects[0].lifetime_ticks(), 1))
		CHAIN_LIGHTNING:
			_checked(definition.configure_chain("delivery.chain_lightning", 300.0, 100.0, 4))
		THUNDER_NOVA:
			_checked(definition.configure_area("delivery.thunder_nova", 100.0, 0))
		STORM_TOTEM:
			_checked(definition.configure_persistent("delivery.storm_totem", 150.0, effects[0].duration_ticks(), 30, 1))
		_:
			return null
	return definition


static func _damage_effect(id: String, amount: float) -> Resource:
	var component := Component.new()
	_checked(component.configure("damage.lightning", amount, POWER, 0.5, "source.stormweaver.%s" % id))
	var effect := Effect.new()
	_checked(effect.configure_damage("effect.%s.damage" % id, ["damage.lightning"], [],
		[component], [], CRIT, CRIT_MULTIPLIER))
	return effect


static func _status_effect(id: String, status_id: String, duration: int, dependencies: Array = []) -> Resource:
	var effect := Effect.new()
	_checked(effect.configure_status("effect.%s.status" % id, [], PackedStringArray(dependencies), status_id, duration, 1))
	return effect


static func _milestone(original: Resource, upgraded: Resource) -> Resource:
	var transform := Transform.new()
	_checked(transform.configure("source.rank.five", original.effect_id(), upgraded))
	var milestone := Milestone.new()
	_checked(milestone.configure(5, [transform]))
	return milestone


static func _checked(error: String) -> void:
	assert(error.is_empty(), error)


static func _authored_impact(slot: int) -> Resource:
	var row: Dictionary = SKILLS[slot]
	var damage := _damage_effect(row.id, row.damage)
	var effects: Array = [damage]
	if slot == CHAIN_LIGHTNING:
		effects.append(_status_effect(row.id, SHOCK, 180, [damage.effect_id()]))
	var ability := Ability.new()
	_checked(ability.configure_ability("ability.stormweaver.%s.hit" % row.id, ["ability.stormweaver"], [],
		"", 0.0, 0, 0, 0, Ability.Targeting.ENTITY, Ability.Delivery.INSTANT, effects,
		[_milestone(damage, _damage_effect(row.id, row.damage * 1.5))]))
	return ability


func canonical_values() -> Array:
	var values: Array = []
	for slot in SKILLS.size():
		values.append([_ranks[slot], ability_values(_activations[slot], _ranks[slot]),
			ability_values(_impacts[slot]),
			_deliveries[slot].canonical_values() if _deliveries[slot] != null else []])
	return values


static func ability_values(ability: Resource, rank_value: int = 1) -> Array:
	if ability == null:
		return []
	var effects: Array = []
	for effect: Resource in ability.effects_for_rank(rank_value):
		var components: Array = []
		for component: Resource in effect.damage_components():
			components.append([component.damage_type_id(), component.base_amount(), component.scaling_stat_id(),
				component.scaling_coefficient(), component.source_id()])
		var modifiers: Array = []
		for modifier: Resource in effect.damage_modifiers():
			modifiers.append(modifier.to_runtime().explanation_fields())
		effects.append([effect.effect_id(), effect.kind(), Array(effect.tags()), Array(effect.dependency_ids()),
			components, modifiers, effect.critical_chance_stat_id(), effect.critical_multiplier_stat_id(),
			effect.status_definition_id(), effect.duration_ticks(), effect.stacks(), effect.movement_mode_id(),
			effect.distance(), effect.projectile_definition_id(), effect.speed(), effect.lifetime_ticks(),
			effect.entity_definition_id(), effect.event_type(), effect.event_payload()])
	return [ability.content_id, Array(ability.tags), ability.cost_resource_id(), ability.cost_amount(),
		ability.cooldown_ticks(), ability.cast_time_ticks(), ability.recovery_ticks(),
		ability.targeting(), ability.delivery(), effects]


static func damage_types(abilities: Array) -> Array:
	var types: Dictionary = {}
	for ability: Resource in abilities:
		if ability == null:
			continue
		for effect: Resource in ability.effects_for_rank(1):
			for component: Resource in effect.damage_components():
				types[component.damage_type_id()] = true
			for authored: Resource in effect.damage_modifiers():
				var modifier: RefCounted = authored.to_runtime()
				types[modifier.damage_type_id()] = true
				if not modifier.target_damage_type_id().is_empty():
					types[modifier.target_damage_type_id()] = true
	var result: Array = types.keys()
	result.sort()
	return result
