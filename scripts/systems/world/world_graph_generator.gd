class_name WorldGraphGenerator
extends RefCounted

const WorldGenerationProfileScript := preload("res://scripts/systems/world/world_generation_profile.gd")
const WorldGraphBlueprintScript := preload("res://scripts/systems/world/world_graph_blueprint.gd")
const RegionMapGeneratorScript := preload("res://scripts/systems/world/region_map_generator.gd")
const WildTerrainProfileScript := preload("res://scripts/systems/terrain/wild_terrain_profile.gd")
const REGION_BIOMES := ["sea", "coast", "plain", "forest", "riverbank", "foothill", "rocky"]

var _rng := RandomNumberGenerator.new()
var _region_map_generator: RefCounted = RegionMapGeneratorScript.new()
var _config: Dictionary = {}
var _world_id: String = ""
var _world_seed: int = 0
var _region_profile_id: String = ""
var _region_map: Dictionary = {}
var _warnings: Array[String] = []
var _errors: Array[String] = []
var _node_rows: Array[Dictionary] = []
var _spawn_rows: Array[Dictionary] = []
var _edge_rows: Array[Dictionary] = []
var _node_region_positions: Array[Vector2i] = []
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
	_region_map = _region_map_generator.generate_region_map(_config)
	var region_errors: Array[String] = _region_map_generator.validate_region_map(_region_map)
	if not region_errors.is_empty():
		_errors.append_array(region_errors)
		return _failure_result()

	var node_count := _node_count()
	if node_count <= 0:
		return _failure_result()
	if not _place_region_nodes(node_count):
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
		"region_map": _region_map.duplicate(true),
		"start_location_id": str(_node_rows[0].get("location_id", "")),
		"start_spawn_id": _start_spawn_id,
		"locations": _node_rows.duplicate(true),
		"spawns": _spawn_rows.duplicate(true),
		"exits": _edge_rows.duplicate(true),
		"generator_metadata": {
			"generator": "WorldGraphGenerator",
			"algorithm": "region_map_seeded_local_connected_graph",
			"profiles_are_region_derived": true,
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
	_node_region_positions.clear()
	_region_map.clear()
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

	var wild_profiles := _available_wild_profiles()
	if wild_profiles.is_empty():
		_errors.append("available_wild_profiles is empty")
	else:
		var total_wild_weight := 0.0
		var wild_weights := _wild_profile_weights()
		for profile_id in wild_profiles:
			total_wild_weight += maxf(0.0, float(wild_weights.get(profile_id, 0.0)))
		if total_wild_weight <= 0.0:
			_errors.append("wild_profile_weights has no positive candidate weight")
	_validate_biome_profile_map()

	var size_ranges: Dictionary = _config.get("size_ranges", {}) as Dictionary
	var wild_sizes: Array = size_ranges.get("generated_wild", []) as Array
	if wild_sizes.is_empty():
		_errors.append("size_ranges.generated_wild is empty")
	return _errors.is_empty()


func _node_count() -> int:
	var range_values: Array = _config.get("node_count_range", []) as Array
	if range_values.size() < 2:
		return 0
	var min_count := int(range_values[0])
	var max_count := int(range_values[1])
	if min_count < 1 or max_count < min_count:
		return 0
	return _rng.randi_range(min_count, max_count)


func _place_region_nodes(node_count: int) -> bool:
	var width := int(_region_map.get("width", 0))
	var height := int(_region_map.get("height", 0))
	var candidates: Array[Dictionary] = []
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var region_cell: Dictionary = _region_map_generator.cell_at(_region_map, cell)
			var biome := str(region_cell.get("biome", ""))
			if not _can_place_node_on_biome(biome):
				continue
			candidates.append({
				"position": cell,
				"biome": biome,
				"score": _stable_position_jitter(cell, biome, 1217),
			})
	if candidates.size() < node_count:
		_errors.append("RegionMap has only %d placeable cells for %d world nodes" % [candidates.size(), node_count])
		return false
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left.get("score", 0.0)) == float(right.get("score", 0.0)):
			var left_cell: Vector2i = left.get("position", Vector2i.ZERO) as Vector2i
			var right_cell: Vector2i = right.get("position", Vector2i.ZERO) as Vector2i
			return _position_key(left_cell) < _position_key(right_cell)
		return float(left.get("score", 0.0)) > float(right.get("score", 0.0))
	)

	var selected: Array[Vector2i] = [candidates[0].get("position", Vector2i.ZERO) as Vector2i]
	var selected_keys: Dictionary = { _position_key(selected[0]): true }
	while selected.size() < node_count:
		var best_index := -1
		var best_score := -INF
		for index in range(candidates.size()):
			var candidate: Dictionary = candidates[index] as Dictionary
			var position: Vector2i = candidate.get("position", Vector2i.ZERO) as Vector2i
			if selected_keys.has(_position_key(position)):
				continue
			var distance_score := _min_region_distance_to_selected(position, selected)
			var score := distance_score + float(candidate.get("score", 0.0)) * 0.12
			if score > best_score:
				best_score = score
				best_index = index
		if best_index < 0:
			_errors.append("RegionMap node placement failed before selecting all nodes")
			return false
		var next_position: Vector2i = (candidates[best_index] as Dictionary).get("position", Vector2i.ZERO) as Vector2i
		selected.append(next_position)
		selected_keys[_position_key(next_position)] = true
	_node_region_positions = selected
	return true


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
	var region_position := _node_region_position(index)
	var region_cell: Dictionary = _region_map_generator.cell_at(_region_map, region_position)
	if region_cell.is_empty():
		_errors.append("world node has no RegionCell at index %d" % index)
		return false
	var region_biome := str(region_cell.get("biome", ""))
	var region_patch: Dictionary = _region_map_generator.patch_for(_region_map, region_position, 1)
	if region_patch.is_empty():
		_errors.append("world node has no RegionPatch at index %d" % index)
		return false
	var wild_profile_id := _pick_profile_for_biome(region_biome, region_position)
	if wild_profile_id.is_empty():
		return false
	var display_name := _display_name_for_wild_profile(wild_profile_id, index)
	if display_name.is_empty():
		return false
	var size := _pick_size("generated_wild")
	if size.is_empty():
		return false
	var location_id := "%s_node_%03d" % [_world_id, index]
	var seed := _derive_node_seed(index, wild_profile_id, region_position)
	var spawn_id := "%s_spawn" % location_id if is_start else "%s_entry" % location_id
	var spawn_side := _start_side_for_node(index)
	_node_rows.append({
		"location_id": location_id,
		"display_name": display_name,
		"location_kind": "generated_wild",
		"source_type": "generated",
		"generator_id": "wild_terrain",
		"generator_profile_id": wild_profile_id,
		"seed": seed,
		"size": size,
		"region_position": _dict_from_cell(region_position),
		"region_biome": region_biome,
		"region_cell": region_cell.duplicate(true),
		"region_patch": region_patch.duplicate(true),
		"metadata": {
			"source": "world_graph_generator",
			"region_profile_id": _region_profile_id,
			"region_position": _dict_from_cell(region_position),
			"region_biome": region_biome,
			"region_patch": region_patch.duplicate(true),
			"world_node_role": _wild_role_for_profile(wild_profile_id),
			"node_index": index,
		},
	})
	_spawn_rows.append({
		"location_id": location_id,
		"spawn_id": spawn_id,
		"entrance_id": spawn_id,
		"facing": _facing_for_entry_side(spawn_side),
		"tags": ["generated_world_graph", "start", spawn_side] if is_start else ["generated_world_graph", "entry", spawn_side],
		"metadata": {
			"source": "world_graph_generator",
			"side": spawn_side,
		},
	})
	if is_start:
		_start_spawn_id = spawn_id
	return true


