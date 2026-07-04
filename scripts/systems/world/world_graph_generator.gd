class_name WorldGraphGenerator
extends RefCounted

const WorldGenerationProfileScript := preload("res://scripts/systems/world/world_generation_profile.gd")
const WorldGraphBlueprintScript := preload("res://scripts/systems/world/world_graph_blueprint.gd")
const WildTerrainProfileScript := preload("res://scripts/systems/terrain/wild_terrain_profile.gd")

var _rng := RandomNumberGenerator.new()
var _config: Dictionary = {}
var _world_id: String = ""
var _world_seed: int = 0
var _region_profile_id: String = ""
var _warnings: Array[String] = []
var _errors: Array[String] = []
var _node_rows: Array[Dictionary] = []
var _spawn_rows: Array[Dictionary] = []
var _edge_rows: Array[Dictionary] = []
var _undirected_pairs: Dictionary = {}
var _edge_sequence: int = 0
var _start_spawn_id: String = ""


func generate_blueprint(input: Dictionary) -> RefCounted:
	var world_data := generate_world_data(input)
	var blueprint: RefCounted = WorldGraphBlueprintScript.new()
	blueprint.configure(world_data)
	return blueprint


func generate_world_data(input: Dictionary) -> Dictionary:
	var result := generate_world_data_result(input)
	if not bool(result.get("success", false)):
		return {}
	return (result.get("world_data", {}) as Dictionary).duplicate(true)


func generate_world_data_result(input: Dictionary) -> Dictionary:
	_reset(input)
	if not _validate_config():
		return _failure_result()

	var node_count := _node_count()
	if node_count <= 0:
		return _failure_result()
	if not _add_start_node():
		return _failure_result()
	for index in range(1, node_count):
		if not _add_generated_node(index):
			return _failure_result()

	_generate_connected_edges()
	_generate_extra_edges()

	var world_data := {
		"world_id": _world_id,
		"world_seed": _world_seed,
		"region_profile_id": _region_profile_id,
		"start_location_id": str(_node_rows[0].get("location_id", "")),
		"start_spawn_id": _start_spawn_id,
		"locations": _node_rows.duplicate(true),
		"spawns": _spawn_rows.duplicate(true),
		"exits": _edge_rows.duplicate(true),
		"generator_metadata": {
			"generator": "WorldGraphGenerator",
			"algorithm": "seeded_weighted_local_connected_graph",
			"profiles_are_candidate_pools": true,
			"region_profile_id": _region_profile_id,
		},
	}
	world_data["debug_summary"] = _debug_summary(world_data)

	var blueprint: RefCounted = WorldGraphBlueprintScript.new()
	blueprint.configure(world_data)
	var validation_errors: Array[String] = blueprint.validate()
	if not validation_errors.is_empty():
		_errors.append_array(validation_errors)
		return _failure_result(world_data)

	return {
		"success": true,
		"world_data": world_data,
		"errors": [],
		"warnings": _warnings.duplicate(),
	}


func _reset(input: Dictionary) -> void:
	_config = WorldGenerationProfileScript.resolve_generation_config(input)
	_world_seed = int(_config.get("world_seed", _config.get("seed", 6501)))
	_world_id = str(_config.get("world_id", "generated_world_%d" % _world_seed))
	_region_profile_id = str(_config.get("region_profile_id", _config.get("profile_id", "")))
	_rng.seed = _stable_seed(_world_seed, _region_profile_id)
	_warnings.clear()
	_errors.clear()
	_node_rows.clear()
	_spawn_rows.clear()
	_edge_rows.clear()
	_undirected_pairs.clear()
	_edge_sequence = 0
	_start_spawn_id = ""


