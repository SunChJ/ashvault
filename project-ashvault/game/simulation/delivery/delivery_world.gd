class_name DeliveryWorld
extends RefCounted

const DefinitionContract = preload(
	"res://game/simulation/delivery/delivery_definition.gd"
)
const Hit = preload("res://game/simulation/delivery/delivery_hit.gd")
const RequestContract = preload(
	"res://game/simulation/delivery/delivery_request.gd"
)
const RuntimeState = preload(
	"res://game/simulation/delivery/delivery_runtime_state.gd"
)
const TargetContract = preload(
	"res://game/simulation/delivery/delivery_target.gd"
)
const TickResult = preload(
	"res://game/simulation/delivery/delivery_tick_result.gd"
)

const FIXED_TICKS_PER_SECOND := 60
const FIXED_DELTA_SECONDS := 1.0 / float(FIXED_TICKS_PER_SECOND)
const STATE_HASH_SCHEMA_VERSION := 1

var _tick := -1
var _next_runtime_id := 0
var _active_states: Dictionary = {}
var _last_request_id := 0
var _state_hash := ""
var _is_configured := false


func configure(initial_tick: int = 0, next_runtime_id: int = 1) -> String:
	if _is_configured:
		return "Delivery world is already configured."
	if initial_tick < 0 or next_runtime_id <= 0:
		return "Delivery initial tick must be non-negative and runtime ID must be positive."
	_tick = initial_tick
	_next_runtime_id = next_runtime_id
	_active_states = {}
	_last_request_id = 0
	_state_hash = ""
	_is_configured = true
	return ""


func tick() -> int:
	return _tick


func active_count() -> int:
	return _active_states.size()


func active_values() -> Array:
	var values: Array = []
	for runtime_id: int in _sorted_ids(_active_states):
		values.append(_active_states[runtime_id].canonical_values())
	return values


func state_hash() -> String:
	if not _is_configured:
		return ""
	if _state_hash.is_empty():
		var canonical := [
			STATE_HASH_SCHEMA_VERSION,
			FIXED_TICKS_PER_SECOND,
			_tick,
			_next_runtime_id,
			_last_request_id,
			active_values(),
		]
		var context := HashingContext.new()
		var start_error := context.start(HashingContext.HASH_SHA256)
		assert(start_error == OK, "SHA-256 hashing must be available.")
		var update_error := context.update(JSON.stringify(canonical).to_utf8_buffer())
		assert(update_error == OK, "Delivery state hashing must accept UTF-8 input.")
		_state_hash = context.finish().hex_encode()
	return _state_hash


func advance_tick(targets: Array, requests: Array = []) -> RefCounted:
	var expected_tick := _tick + 1
	if not _is_configured:
		return _rejected(expected_tick, "delivery.unconfigured", "Delivery world is not configured.")
	var target_result := _validated_targets(targets)
	if not target_result["error"].is_empty():
		return _rejected(expected_tick, "delivery.invalid_targets", target_result["error"])
	var request_result := _validated_requests(requests)
	if not request_result["error"].is_empty():
		return _rejected(expected_tick, "delivery.invalid_requests", request_result["error"])

	var target_values: Array = target_result["targets"]
	var sorted_requests: Array = request_result["requests"]
	var staged_states: Dictionary = {}
	for runtime_id: int in _sorted_ids(_active_states):
		staged_states[runtime_id] = _active_states[runtime_id]._duplicate_state()
	var staged_last_request_id := _last_request_id
	var staged_next_runtime_id := _next_runtime_id
	var hits: Array = []
	var spawned_ids: Array = []
	var expired_ids: Array = []

	for runtime_id: int in _sorted_ids(staged_states):
		var state: RefCounted = staged_states[runtime_id]
		if state.kind() == DefinitionContract.Kind.PROJECTILE:
			_advance_projectile(state, expected_tick, target_values, hits)
			if state.hit_count() >= state.max_targets() or expected_tick >= state.expiry_tick():
				staged_states.erase(runtime_id)
				expired_ids.append(runtime_id)
		elif state.kind() == DefinitionContract.Kind.PERSISTENT:
			if expected_tick >= state.expiry_tick():
				staged_states.erase(runtime_id)
				expired_ids.append(runtime_id)
			elif expected_tick >= state.next_pulse_tick():
				_append_area_hits(state, expected_tick, target_values, hits)
				state._advance_pulse()

	for request: RefCounted in sorted_requests:
		staged_last_request_id = request.request_id()
		var definition: Resource = request.definition()
		match definition.kind():
			DefinitionContract.Kind.PROJECTILE:
				var projectile := RuntimeState.new()
				projectile._configure(staged_next_runtime_id, request, expected_tick)
				staged_states[staged_next_runtime_id] = projectile
				spawned_ids.append(staged_next_runtime_id)
				staged_next_runtime_id += 1
			DefinitionContract.Kind.PERSISTENT:
				var persistent := RuntimeState.new()
				persistent._configure(staged_next_runtime_id, request, expected_tick)
				staged_states[staged_next_runtime_id] = persistent
				spawned_ids.append(staged_next_runtime_id)
				_append_area_hits(persistent, expected_tick, target_values, hits)
				persistent._advance_pulse()
				staged_next_runtime_id += 1
			DefinitionContract.Kind.AREA:
				_append_request_area_hits(request, expected_tick, target_values, hits)
			DefinitionContract.Kind.CHAIN:
				_append_chain_hits(request, expected_tick, target_values, hits)

	_tick = expected_tick
	_next_runtime_id = staged_next_runtime_id
	_active_states = staged_states
	_last_request_id = staged_last_request_id
	_state_hash = ""
	return _result(_tick, true, hits, spawned_ids, expired_ids, _active_states.size(), [])