func _generate_connected_edges() -> void:
	if _node_rows.size() <= 1:
		return
	var connected: Array[int] = [0]
	var remaining: Array[int] = []
	for index in range(1, _node_rows.size()):
		remaining.append(index)
	while not remaining.is_empty():
		var best_from := -1
		var best_to := -1
		var best_score := INF
		for from_index in connected:
			for to_index in remaining:
				var distance := _region_distance(_node_region_position(from_index), _node_region_position(to_index))
				var score := distance + _stable_pair_jitter(from_index, to_index, 1709) * 0.08
				if score < best_score:
					best_score = score
					best_from = from_index
					best_to = to_index
		if best_from < 0 or best_to < 0:
			return
		_add_bidirectional_edge(best_from, best_to, "region_tree")
		connected.append(best_to)
		remaining.erase(best_to)


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
				"score": _region_distance(_node_region_position(a), _node_region_position(b)) + _stable_pair_jitter(a, b, 1723) * 0.08,
			})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left.get("score", 0.0)) == float(right.get("score", 0.0)):
			return "%d:%d" % [int(left.get("a", 0)), int(left.get("b", 0))] < "%d:%d" % [int(right.get("a", 0)), int(right.get("b", 0))]
		return float(left.get("score", 0.0)) < float(right.get("score", 0.0))
	)
	for candidate in candidates:
		if _undirected_pairs.size() >= desired_undirected_edges:
			break
		_add_bidirectional_edge(int(candidate.get("a", 0)), int(candidate.get("b", 0)), "region_extra")


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
	var side_a := _side_from_region_positions(_node_region_position(index_a), _node_region_position(index_b), index_a, index_b)
	var side_b := _opposite_side(side_a)
	var exit_ab := _next_edge_id()
	var exit_ba := _next_edge_id()
	var spawn_on_b := _generated_edge_spawn_id(location_b, location_a, side_b)
	var spawn_on_a := _generated_edge_spawn_id(location_a, location_b, side_a)

	_edge_rows.append(_edge_row(index_a, index_b, location_a, location_b, exit_ab, spawn_on_b, side_a, side_b, exit_ba, edge_role))
	_edge_rows.append(_edge_row(index_b, index_a, location_b, location_a, exit_ba, spawn_on_a, side_b, side_a, exit_ab, edge_role))