func _validate_config() -> bool:
	if _world_id.is_empty():
		_errors.append("world_id is missing")
	if _region_profile_id.is_empty():
		_errors.append("region_profile_id is missing")
	if _config.has("_profile_found") and not bool(_config.get("_profile_found", true)):
		_errors.append(str(_config.get("_profile_load_error", "world generation profile is missing")))

	var start_policy := str(_config.get("start_location_policy", ""))
	if start_policy.is_empty():
		_errors.append("start_location_policy is missing")
	elif start_policy != "generated_wild":
		_errors.append("unsupported start_location_policy: %s" % start_policy)

	var node_range: Array = _config.get("node_count_range", []) as Array
	if node_range.size() < 2:
		_errors.append("node_count_range must contain min and max values")
	else:
		var min_count := int(node_range[0])
		var max_count := int(node_range[1])
		if min_count < 1 or max_count < min_count:
			_errors.append("node_count_range is invalid: %s" % str(node_range))

	var location_kinds := _string_array(_config.get("available_location_kinds", []) as Array)
	if location_kinds.is_empty():
		_errors.append("available_location_kinds is empty")
	else:
		var kind_weights := _kind_weights()
		var supported_weight := 0.0
		for kind in location_kinds:
			var weight := maxf(0.0, float(kind_weights.get(kind, 0.0)))
			if not _is_supported_location_kind(kind) and weight > 0.0:
				_errors.append("unsupported location kind has positive weight: %s" % kind)
			if _is_supported_location_kind(kind):
				supported_weight += weight
		if supported_weight <= 0.0:
			_errors.append("no supported location kind has positive weight")

	_validate_wild_profiles()

	var size_ranges: Dictionary = _config.get("size_ranges", {}) as Dictionary
	var wild_sizes: Array = size_ranges.get("generated_wild", []) as Array
	if wild_sizes.is_empty():
		_errors.append("size_ranges.generated_wild is empty")
	return _errors.is_empty()


func _validate_wild_profiles() -> void:
	var wild_profiles := _available_wild_profiles()
	if wild_profiles.is_empty():
		_errors.append("available_wild_profiles is empty")
		return
	var supported_profiles := WildTerrainProfileScript.supported_profile_ids()
	var total_wild_weight := 0.0
	var wild_weights := _wild_profile_weights()
	for profile_id in wild_profiles:
		if not supported_profiles.has(profile_id):
			_errors.append("unsupported wild terrain profile: %s" % profile_id)
		total_wild_weight += maxf(0.0, float(wild_weights.get(profile_id, 0.0)))
	if total_wild_weight <= 0.0:
		_errors.append("wild_profile_weights has no positive candidate weight")


func _node_count() -> int:
	var range_values: Array = _config.get("node_count_range", []) as Array
	if range_values.size() < 2:
		return 0
	var min_count := int(range_values[0])
	var max_count := int(range_values[1])
	if min_count < 1 or max_count < min_count:
		return 0
	return _rng.randi_range(min_count, max_count)


func _add_start_node() -> bool:
	var start_policy := str(_config.get("start_location_policy", ""))
	if start_policy != "generated_wild":
		_errors.append("unsupported start_location_policy: %s" % start_policy)
		return false
	return _add_generated_node(0, "generated_wild", true)


func _add_generated_node(index: int, forced_kind: String = "", is_start: bool = false) -> bool:
	var location_kind := forced_kind
	if location_kind.is_empty():
		location_kind = _pick_location_kind()
	if location_kind.is_empty():
		return false
	if not _is_supported_location_kind(location_kind):
		_errors.append("unsupported location kind: %s" % location_kind)
		return false

	match location_kind:
		"generated_wild":
			return _add_generated_wild_node(index, is_start)
		_:
			_errors.append("unsupported location kind: %s" % location_kind)
			return false


