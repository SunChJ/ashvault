extends SceneTree

const Progression = preload("res://game/simulation/progression/character_progression.gd")
const Catalog = preload("res://game/simulation/progression/progression_catalog.gd")
const Passive = preload("res://game/simulation/progression/passive_definition.gd")
const Template = preload("res://game/simulation/stats/stat_modifier_template.gd")
const Stat = preload("res://game/simulation/stats/stat_definition.gd")
const Registry = preload("res://game/simulation/stats/stat_registry.gd")
const Stormweaver = preload("res://game/simulation/abilities/stormweaver_catalog.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _passive(id: String, amount: float, minimum_level: int = 1, stat_id: String = "stat.power") -> Resource:
	var effect := Template.new()
	effect.effect_id = "stat_effect.power"
	effect.stat_id = stat_id
	effect.amount = amount
	var passive := Passive.new()
	passive.content_id = id
	passive.minimum_level = minimum_level
	passive.max_rank = 2
	passive.modifiers = [effect]
	return passive


func _fixture(reverse: bool = false) -> Dictionary:
	var storm := Stormweaver.new()
	storm.configure()
	var skills: Array = []
	for slot in 6:
		skills.append(storm.activation(slot))
	var root: Resource = _passive("passive.power", 5)
	var child: Resource = _passive("passive.mastery", 10, 3)
	child.prerequisites = {"passive.power": 2}
	var broken: Resource = _passive("passive.broken", 1, 1, "stat.missing")
	var passives: Array = [root, child, broken]
	if reverse:
		passives.reverse()
		skills.reverse()
	var catalog := Catalog.new()
	var curve: Resource = preload("res://game/simulation/progression/character_curve.tres")
	var error: String = catalog.load_definitions(curve, skills, passives)
	_check(error.is_empty(), "Progression catalog must load: " + error)
	var stat := Stat.new()
	stat.configure("stat.power", 100)
	var registry := Registry.new()
	registry.load_definitions([stat])
	var progression := Progression.new()
	_check(progression.configure("character.fixture", catalog, registry).is_empty(), "Character progression must configure.")
	return {"progression": progression, "catalog": catalog, "registry": registry, "root": root, "child": child, "curve": curve, "storm": storm}


func _allocate(p: RefCounted, kind: String, id: String, count: int = 1) -> String:
	return p.allocate(kind, id, count, p.snapshot().revision)


func _run() -> void:
	var f: Dictionary = _fixture()
	var p: RefCounted = f.progression
	_check(p.level() == 1 and p.available_points() == 0 and p.stats().value("stat.power") == 100, "New character must start at level one with no earned points.")
	_check(p.award_xp("run.first", 1, 99).is_empty() and p.level() == 1, "XP below threshold must not grant a level.")
	_check(p.award_xp("run.first", 2, 1).is_empty() and p.level() == 2 and p.available_points() == 1, "Exact XP threshold must grant one level and point.")
	var before: Dictionary = p.snapshot()
	_check(not p.award_xp("run.first", 2, 100).is_empty() and not p.award_xp("run.first", 1, 100).is_empty(), "Repeated or older reward sequences must reject.")
	_check(not _allocate(p, "passives", "passive.mastery").is_empty(), "Minimum level and prerequisites must gate child allocation.")
	_check(not _allocate(p, "passives", "passive.power", 2).is_empty(), "Insufficient point budget must reject allocation.")
	_check(p.snapshot() == before, "Rejected rewards and allocations must preserve state.")
	_check(p.award_xp("run.first", 3, 900).is_empty() and p.level() == 5 and p.available_points() == 4, "One reward must handle multiple level gains.")
	_check(not _allocate(p, "passives", "passive.mastery").is_empty(), "Prerequisite ranks must gate allocation even after the level requirement is met.")
	_check(_allocate(p, "passives", "passive.power", 2).is_empty() and p.stats().value("stat.power") == 110, "Passive ranks must contribute through the shared resolver.")
	_check(_allocate(p, "passives", "passive.mastery").is_empty() and p.stats().value("stat.power") == 120, "Satisfied prerequisite must allow the child modifier.")
	var skill_id: String = f.storm.activation(Stormweaver.STATIC_WARD).content_id
	_check(_allocate(p, "skills", skill_id).is_empty() and p.skill_rank(skill_id) == 2 and p.available_points() == 0, "Skills and passives must spend one shared budget.")
	before = p.snapshot()
	var old_stats: RefCounted = p.stats()
	_check(not p.allocate("passives", "passive.power", -1, before.revision).is_empty(), "Negative allocation cannot implicitly refund a passive.")
	_check(not p.respec(before.revision - 1).is_empty(), "Stale respec must reject.")
	_check(not p.allocate("skills", skill_id, 1, before.revision - 1).is_empty(), "Stale UI allocation must reject.")
	_check(not _allocate(p, "skills", "ability.missing").is_empty(), "Unknown skill must reject.")
	_check(p.snapshot() == before and p.stats() == old_stats, "Rejected progression transactions must preserve published stats.")
	var next_run := Progression.new()
	next_run.configure("character.fixture", f.catalog, f.registry)
	_check(next_run.restore(JSON.parse_string(JSON.stringify(before))).is_empty(), "Progression must restore from a JSON snapshot for another run.")
	_check(next_run.snapshot() == before and next_run.stats().values() == p.stats().values(), "XP, skill/passive allocations and reward sequences must survive run restore.")
	_check(not next_run.award_xp("run.first", 3, 1000).is_empty(), "Restored reward watermark must prevent duplicate XP.")
	_check(next_run.award_xp("run.second", 1, 500).is_empty() and next_run.level() == 6, "New run rewards must build on persistent XP.")
	_check(not next_run.restore(before).is_empty(), "Live progression cannot rewind through restore.")
	_check(p.respec(before.revision).is_empty() and p.available_points() == 4 and p.skill_rank(skill_id) == 1 and p.stats().value("stat.power") == 100, "Explicit respec must refund both allocation families and remove passive effects.")
	_check(old_stats.value("stat.power") == 120 and p.passive_modifiers().is_empty(), "Old stat snapshots remain immutable and respec retires modifiers.")
	before = p.snapshot()
	_check(not _allocate(p, "passives", "passive.broken").is_empty() and p.snapshot() == before, "Unknown passive stat must roll back allocation and points.")
	_check(_allocate(p, "skills", skill_id, 4).is_empty() and p.skill_rank(skill_id) == 5, "Persistent skill ranks must reach authored milestones.")
	var upgraded := Stormweaver.new()
	_check(upgraded.configure({Stormweaver.STATIC_WARD: p.skill_rank(skill_id)}).is_empty(), "Persistent rank must configure the existing ability system.")
	_check(upgraded.rank_for(Stormweaver.STATIC_WARD) == 5 and upgraded.activation(Stormweaver.STATIC_WARD).effects_for_rank(5)[0].duration_ticks() == 360 and f.storm.activation(Stormweaver.STATIC_WARD).effects_for_rank(1)[0].duration_ticks() == 240, "Rank five must select the existing Ward milestone effects.")
	_check(p.award_xp("run.first", 4, 2147483647).is_empty() and p.level() == 20 and p.available_points() == 15, "XP at cap must clamp without extra level rewards.")
	before = p.snapshot()
	_check(not _allocate(p, "skills", skill_id, 16).is_empty() and p.snapshot() == before, "Skills must respect the rank-20 cap.")
	var capped_points: int = p.available_points()
	_check(p.award_xp("run.first", 5, 1000).is_empty() and p.available_points() == capped_points, "Further capped XP must not mint skill points.")
	var observations: Dictionary = p.snapshot()
	observations.skills.clear()
	_check(not p.snapshot().skills.is_empty(), "Progression snapshots must not alias allocations.")
	_test_restore(f)
	_test_catalog()
	_test_replay()
	f.root.modifiers[0].amount = 999
	f.child.prerequisites = {}
	f.curve.points_per_level = 999
	_check(f.root.modifiers[0].amount == 5 and not f.child.prerequisites.is_empty() and f.curve.points_per_level == 1, "Published progression content must remain frozen.")
	print(JSON.stringify({"fixture": "progression", "level": p.level(), "points": p.available_points(), "revision": p.snapshot().revision}))
	if failures.is_empty():
		print("Production progression contracts passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_restore(f: Dictionary) -> void:
	var valid: Dictionary = f.progression.snapshot()
	for mutation: Dictionary in [{"experience": -1}, {"experience": 1.5}, {"experience": 20000}, {"character_id": "character.other"}, {"skills": {"ability.unknown": 1}}, {"passives": {"passive.mastery": 1}}, {"passives": {"passive.power": 3}}, {"passives": {"passive.broken": 1}}, {"reward_sequences": {"run.first": 0}}, {"schema_version": 2}, {"revision": -1}, {"skills": {"ability.unknown": {}}}]:
		var state := Progression.new()
		state.configure("character.fixture", f.catalog, f.registry)
		var before: Dictionary = state.snapshot()
		var corrupted: Dictionary = valid.duplicate(true)
		corrupted.merge(mutation, true)
		_check(not state.restore(corrupted).is_empty() and state.snapshot() == before, "Corrupt restore must reject atomically.")
	var state := Progression.new()
	state.configure("character.fixture", f.catalog, f.registry)
	var overspent: Dictionary = valid.duplicate(true)
	overspent.experience = 0
	_check(not state.restore(overspent).is_empty(), "Restore must enforce earned point conservation.")


func _test_catalog() -> void:
	var a: Resource = _passive("passive.a", 1)
	var b: Resource = _passive("passive.b", 1)
	a.prerequisites = {"passive.b": 1}
	b.prerequisites = {"passive.a": 1}
	var curve: Resource = preload("res://game/simulation/progression/character_curve.tres")
	_check(not Catalog.new().load_definitions(curve, [], [a, b]).is_empty() and not a.is_frozen(), "Cyclic passive graphs must fail before freezing.")
	b.prerequisites = {"passive.missing": 1}
	_check(not Catalog.new().load_definitions(curve, [], [a, b]).is_empty(), "Unknown prerequisite must reject publication.")
	b.prerequisites = {}
	a.prerequisites = {"passive.b": 3}
	_check(not Catalog.new().load_definitions(curve, [], [a, b]).is_empty(), "Prerequisite rank cannot exceed the prerequisite cap.")

	var invalid_curve := preload("res://game/simulation/progression/progression_definition.gd").new()
	invalid_curve.xp_thresholds = [0, 100, 100]
	_check(not Catalog.new().load_definitions(invalid_curve, [], []).is_empty() and not invalid_curve.is_frozen(), "Non-increasing XP curves must reject before freeze.")


func _test_replay() -> void:
	var a: Dictionary = _fixture()
	var b: Dictionary = _fixture(true)
	for f: Dictionary in [a, b]:
		f.progression.award_xp("run.replay", 1, 1000)
		_allocate(f.progression, "passives", "passive.power", 2)
		_allocate(f.progression, "passives", "passive.mastery")
		f.progression.respec(f.progression.snapshot().revision)
		_allocate(f.progression, "passives", "passive.power")
	_check(a.progression.snapshot() == b.progression.snapshot() and a.progression.stats().values() == b.progression.stats().values(), "Replay must be deterministic regardless of catalog publication order.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