func _edge_row(
	from_index: int,
	target_index: int,
	from_location_id: String,
	target_location_id: String,
	exit_id: String,
	target_spawn_id: String,
	from_side: String,
	target_side: String,
	paired_exit_id: String,
	edge_role: String
) -> Dictionary:
	var from_position := _node_region_position(from_index)
	var target_position := _node_region_position(target_index)
	var from_cell: Dictionary = _region_map_generator.cell_at(_region_map, from_position)
	var target_cell: Dictionary = _region_map_generator.cell_at(_region_map, target_position)
	var from_biome := str(from_cell.get("biome", ""))
	var target_biome := str(target_cell.get("biome", ""))
	var transition_kind := "%s_to_%s" % [from_biome, target_biome]
	var distance := _region_distance(from_position, target_position)
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
		"from_region_position": _dict_from_cell(from_position),
		"to_region_position": _dict_from_cell(target_position),
		"from_biome": from_biome,
		"to_biome": target_biome,
		"transition_kind": transition_kind,
		"region_distance": _round3(distance),
		"metadata": {
			"source": "world_graph_generator",
			"edge_role": edge_role,
			"region_from": _dict_from_cell(from_position),
			"region_to": _dict_from_cell(target_position),
			"biome_from": from_biome,
			"biome_to": target_biome,
			"transition_kind": transition_kind,
			"region_distance": _round3(distance),
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
		"facing": _facing_for_entry_side(target_side),
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


func _biome_profile_map() -> Dictionary:
	return (_config.get("biome_profile_map", {}) as Dictionary).duplicate(true)


func _unplaceable_region_biomes() -> Array[String]:
	return _string_array(_config.get("unplaceable_region_biomes", []) as Array)


func _validate_biome_profile_map() -> void:
	var biome_profile_map := _biome_profile_map()
	if biome_profile_map.is_empty():
		_errors.append("biome_profile_map is missing")
		return
	var available_profiles := _available_wild_profiles()
	var supported_profiles := WildTerrainProfileScript.supported_profile_ids()
	var unplaceable_biomes := _unplaceable_region_biomes()
	for biome_value in biome_profile_map.keys():
		var biome := str(biome_value)
		if not REGION_BIOMES.has(biome):
			_errors.append("biome_profile_map contains unsupported region biome: %s" % biome)
		var profiles := _profiles_for_biome(biome)
		if unplaceable_biomes.has(biome) and not profiles.is_empty():
			_errors.append("unplaceable region biome maps to generated profiles: %s" % biome)
		for profile_id in profiles:
			if not available_profiles.has(profile_id):
				_errors.append("biome %s maps to profile not listed in available_wild_profiles: %s" % [biome, profile_id])
			if not supported_profiles.has(profile_id):
				_errors.append("biome %s maps to unsupported wild terrain profile: %s" % [biome, profile_id])
	for biome in REGION_BIOMES:
		if unplaceable_biomes.has(biome):
			continue
		if not biome_profile_map.has(biome):
			_errors.append("placeable region biome missing profile mapping: %s" % biome)
			continue
		if _profiles_for_biome(biome).is_empty():
			_errors.append("placeable region biome has no generated profile mapping: %s" % biome)


func _profiles_for_biome(biome: String) -> Array[String]:
	var raw_value: Variant = _biome_profile_map().get(biome, [])
	if raw_value is String:
		var profile_id := str(raw_value)
		return [profile_id] if not profile_id.is_empty() else []
	if raw_value is Array:
		return _string_array(raw_value as Array)
	return []


func _can_place_node_on_biome(biome: String) -> bool:
	if _unplaceable_region_biomes().has(biome):
		return false
	return not _profiles_for_biome(biome).is_empty()


func _pick_profile_for_biome(biome: String, region_position: Vector2i) -> String:
	if not REGION_BIOMES.has(biome):
		_errors.append("world node uses unsupported region biome: %s" % biome)
		return ""
	var candidates := _profiles_for_biome(biome)
	if candidates.is_empty():
		_errors.append("region biome has no available generator profile: %s" % biome)
		return ""
	var weights := _wild_profile_weights()
	var total := 0.0
	for candidate in candidates:
		total += maxf(0.0, float(weights.get(candidate, 0.0)))
	if total <= 0.0:
		_errors.append("region biome profiles have no positive weight: %s" % biome)
		return ""
	var roll := _stable_position_jitter(region_position, biome, 941) * total
	var cursor := 0.0
	for candidate in candidates:
		cursor += maxf(0.0, float(weights.get(candidate, 0.0)))
		if roll <= cursor:
			return candidate
	_errors.append("region biome profile weighted pick failed: %s" % biome)
	return ""


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
		cursor += maxf(0.0, float(weights.get(candidate, 0.0)))
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


func _derive_node_seed(index: int, salt: String, region_position: Vector2i) -> int:
	var salt_value: int = int(abs(hash("%s:%s:%d:%d:%d" % [_world_id, salt, index, region_position.x, region_position.y])) % 100000)
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


func _side_from_region_positions(from_position: Vector2i, target_position: Vector2i, index_a: int, index_b: int) -> String:
	var delta := target_position - from_position
	if delta == Vector2i.ZERO:
		return _pick_side_for_pair(index_a, index_b)
	if absi(delta.x) >= absi(delta.y):
		return "east" if delta.x > 0 else "west"
	return "south" if delta.y > 0 else "north"


func _node_region_position(index: int) -> Vector2i:
	if index >= 0 and index < _node_region_positions.size():
		return _node_region_positions[index]
	return Vector2i(-1, -1)


func _region_distance(a: Vector2i, b: Vector2i) -> float:
	return sqrt(float(a.distance_squared_to(b)))


func _min_region_distance_to_selected(position: Vector2i, selected: Array[Vector2i]) -> float:
	var best := INF
	for existing in selected:
		best = minf(best, _region_distance(position, existing))
	return best


func _stable_position_jitter(position: Vector2i, salt: String, numeric_salt: int) -> float:
	var value := sin(float(position.x) * 12.9898 + float(position.y) * 78.233 + float(_world_seed + numeric_salt) * 37.719 + float(abs(hash("%s:%s" % [_region_profile_id, salt])) % 10000) * 0.017) * 43758.5453123
	return value - floor(value)


func _stable_pair_jitter(index_a: int, index_b: int, numeric_salt: int) -> float:
	var a := mini(index_a, index_b)
	var b := maxi(index_a, index_b)
	var value := sin(float(a) * 12.9898 + float(b) * 78.233 + float(_world_seed + numeric_salt) * 37.719 + float(abs(hash(_region_profile_id)) % 10000) * 0.017) * 43758.5453123
	return value - floor(value)


func _dict_from_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _position_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _round3(value: float) -> float:
	return snappedf(value, 0.001)


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


func _facing_for_entry_side(side: String) -> String:
	match side:
		"north":
			return "down"
		"south":
			return "up"
		"east":
			return "left"
		"west":
			return "right"
		_:
			return "down"


func _start_side_for_node(index: int) -> String:
	var sides: Array[String] = ["north", "east", "south", "west"]
	var value: int = int(abs(hash("%s:%d:start:%d" % [_world_id, _world_seed, index])) % sides.size())
	return sides[value]


func _display_name_for_wild_profile(profile_id: String, index: int) -> String:
	var labels := {
		"plain": "平原野地",
		"forest_edge": "林缘野地",
		"riverbank": "河岸野地",
		"foothill": "山脚野地",
	}
	if not labels.has(profile_id):
		_errors.append("wild profile has no generated display name label: %s" % profile_id)
		return ""
	var label := str(labels.get(profile_id, ""))
	return "%s %02d" % [label, index]


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
	var region_biome_counts: Dictionary = {}
	var generated_node_ids: Array[String] = []
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var kind := str(location.get("location_kind", ""))
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
		var region_biome := str(location.get("region_biome", ""))
		if not region_biome.is_empty():
			region_biome_counts[region_biome] = int(region_biome_counts.get(region_biome, 0)) + 1
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
		"region_biome_counts": region_biome_counts,
		"region_map_fingerprint": _region_map_generator.fingerprint(_region_map),
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