func _add_generated_wild_node(index: int, is_start: bool) -> bool:
	var wild_profile_id := _pick_wild_profile()
	if wild_profile_id.is_empty():
		return false
	var size := _pick_size("generated_wild")
	if size.is_empty():
		return false
	var location_id := "%s_node_%03d" % [_world_id, index]
	var seed := _derive_node_seed(index, wild_profile_id)
	var spawn_id := "%s_spawn" % location_id if is_start else "%s_entry" % location_id
	_node_rows.append({
		"location_id": location_id,
		"display_name": _display_name_for_wild_profile(wild_profile_id, index),
		"location_kind": "generated_wild",
		"source_type": "generated",
		"generator_id": "wild_terrain",
		"generator_profile_id": wild_profile_id,
		"seed": seed,
		"size": size,
		"metadata": {
			"source": "world_graph_generator",
			"region_profile_id": _region_profile_id,
			"world_node_role": _wild_role_for_profile(wild_profile_id),
			"node_index": index,
		},
	})
	_spawn_rows.append({
		"location_id": location_id,
		"spawn_id": spawn_id,
		"entrance_id": spawn_id,
		"facing": "down",
		"tags": ["generated_world_graph", "start"] if is_start else ["generated_world_graph", "entry"],
	})
	if is_start:
		_start_spawn_id = spawn_id
	return true


func _generate_connected_edges() -> void:
	if _node_rows.size() <= 1:
		return
	for index in range(1, _node_rows.size()):
		var target_index := index - 1
		if index > 1 and _rng.randf() < float(_config.get("branchiness", 0.45)):
			target_index = _rng.randi_range(0, index - 1)
		_add_bidirectional_edge(target_index, index, "tree")


func _generate_extra_edges() -> void:
	var node_count := _node_rows.size()
	if node_count <= 2:
		return
	var connection_density := maxf(1.0, float(_config.get("connection_density", 1.0)))
	var desired_undirected_edges: int = maxi(node_count - 1, int(round(float(node_count - 1) * connection_density)))
	var max_undirected_edges: int = int(node_count * (node_count - 1) / 2)
	desired_undirected_edges = mini(desired_undirected_edges, max_undirected_edges)
	var candidates: Array[Dictionary] = []
	for a in range(node_count):
		for b in range(a + 1, node_count):
			var pair_key := "%d::%d" % [a, b]
			if _undirected_pairs.has(pair_key):
				continue
			candidates.append({
				"a": a,
				"b": b,
				"score": _stable_pair_jitter(a, b, 1723),
			})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left.get("score", 0.0)) == float(right.get("score", 0.0)):
			return "%d:%d" % [int(left.get("a", 0)), int(left.get("b", 0))] < "%d:%d" % [int(right.get("a", 0)), int(right.get("b", 0))]
		return float(left.get("score", 0.0)) < float(right.get("score", 0.0))
	)
	for candidate in candidates:
		if _undirected_pairs.size() >= desired_undirected_edges:
			break
		_add_bidirectional_edge(int(candidate.get("a", 0)), int(candidate.get("b", 0)), "extra")


func _add_bidirectional_edge(index_a: int, index_b: int, edge_role: String) -> void:
	var a := mini(index_a, index_b)
	var b := maxi(index_a, index_b)
	var pair_key := "%d::%d" % [a, b]
	if _undirected_pairs.has(pair_key):
		return
	_undirected_pairs[pair_key] = true
	var node_a: Dictionary = _node_rows[index_a] as Dictionary
	var node_b: Dictionary = _node_rows[index_b] as Dictionary
	var location_a := str(node_a.get("location_id", ""))
	var location_b := str(node_b.get("location_id", ""))
	var side_a := _pick_side_for_pair(index_a, index_b)
	var side_b := _opposite_side(side_a)
	var exit_ab := _next_edge_id()
	var exit_ba := _next_edge_id()
	var spawn_on_b := _generated_edge_spawn_id(location_b, location_a, side_b)
	var spawn_on_a := _generated_edge_spawn_id(location_a, location_b, side_a)

	_edge_rows.append(_edge_row(location_a, location_b, exit_ab, spawn_on_b, side_a, side_b, exit_ba, edge_role))
	_edge_rows.append(_edge_row(location_b, location_a, exit_ba, spawn_on_a, side_b, side_a, exit_ab, edge_role))