func _validated_targets(values: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for index in values.size():
		var value: Variant = values[index]
		if not value is TargetContract or not value.is_configured():
			return {"targets": [], "error": "Target at index %d is not configured." % index}
		if by_id.has(value.runtime_id()):
			return {"targets": [], "error": "Duplicate target runtime ID %d." % value.runtime_id()}
		by_id[value.runtime_id()] = value
	var target_ids: Array = by_id.keys()
	target_ids.sort()
	var result: Array = []
	for target_id: int in target_ids:
		result.append(by_id[target_id])
	return {"targets": result, "error": ""}


func _validated_requests(values: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for index in values.size():
		var value: Variant = values[index]
		if not value is RequestContract or not value.is_configured():
			return {"requests": [], "error": "Request at index %d is not configured." % index}
		if value.request_id() <= _last_request_id or by_id.has(value.request_id()):
			return {
				"requests": [],
				"error": (
					"Delivery request ID %d must be unique and greater than %d."
					% [value.request_id(), _last_request_id]
				),
			}
		by_id[value.request_id()] = value
	var request_ids: Array = by_id.keys()
	request_ids.sort()
	var result: Array = []
	for request_id: int in request_ids:
		result.append(by_id[request_id])
	return {"requests": result, "error": ""}


func _advance_projectile(
	state: RefCounted,
	current_tick: int,
	targets: Array,
	hits: Array
) -> void:
	var start: Vector2 = state._move_projectile(FIXED_DELTA_SECONDS)
	var candidates: Array = []
	for target: RefCounted in targets:
		if not _is_eligible_target(target, state.source_entity_id(), state.source_team_id()):
			continue
		if state.has_hit_target(target.runtime_id()):
			continue
		var contact_time: float = _segment_circle_contact_time(
			start,
			state.position(),
			target.position(),
			state.radius() + target.collision_radius()
		)
		if contact_time < 0.0:
			continue
		candidates.append({"time": contact_time, "target": target})
	candidates.sort_custom(_contact_precedes)
	var remaining_hits: int = state.max_targets() - state.hit_count()
	for candidate: Dictionary in candidates:
		if remaining_hits <= 0:
			break
		var target: RefCounted = candidate["target"]
		var ordinal: int = state.hit_count()
		state._record_hit(target.runtime_id())
		var impact_position: Vector2 = start.lerp(state.position(), candidate["time"])
		hits.append(_hit_from_state(state, current_tick, target, impact_position, ordinal))
		remaining_hits -= 1


func _append_request_area_hits(
	request: RefCounted,
	current_tick: int,
	targets: Array,
	hits: Array
) -> void:
	var definition: Resource = request.definition()
	var selected := _targets_in_radius(
		targets,
		request.origin(),
		definition.radius(),
		request.source_entity_id(),
		request.source_team_id(),
		definition.max_targets(),
		{}
	)
	for index in selected.size():
		var target: RefCounted = selected[index]
		hits.append(_hit_from_request(request, current_tick, target, target.position(), index))


func _append_area_hits(
	state: RefCounted,
	current_tick: int,
	targets: Array,
	hits: Array
) -> void:
	var selected := _targets_in_radius(
		targets,
		state.position(),
		state.radius(),
		state.source_entity_id(),
		state.source_team_id(),
		state.max_targets(),
		{}
	)
	for index in selected.size():
		var target: RefCounted = selected[index]
		hits.append(_hit_from_state(state, current_tick, target, target.position(), index))


func _append_chain_hits(
	request: RefCounted,
	current_tick: int,
	targets: Array,
	hits: Array
) -> void:
	var definition: Resource = request.definition()
	var excluded: Dictionary = {}
	var current: RefCounted = null
	if request.primary_target_id() > 0:
		for target: RefCounted in targets:
			if target.runtime_id() != request.primary_target_id():
				continue
			if (
				_is_eligible_target(target, request.source_entity_id(), request.source_team_id())
				and _within_radius(request.origin(), target, definition.acquisition_range())
			):
				current = target
			break
	if current == null:
		var acquired := _targets_in_radius(
			targets,
			request.origin(),
			definition.acquisition_range(),
			request.source_entity_id(),
			request.source_team_id(),
			1,
			excluded
		)
		if acquired.is_empty():
			return
		current = acquired[0]

	for ordinal in definition.max_targets():
		hits.append(_hit_from_request(request, current_tick, current, current.position(), ordinal))
		excluded[current.runtime_id()] = true
		var next_targets := _targets_in_radius(
			targets,
			current.position(),
			definition.chain_range(),
			request.source_entity_id(),
			request.source_team_id(),
			1,
			excluded
		)
		if next_targets.is_empty():
			break
		current = next_targets[0]


func _targets_in_radius(
	targets: Array,
	origin: Vector2,
	radius: float,
	source_entity_id: int,
	source_team_id: int,
	max_targets: int,
	excluded: Dictionary
) -> Array:
	var candidates: Array = []
	for target: RefCounted in targets:
		if excluded.has(target.runtime_id()):
			continue
		if not _is_eligible_target(target, source_entity_id, source_team_id):
			continue
		if not _within_radius(origin, target, radius):
			continue
		candidates.append({
			"distance_squared": origin.distance_squared_to(target.position()),
			"target": target,
		})
	candidates.sort_custom(_distance_precedes)
	var result: Array = []
	for candidate: Dictionary in candidates:
		if max_targets > 0 and result.size() >= max_targets:
			break
		result.append(candidate["target"])
	return result


static func _is_eligible_target(
	target: RefCounted,
	source_entity_id: int,
	source_team_id: int
) -> bool:
	return (
		target.is_alive()
		and target.runtime_id() != source_entity_id
		and target.team_id() != source_team_id
	)


static func _within_radius(origin: Vector2, target: RefCounted, radius: float) -> bool:
	var effective_radius: float = radius + target.collision_radius()
	return origin.distance_squared_to(target.position()) <= effective_radius * effective_radius


static func _segment_circle_contact_time(
	start: Vector2,
	end: Vector2,
	center: Vector2,
	radius: float
) -> float:
	var offset := start - center
	var radius_squared := radius * radius
	if offset.length_squared() <= radius_squared:
		return 0.0
	var displacement := end - start
	var coefficient := displacement.length_squared()
	if coefficient <= 0.0:
		return -1.0
	var linear := 2.0 * offset.dot(displacement)
	var constant := offset.length_squared() - radius_squared
	var discriminant: float = linear * linear - 4.0 * coefficient * constant
	var discriminant_scale: float = absf(linear * linear) + absf(
		4.0 * coefficient * constant
	)
	var discriminant_tolerance: float = maxf(1.0, discriminant_scale) * 0.000001
	if discriminant < -discriminant_tolerance:
		return -1.0
	discriminant = maxf(0.0, discriminant)
	var contact := (-linear - sqrt(discriminant)) / (2.0 * coefficient)
	if contact < 0.0 or contact > 1.0:
		return -1.0
	return contact


static func _contact_precedes(left: Dictionary, right: Dictionary) -> bool:
	if not is_equal_approx(left["time"], right["time"]):
		return left["time"] < right["time"]
	return left["target"].runtime_id() < right["target"].runtime_id()


static func _distance_precedes(left: Dictionary, right: Dictionary) -> bool:
	if not is_equal_approx(left["distance_squared"], right["distance_squared"]):
		return left["distance_squared"] < right["distance_squared"]
	return left["target"].runtime_id() < right["target"].runtime_id()


static func _hit_from_request(
	request: RefCounted,
	tick_value: int,
	target: RefCounted,
	impact_position: Vector2,
	ordinal: int
) -> RefCounted:
	var result := Hit.new()
	result._configure(
		tick_value,
		request.request_id(),
		0,
		request.definition().definition_id(),
		request.definition().kind(),
		request.source_entity_id(),
		target.runtime_id(),
		impact_position,
		ordinal
	)
	return result


static func _hit_from_state(
	state: RefCounted,
	tick_value: int,
	target: RefCounted,
	impact_position: Vector2,
	ordinal: int
) -> RefCounted:
	var result := Hit.new()
	result._configure(
		tick_value,
		state.request_id(),
		state.runtime_id(),
		state.definition_id(),
		state.kind(),
		state.source_entity_id(),
		target.runtime_id(),
		impact_position,
		ordinal
	)
	return result


static func _sorted_ids(values: Dictionary) -> Array:
	var result: Array = values.keys()
	result.sort()
	return result


func _rejected(tick_value: int, code: String, message: String) -> RefCounted:
	return _result(
		tick_value,
		false,
		[],
		[],
		[],
		_active_states.size(),
		[{"code": code, "tick": tick_value, "message": message}]
	)


static func _result(
	tick_value: int,
	is_success: bool,
	hits: Array,
	spawned_ids: Array,
	expired_ids: Array,
	active_count_value: int,
	diagnostics: Array
) -> RefCounted:
	var result := TickResult.new()
	result._configure(
		tick_value,
		is_success,
		hits,
		spawned_ids,
		expired_ids,
		active_count_value,
		diagnostics
	)
	return result
