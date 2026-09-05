extends SceneTree

const Simulation = preload("res://game/infrastructure/headless/build_simulation.gd")
const Build = preload("res://game/infrastructure/headless/build_loadout.gd")
const Gate = preload("res://game/infrastructure/headless/rarity_value_gate.gd")
const Candidates = preload("res://tests/fixtures/builds/reference_candidates.gd")
const GearFixture = preload("res://tests/fixtures/items/equipment_fixture.gd")
const Combat = preload("res://game/simulation/abilities/stormweaver_combat.gd")
const Snapshot = preload("res://game/simulation/stats/stat_snapshot.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Candidates.create()
	var before: Dictionary = fixture.world.snapshot()
	var reports: Array = []
	for profile: String in ["arc_bolt", "chain_lightning", "nova_ward", "storm_totem"]:
		var build := _build(profile)
		var result := Simulation.compare(build, fixture.world, fixture.bonuses)
		_check(result.error.is_empty(), "Reference comparison failed: " + result.error)
		if not result.error.is_empty():
			_finish()
			return
		reports.append(result.report)
		var repeated := Simulation.run(build, fixture.world, fixture.bonuses)
		_check(repeated.error.is_empty() and repeated.get("report") == result.report.baseline, "Identical loadouts must reproduce every metric and hash.")
	var gate := Gate.evaluate(reports)
	_check(gate.passed, "Reference gate failed: " + str(gate.errors))
	_check(reports[1].baseline.metrics.shock_peak == 3, "Chain profile must exercise real Shock stacking.")
	_check(reports[2].baseline.metrics.ward_ticks == 240, "Nova/Ward profile must exercise rank-scaled protection.")
	_check(reports[3].baseline.metrics.hits > 1, "Totem profile must execute repeated delivery pulses.")
	for report: Dictionary in reports:
		var incoming: int = report.baseline.metrics.damage_taken
		for candidate: Dictionary in report.slots[0].candidates:
			_check(candidate.error.is_empty(), "Every reference candidate must simulate.")
			if candidate.error.is_empty() and candidate.item.rarity != "green":
				_check(candidate.report.metrics.damage_taken == incoming, "Offensive gear must not change enemy stats or incoming damage.")
	_check(fixture.world.snapshot() == before, "Build comparisons must not mutate candidate items or allocate UIDs.")
	_test_multi_slot(fixture, reports)
	_test_injected_state()
	_test_selection(fixture)
	_test_invalid_inputs(fixture)
	_test_gate(reports)
	_test_equipment_conflict()
	var dominant := Candidates.create("red")
	var dominant_reports: Array = []
	for profile: String in ["arc_bolt", "chain_lightning", "nova_ward", "storm_totem"]:
		var result := Simulation.compare(_build(profile), dominant.world, dominant.bonuses)
		_check(result.error.is_empty(), "Dominant candidate must simulate.")
		if result.error.is_empty():
			dominant_reports.append(result.report)
	var rejected := Gate.evaluate(dominant_reports)
	_check(not rejected.passed and str(rejected.errors).contains("Red/set"), "Simulated all-red dominance must fail the gate.")
	print(JSON.stringify({"fixture": "build_simulation", "gate": gate, "dominance_rejected": not rejected.passed}))
	_finish()


func _test_multi_slot(fixture: Dictionary, reports: Array) -> void:
	var build := _build("arc_bolt")
	build.loadout["slot.head"] = {"uid": fixture.uids.head_white}
	var compared := Simulation.compare(build, fixture.world, fixture.bonuses)
	_check(compared.error.is_empty(), "Multi-slot Build must simulate.")
	if not compared.error.is_empty():
		return
	_check(compared.report.baseline.items.size() == 2 and compared.report.baseline.rarities.white == 2, "Composition must cover all equipped slots.")
	_check(compared.report.slots[1].winners.has(fixture.uids.head_red), "Red may provide a useful individual best slot.")
	var mixed := reports.duplicate(true)
	mixed[0] = compared.report
	_check(Gate.evaluate(mixed).passed, "One high-rarity best slot must not fail a mixed Build.")


func _test_injected_state() -> void:
	var catalog := Combat.Catalog.new()
	_check(catalog.configure().is_empty(), "Injection catalog must configure.")
	var environment := Combat.Movement.new()
	_check(environment.configure(Rect2(-100, -100, 200, 200), [], 2, 120).is_empty(), "Injection environment must configure.")
	var actor := Combat.Entity.new()
	_check(actor.configure(1, "actor.injection", true, Vector2.ZERO, 100, 100, 100, 100).is_empty(), "Injection actor must configure.")
	var combat := Combat.new()
	_check(combat.configure([actor], environment, catalog, 1, {}, {}, Snapshot.new()).contains("published StatSnapshot"), "Unpublished player stats must fail at the injection boundary.")
	var values: Dictionary = catalog.default_stats().values()
	values[Combat.Catalog.CRIT] = 0.96
	var invalid := Snapshot.new()
	invalid._configure(0, values, {})
	_check(combat.configure([actor], environment, catalog, 1, {}, {}, invalid).contains("supported ranges"), "Invalid critical stats must fail before the first attack.")
	var modifier := Combat.DamageModifier.new()
	_check(modifier.configure("damage.lightning", Combat.DamageModifier.Operation.DEFENSE, 10, "source.injected").is_empty(), "Injection modifier must configure.")
	_check(combat.configure([actor], environment, catalog, 1, {}, {}, null, [modifier, modifier]).contains("distinct"), "Duplicate mitigation must fail before publication.")
	_check(combat.configure([actor], environment, catalog, 1, {}, {}, catalog.default_stats(), [modifier]).is_empty(), "Rejected inputs must leave combat reusable.")
	_check(combat.advance_tick().is_empty(), "Injected snapshots must rebase to the execution tick.")


func _test_selection(fixture: Dictionary) -> void:
	var build := _build("arc_bolt")
	build.loadout["slot.weapon"] = {"bases": ["item.reference.green"], "affixes": ["affix.reference.a2"], "rarities": ["green"]}
	var resolved := Build.resolve(build, fixture.world)
	_check(resolved.error.is_empty() and resolved.slots["slot.weapon"] == fixture.uids.green, "Base, affix, and rarity constraints must all apply.")
	var exact := build.duplicate(true)
	exact.loadout["slot.weapon"] = {"uid": fixture.uids.green}
	_check(Simulation.run(build, fixture.world, fixture.bonuses) == Simulation.run(exact, fixture.world, fixture.bonuses), "Exact and equivalent constrained loadouts must simulate identically.")
	build.loadout["slot.weapon"].rarities = ["red"]
	_check(not Build.resolve(build, fixture.world).error.is_empty(), "Unsatisfied constraints must not silently fall back.")
	build.loadout["slot.weapon"] = {"bases": [], "affixes": [], "rarities": []}
	var selected := Build.resolve(build, fixture.world)
	_check(selected.slots["slot.weapon"] == "profile.reference:1", "Unconstrained selection must use lexical UID order.")
	var reordered: RefCounted = Candidates.Fixture.World.new()
	_check(reordered.configure("profile.reference", fixture.world.item_catalog()).is_empty(), "Cloned pool must configure.")
	_check(reordered.restore(fixture.world.snapshot()).is_empty(), "Cloned pool must restore.")
	# Native dictionaries can arrive in a different iteration order after loading.
	var reversed: Dictionary = {}
	var keys: Array = reordered._items.keys()
	keys.reverse()
	for key: String in keys:
		reversed[key] = reordered._items[key]
	reordered._items = reversed
	_check(Build.resolve(build, reordered) == selected, "Candidate iteration order must not choose the baseline.")


func _test_invalid_inputs(fixture: Dictionary) -> void:
	var invalid: Array = [null, [], {}, {"schema_version": 99}]
	for field: String in Build.FIELDS:
		var missing := _build("arc_bolt")
		missing.erase(field)
		invalid.append(missing)
	for row: Array in [["schema_version", 1.5], ["root_seed", 42.5], ["duration_ticks", 0], ["duration_ticks", 3601], ["skills", {"arc_bolt": 21}], ["skills", {"unknown": 1}], ["conditions", ["bad"]], ["objective", "rarity"], ["rotation", [{"tick": 1, "skill": "storm_totem"}]], ["loadout", {"slot.weapon": {"uid": "missing"}}], ["loadout", {"slot.weapon": {"bases": ["item.missing"], "affixes": [], "rarities": []}}]]:
		var changed := _build("arc_bolt")
		changed[row[0]] = row[1]
		invalid.append(changed)
	for value: Variant in invalid:
		_check(not Simulation.run(value, fixture.world).error.is_empty(), "Malformed Build must return a diagnostic.")
	var bad_stats := _build("arc_bolt")
	bad_stats.base_stats[Build.STATS[0]] = NAN
	_check(not Build.validate(bad_stats, fixture.world).is_empty(), "Non-finite stats must be rejected before simulation.")
	var invalid_rotation := _build("arc_bolt")
	invalid_rotation.rotation = [{"tick": 1, "skill": "arc_bolt"}, {"tick": 2, "skill": "arc_bolt"}]
	_check(not Simulation.run(invalid_rotation, fixture.world).error.is_empty(), "Overlapping casts must fail through the real command runtime.")
	invalid_rotation.rotation = [{"tick": 239, "skill": "arc_bolt"}]
	_check(not Simulation.run(invalid_rotation, fixture.world).error.is_empty(), "Out-of-window releases must fail.")



func _test_gate(reports: Array) -> void:
	_check(not Gate.evaluate([]).passed, "Empty gate input must fail.")
	_check(not Gate.evaluate([reports[0], reports[0], reports[2], reports[3]]).passed, "Duplicate and missing reference profiles must fail.")
	var future := reports.duplicate(true)
	future[0].schema_version = 2
	_check(not Gate.evaluate(future).passed, "Unknown comparison schema versions must fail closed.")
	var ties := reports.duplicate(true)
	for candidate: Dictionary in ties[0].slots[0].candidates:
		if candidate.item.rarity == "red":
			candidate.report.metrics.damage_dealt = ties[0].slots[0].best_score
	_check(not Gate.evaluate(ties).passed, "A red best-score tie must count as dominance regardless of cached winner IDs.")
	var sets := ties.duplicate(true)
	for candidate: Dictionary in sets[0].slots[0].candidates:
		if candidate.item.rarity == "red":
			candidate.item.rarity = "set"
	_check(not Gate.evaluate(sets).passed, "Set dominance must fail too.")
	var omitted := reports.duplicate(true)
	omitted[0].build.loadout["slot.head"] = {"uid": "missing"}
	_check(not Gate.evaluate(omitted).passed, "Omitting an equipped slot must fail.")
	var no_challenger := reports.duplicate(true)
	no_challenger[0].slots[0].candidates = no_challenger[0].slots[0].candidates.filter(func(c: Dictionary) -> bool: return not c.item.rarity in ["red", "set"])
	_check(not Gate.evaluate(no_challenger).passed, "A pool without high-rarity challengers cannot prove diversity.")
	var bad := reports.duplicate(true)
	bad[0].slots[0].candidates[0].report.metrics.damage_dealt = INF
	_check(not Gate.evaluate(bad).passed, "Non-finite metrics must fail the gate.")
	bad = reports.duplicate(true)
	bad[0].slots[0].candidates[0] = {"error": "Unsupported candidate"}
	_check(not Gate.evaluate(bad).passed, "Failed candidates cannot disappear from the gate.")


func _test_equipment_conflict() -> void:
	var fixture := GearFixture.create()
	var build := _build("arc_bolt")
	build.loadout = {"slot.weapon": {"uid": fixture.two_handed.uid()}, "slot.off_hand": {"uid": fixture.items["slot.off_hand"].uid()}}
	var result := Simulation.run(build, fixture.world)
	_check(not result.error.is_empty() and result.error.contains("two-handed"), "Build loader must preserve two-handed/off-hand exclusion.")


func _build(profile: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/builds/%s.json" % profile))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("Production Build simulation tests passed.")
	quit(0 if failures.is_empty() else 1)