func _edge_row(
	from_location_id: String,
	target_location_id: String,
	exit_id: String,
	target_spawn_id: String,
	from_side: String,
	target_side: String,
	paired_exit_id: String,
	edge_role: String
) -> Dictionary:
	return {
		"edge_id": exit_id,
		"exit_id": exit_id,
		"from_location_id": from_location_id,
		"from_anchor_id": "%s_anchor" % exit_id,
		"target_location_id": target_location_id,
		"target_spawn_id": target_spawn_id,
		"transition_type": "walk",
		"enabled": true,
		"paired_exit_id": paired_exit_id,
		"metadata": {
			"source": "world_graph_generator",
			"edge_role": edge_role,
			"from_side": from_side,
			"target_side": target_side,
			"side": from_side,
			"facing": _facing_for_side(from_side),
		},
	}


func _generated_edge_spawn_id(location_id: String, from_location_id: String, target_side: String) -> String:
	var spawn_id := "%s_from_%s" % [_short_id(location_id), _short_id(from_location_id)]
	for spawn_value in _spawn_rows:
		var spawn: Dictionary = spawn_value as Dictionary
		if str(spawn.get("location_id", "")) == location_id and str(spawn.get("spawn_id", "")) == spawn_id:
			return spawn_id
	_spawn_rows.append({
		"location_id": location_id,
		"spawn_id": spawn_id,
		"entrance_id": spawn_id,
		"facing": _facing_for_side(target_side),
		"tags": ["generated_world_graph", "from_%s" % from_location_id, target_side],
		"metadata": {
			"source": "world_graph_generator",
			"side": target_side,
		},
	})
	return spawn_id


func _pick_location_kind() -> String:
	var candidates := _string_array(_config.get("available_location_kinds", []) as Array)
	return _pick_weighted(_kind_weights(), candidates, "location kind")


func _is_supported_location_kind(location_kind: String) -> bool:
	return location_kind == "generated_wild"


func _available_wild_profiles() -> Array[String]:
	return _string_array(_config.get("available_wild_profiles", []) as Array)


func _pick_wild_profile() -> String:
	return _pick_weighted(_wild_profile_weights(), _available_wild_profiles(), "wild profile")


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


func _kind_weights() -> Dictionary:
	return (_config.get("location_kind_weights", {}) as Dictionary).duplicate(true)


func _wild_profile_weights() -> Dictionary:
	return (_config.get("wild_profile_weights", {}) as Dictionary).duplicate(true)


func _pick_weighted(weights: Dictionary, candidates: Array[String], label: String) -> String:
	var total := 0.0
	for candidate in candidates:
		total += maxf(0.0, float(weights.get(candidate, 0.0)))
	if total <= 0.0:
		_errors.append("%s weights have no positive candidate" % label)
		return ""
	var roll := _rng.randf() * total
	var cursor := 0.0
	for candidate in candidates:
		var weight := maxf(0.0, float(weights.get(candidate, 0.0)))
		if weight <= 0.0:
			continue
		cursor += weight
		if roll <= cursor:
			return candidate
	_errors.append("%s weighted pick failed" % label)
	return ""


func _pick_size(location_kind: String) -> Dictionary:
	var size_ranges: Dictionary = _config.get("size_ranges", {}) as Dictionary
	var rows: Array = size_ranges.get(location_kind, []) as Array
	if rows.is_empty():
		_errors.append("missing size range for location kind: %s" % location_kind)
		return {}
	var row: Array = rows[_rng.randi_range(0, rows.size() - 1)] as Array
	if row.size() < 2:
		_errors.append("invalid size range row for location kind: %s" % location_kind)
		return {}
	var width := int(row[0])
	var height := int(row[1])
	if width <= 0 or height <= 0:
		_errors.append("invalid generated size for location kind: %s" % location_kind)
		return {}
	return {
		"width": width,
		"height": height,
	}


