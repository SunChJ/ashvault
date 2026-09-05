class_name RarityValueGate
extends RefCounted

const REQUIRED_BUILDS := ["build.reference.arc_bolt", "build.reference.chain_lightning", "build.reference.nova_ward", "build.reference.storm_totem"]
const REQUIRED_RARITIES := ["blue", "gold", "green", "purple"]
const Build = preload("res://game/infrastructure/headless/build_loadout.gd")


static func evaluate(reports: Array) -> Dictionary:
	var errors: Array[String] = []
	var coverage: Dictionary = {}
	var observed: Array = []
	for report: Variant in reports:
		if not report is Dictionary or not Build.integer(report.get("schema_version"), 1, 1) or not report.get("build") is Dictionary or not report.build.get("build_id") is String or not report.get("slots") is Array or report.slots.is_empty():
			errors.append("Rarity gate requires non-empty comparison reports.")
			continue
		var id: String = report.build.build_id
		if observed.has(id) or not REQUIRED_BUILDS.has(id):
			errors.append("Unexpected or duplicate reference Build: " + id)
		observed.append(id)
		if not Build.OBJECTIVES.has(report.build.get("objective")):
			errors.append("Comparison objective is invalid.")
			continue
		var all_high := true
		var seen_slots: Array = []
		for slot: Variant in report.slots:
			if not slot is Dictionary or not slot.get("slot") is String or not slot.get("candidates") is Array or slot.candidates.is_empty():
				errors.append("Comparison slot requires candidates.")
				continue
			if seen_slots.has(slot.slot):
				errors.append("Duplicate comparison slot.")
			seen_slots.append(slot.slot)
			var best := -INF
			var winners: Array = []
			var seen_uids: Array = []
			var has_high_candidate := false
			for candidate: Variant in slot.candidates:
				if not candidate is Dictionary or candidate.get("error", "missing") != "" or not candidate.get("item") is Dictionary or not candidate.get("report") is Dictionary or not candidate.report.get("metrics") is Dictionary:
					errors.append("Failed or malformed candidate makes the gate inconclusive.")
					continue
				var item: Dictionary = candidate.item
				if not item.get("uid") is String or not item.get("rarity") is String or seen_uids.has(item.uid):
					errors.append("Candidate identity is invalid or duplicated.")
					continue
				seen_uids.append(item.uid)
				has_high_candidate = has_high_candidate or item.rarity in ["red", "set"]
				var metrics: Dictionary = candidate.report.metrics
				var metric: String = {"damage": "damage_dealt", "defense": "damage_taken", "procs": "proc_events"}[report.build.objective]
				var amount: Variant = metrics.get(metric)
				if not (amount is int or amount is float) or not is_finite(amount) or amount < 0:
					errors.append("Candidate objective metric is invalid.")
					continue
				var score: float = -float(amount) if metric == "damage_taken" else float(amount)
				if score > best:
					best = score
					winners = [item]
				elif score == best:
					winners.append(item)
			if not has_high_candidate:
				errors.append("Every compared slot requires a red or set challenger.")
			if winners.is_empty():
				errors.append("Comparison slot has no valid winner.")
			var high_wins := false
			for winner: Dictionary in winners:
				high_wins = high_wins or winner.rarity in ["red", "set"]
				if not coverage.has(winner.rarity):
					coverage[winner.rarity] = []
				coverage[winner.rarity].append({"build_id": id, "slot": slot.slot, "uid": winner.uid, "score": best})
			all_high = all_high and high_wins
		if not report.build.get("loadout") is Dictionary or seen_slots.size() != report.build.loadout.size():
			errors.append("Gate must cover every occupied baseline slot.")
		else:
			for slot: Variant in report.build.loadout:
				if not seen_slots.has(slot):
					errors.append("Gate omitted an occupied baseline slot.")
		if all_high:
			errors.append("Red/set candidates can fill every best slot in " + id)
	for id: String in REQUIRED_BUILDS:
		if not observed.has(id):
			errors.append("Missing reference Build: " + id)
	for rarity: String in REQUIRED_RARITIES:
		if not coverage.has(rarity):
			errors.append("No best-slot evidence for " + rarity)
	return {"schema_version": 1, "passed": errors.is_empty(), "errors": errors, "coverage": coverage,
		"scope": "authored candidate pool; fixed-baseline single-slot comparisons; ties count as dominance"}