func _derive_node_seed(index: int, salt: String) -> int:
	var salt_value: int = int(abs(hash("%s:%s:%d" % [_world_id, salt, index])) % 100000)
	return int(_world_seed + 1013 * (index + 1) + salt_value)


func _stable_seed(world_seed: int, profile_id: String) -> int:
	return int(abs(world_seed * 4099 + int(abs(hash(profile_id)) % 100000)))


func _next_edge_id() -> String:
	_edge_sequence += 1
	return "edge_%04d" % _edge_sequence


func _short_id(location_id: String) -> String:
	var value := location_id.replace(_world_id, "world")
	value = value.replace("__", "_")
	value = value.replace("-", "_")
	value = value.replace(".", "_")
	return value


func _pick_side_for_pair(index_a: int, index_b: int) -> String:
	var sides: Array[String] = ["north", "east", "south", "west"]
	var value: int = int(abs(hash("%s:%d:%d:%d" % [_world_id, _world_seed, index_a, index_b])) % sides.size())
	return sides[value]


func _stable_pair_jitter(index_a: int, index_b: int, numeric_salt: int) -> float:
	var a := mini(index_a, index_b)
	var b := maxi(index_a, index_b)
	var value := sin(float(a) * 12.9898 + float(b) * 78.233 + float(_world_seed + numeric_salt) * 37.719 + float(abs(hash(_region_profile_id)) % 10000) * 0.017) * 43758.5453123
	return value - floor(value)


func _opposite_side(side: String) -> String:
	match side:
		"north":
			return "south"
		"south":
			return "north"
		"east":
			return "west"
		"west":
			return "east"
		_:
			return "path"


func _facing_for_side(side: String) -> String:
	match side:
		"north":
			return "up"
		"south":
			return "down"
		"east":
			return "right"
		"west":
			return "left"
		_:
			return "down"


func _display_name_for_wild_profile(profile_id: String, index: int) -> String:
	var label := profile_id.capitalize().replace("_", " ")
	return "%s Wild %02d" % [label, index]


func _wild_role_for_profile(profile_id: String) -> String:
	match profile_id:
		"forest_edge":
			return "forest"
		"riverbank":
			return "water_lowland"
		"foothill":
			return "upland"
		_:
			return "open_field"


func _debug_summary(world_data: Dictionary) -> Dictionary:
	var kind_counts: Dictionary = {}
	var wild_profile_counts: Dictionary = {}
	var generated_node_ids: Array[String] = []
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var kind := str(location.get("location_kind", ""))
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
		if str(location.get("source_type", "")) == "generated":
			generated_node_ids.append(str(location.get("location_id", "")))
		if kind == "generated_wild":
			var profile_id := str(location.get("generator_profile_id", ""))
			wild_profile_counts[profile_id] = int(wild_profile_counts.get(profile_id, 0)) + 1
	return {
		"world_id": _world_id,
		"seed": _world_seed,
		"region_profile_id": _region_profile_id,
		"node_count": (world_data.get("locations", []) as Array).size(),
		"edge_count": (world_data.get("exits", []) as Array).size(),
		"undirected_edge_count": _undirected_pairs.size(),
		"location_kind_counts": kind_counts,
		"wild_profile_counts": wild_profile_counts,
		"connected": _is_connected(world_data),
		"start_location_id": str(world_data.get("start_location_id", "")),
		"generated_node_ids": generated_node_ids,
		"generation_warnings": _warnings.duplicate(),
		"generation_errors": _errors.duplicate(),
	}


func _is_connected(world_data: Dictionary) -> bool:
	var blueprint: RefCounted = WorldGraphBlueprintScript.new()
	blueprint.configure(world_data)
	var errors: Array[String] = blueprint.validate()
	for error in errors:
		if error == "world graph is not connected":
			return false
	return true


func _failure_result(world_data: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"world_data": world_data.duplicate(true),
		"errors": _errors.duplicate(),
		"warnings": _warnings.duplicate(),
	}
