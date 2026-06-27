class_name WorldGraphGenerator
extends RefCounted

const WorldGenerationProfileScript := preload("res://scripts/systems/world/world_generation_profile.gd")
const WorldGraphBlueprintScript := preload("res://scripts/systems/world/world_graph_blueprint.gd")

const STATIC_TEST_VILLAGE_SCENE := "res://scenes/locations/test_village.tscn"
const STATIC_TEST_VILLAGE_DATA := "res://data/locations/test_village.json"
const WILD_SCENE := "res://scenes/locations/test_wild_plain.tscn"
const WILD_DATA := "res://data/locations/test_wild_plain.json"

var _rng := RandomNumberGenerator.new()
var _config: Dictionary = {}
var _world_id: String = ""
var _world_seed: int = 0
var _region_profile_id: String = ""
var _warnings: Array[String] = []
var _node_rows: Array[Dictionary] = []
var _spawn_rows: Array[Dictionary] = []
var _edge_rows: Array[Dictionary] = []
var _undirected_pairs: Dictionary = {}
var _wild_profile_order: Array[String] = []
var _edge_sequence: int = 0


func generate_blueprint(input: Dictionary) -> RefCounted:
	var world_data := generate_world_data(input)
	var blueprint: RefCounted = WorldGraphBlueprintScript.new()
	blueprint.configure(world_data)
	return blueprint


func generate_world_data(input: Dictionary) -> Dictionary:
	_config = WorldGenerationProfileScript.resolve_generation_config(input)
	_world_seed = int(_config.get("world_seed", _config.get("seed", 6501)))
	_world_id = str(_config.get("world_id", "generated_world_%d" % _world_seed))
	_region_profile_id = str(_config.get("region_profile_id", _config.get("profile_id", "temperate_frontier")))
	_rng.seed = _stable_seed(_world_seed, _region_profile_id)
	_warnings.clear()
	_node_rows.clear()
	_spawn_rows.clear()
	_edge_rows.clear()
	_undirected_pairs.clear()
	_wild_profile_order = _shuffled_string_array(_available_wild_profiles())
	_edge_sequence = 0

	var node_count := _node_count()
	_add_start_node()
	for index in range(1, node_count):
		_add_generated_node(index)
	_generate_connected_edges()
	_generate_extra_edges()

	var world_data := {
		"world_id": _world_id,
		"world_seed": _world_seed,
		"region_profile_id": _region_profile_id,
		"start_location_id": str(_node_rows[0].get("location_id", "")),
		"start_spawn_id": "village_start" if str(_node_rows[0].get("location_kind", "")) == "static" else "%s.start" % str(_node_rows[0].get("location_id", "")),
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
	return world_data


func _node_count() -> int:
	var explicit_min := int(_config.get("node_count_min", -1))
	var explicit_max := int(_config.get("node_count_max", -1))
	var range_values: Array = _config.get("node_count_range", []) as Array
	if explicit_min < 0 and range_values.size() >= 1:
		explicit_min = int(range_values[0])
	if explicit_max < 0 and range_values.size() >= 2:
		explicit_max = int(range_values[1])
	if explicit_min < 0:
		explicit_min = 4
	if explicit_max < 0:
		explicit_max = explicit_min
	var min_count: int = maxi(1, mini(explicit_min, explicit_max))
	var max_count: int = maxi(min_count, maxi(explicit_min, explicit_max))
	return _rng.randi_range(min_count, max_count)


func _add_start_node() -> void:
	var start_policy := str(_config.get("start_location_policy", "static_test_village"))
	var start_location_id := str(_config.get("optional_start_location_id", ""))
	var start_location_kind := str(_config.get("optional_start_location_kind", ""))
	if start_policy == "static_test_village" or (start_location_id == "test_village" and start_location_kind == "static"):
		_node_rows.append({
			"location_id": "test_village",
			"display_name": "Generated Graph Test Village",
			"location_kind": "static",
			"source_type": "static_scene",
			"scene_path": STATIC_TEST_VILLAGE_SCENE,
			"data_path": STATIC_TEST_VILLAGE_DATA,
			"metadata": {
				"source": "world_graph_generator",
				"start_location_policy": start_policy,
			},
		})
		_spawn_rows.append({
			"location_id": "test_village",
			"spawn_id": "village_start",
			"entrance_id": "plaza",
			"facing": "down",
			"tags": ["start", "generated_world_graph"],
		})
		return

	if start_location_id.is_empty():
		start_location_id = "%s_start" % _world_id
	if start_location_kind.is_empty():
		start_location_kind = "generated_wild"
	_add_generated_node(0, start_location_id, start_location_kind, true)


func _add_generated_node(index: int, forced_id: String = "", forced_kind: String = "", is_start: bool = false) -> void:
	var location_kind := forced_kind
	if location_kind.is_empty():
		location_kind = _pick_location_kind()
	if location_kind == "static" and not is_start:
		location_kind = "generated_wild"
		_warnings.append("non-start static node request fell back to generated_wild")

	match location_kind:
		"generated_wild":
			_add_generated_wild_node(index, forced_id, is_start)
		"generated_settlement":
			_add_generated_settlement_placeholder(index, forced_id, is_start)
		_:
			_add_generated_wild_node(index, forced_id, is_start)
			_warnings.append("unsupported generated node kind fell back to generated_wild: %s" % location_kind)


func _add_generated_wild_node(index: int, forced_id: String, is_start: bool) -> void:
	var wild_profile_id := _pick_wild_profile(index)
	var location_id := forced_id
	if location_id.is_empty():
		location_id = "%s_%s_%03d" % [_world_id, _profile_slug(wild_profile_id), index]
	var size := _pick_size("generated_wild")
	var seed := _derive_node_seed(index, wild_profile_id)
	var spawn_id := "%s.start" % location_id if is_start else "%s.entry" % location_id
	_node_rows.append({
		"location_id": location_id,
		"display_name": _display_name_for_wild_profile(wild_profile_id, index),
		"location_kind": "generated_wild",
		"source_type": "generated",
		"scene_path": WILD_SCENE,
		"data_path": WILD_DATA,
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
		"entrance_id": "wild_spawn",
		"facing": "right",
		"tags": ["generated_world_graph", "wild_spawn"],
	})


func _add_generated_settlement_placeholder(index: int, forced_id: String, is_start: bool) -> void:
	var location_id := forced_id
	if location_id.is_empty():
		location_id = "%s_settlement_%03d" % [_world_id, index]
	_node_rows.append({
		"location_id": location_id,
		"display_name": "Generated Settlement Placeholder %02d" % index,
		"location_kind": "generated_settlement",
		"source_type": "generated",
		"generator_id": "generated_settlement",
		"generator_profile_id": "frontier_settlement",
		"seed": _derive_node_seed(index, "settlement"),
		"metadata": {
			"source": "world_graph_generator",
			"placeholder": true,
			"region_profile_id": _region_profile_id,
		},
	})
	_spawn_rows.append({
		"location_id": location_id,
		"spawn_id": "%s.start" % location_id,
		"entrance_id": "plaza",
		"facing": "down",
		"tags": ["generated_world_graph", "settlement_placeholder"],
	})
	if is_start:
		_warnings.append("generated_settlement start is a placeholder and cannot materialize yet")


func _generate_connected_edges() -> void:
	for index in range(1, _node_rows.size()):
		var target_index := index - 1
		if index > 1 and _rng.randf() < float(_config.get("branchiness", 0.45)):
			target_index = _rng.randi_range(0, index - 1)
			if target_index == 0:
				target_index = _rng.randi_range(1, index - 1)
		_add_bidirectional_edge(target_index, index, "tree")


func _generate_extra_edges() -> void:
	var node_count := _node_rows.size()
	if node_count <= 2:
		return
	var connection_density := maxf(1.0, float(_config.get("connection_density", 1.20)))
	var desired_undirected_edges: int = maxi(node_count - 1, int(round(float(node_count - 1) * connection_density)))
	var max_undirected_edges: int = int(node_count * (node_count - 1) / 2)
	desired_undirected_edges = mini(desired_undirected_edges, max_undirected_edges)
	var attempts := node_count * node_count * 2
	while _undirected_pairs.size() < desired_undirected_edges and attempts > 0:
		attempts -= 1
		var a := _rng.randi_range(0, node_count - 1)
		var b := _rng.randi_range(0, node_count - 1)
		if a == b:
			continue
		if a == 0 or b == 0:
			continue
		_add_bidirectional_edge(a, b, "extra")


func _add_bidirectional_edge(index_a: int, index_b: int, edge_role: String) -> void:
	var a := mini(index_a, index_b)
	var b := maxi(index_a, index_b)
	var pair_key := "%d::%d" % [a, b]
	if _undirected_pairs.has(pair_key):
		return
	_undirected_pairs[pair_key] = true
	var node_a: Dictionary = _node_rows[a] as Dictionary
	var node_b: Dictionary = _node_rows[b] as Dictionary
	var location_a := str(node_a.get("location_id", ""))
	var location_b := str(node_b.get("location_id", ""))
	var side_a := _pick_side_for_pair(a, b)
	var side_b := _opposite_side(side_a)
	var exit_ab := _edge_id(location_a, location_b)
	var exit_ba := _edge_id(location_b, location_a)
	if location_a == "test_village":
		exit_ab = "wild_gate"
		exit_ba = "return_to_village"
	elif location_b == "test_village":
		exit_ab = "return_to_village"
		exit_ba = "wild_gate"
	var spawn_on_b := _ensure_edge_spawn(location_b, location_a, side_b)
	var spawn_on_a := _ensure_edge_spawn(location_a, location_b, side_a)

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


func _ensure_edge_spawn(location_id: String, from_location_id: String, target_side: String) -> String:
	var spawn_id := "%s_from_%s" % [_short_id(location_id), _short_id(from_location_id)]
	for spawn_value in _spawn_rows:
		var spawn: Dictionary = spawn_value as Dictionary
		if str(spawn.get("location_id", "")) == location_id and str(spawn.get("spawn_id", "")) == spawn_id:
			return spawn_id
	var entrance_id := "from_wild" if location_id == "test_village" else spawn_id
	_spawn_rows.append({
		"location_id": location_id,
		"spawn_id": spawn_id,
		"entrance_id": entrance_id,
		"facing": _facing_for_side(target_side),
		"tags": ["generated_world_graph", "from_%s" % from_location_id, target_side],
		"metadata": {
			"source": "world_graph_generator",
			"side": target_side,
		},
	})
	return spawn_id


func _pick_location_kind() -> String:
	var candidates: Array = _config.get("available_location_kinds", []) as Array
	if candidates.is_empty():
		candidates = ["generated_wild"]
	return _pick_weighted(_kind_weights(), candidates, "generated_wild")


func _available_wild_profiles() -> Array:
	var profiles: Array = _config.get("available_wild_profiles", []) as Array
	if profiles.is_empty():
		profiles = ["plain"]
	return profiles


func _pick_wild_profile(index: int) -> String:
	var profile_index := index - 1
	if profile_index >= 0 and profile_index < _wild_profile_order.size():
		return _wild_profile_order[profile_index]
	return _pick_weighted(_wild_profile_weights(), _available_wild_profiles(), "plain")


func _shuffled_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	for index in range(result.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var current := result[index]
		result[index] = result[swap_index]
		result[swap_index] = current
	return result


func _kind_weights() -> Dictionary:
	return (_config.get("location_kind_weights", {}) as Dictionary).duplicate(true)


func _wild_profile_weights() -> Dictionary:
	return (_config.get("wild_profile_weights", {}) as Dictionary).duplicate(true)


func _pick_weighted(weights: Dictionary, candidates: Array, fallback: String) -> String:
	var total := 0.0
	for candidate_value in candidates:
		total += maxf(0.0, float(weights.get(str(candidate_value), 0.0)))
	if total <= 0.0:
		return str(candidates[0]) if not candidates.is_empty() else fallback
	var roll := _rng.randf() * total
	var cursor := 0.0
	for candidate_value in candidates:
		var candidate := str(candidate_value)
		cursor += maxf(0.0, float(weights.get(candidate, 0.0)))
		if roll <= cursor:
			return candidate
	return str(candidates[candidates.size() - 1]) if not candidates.is_empty() else fallback


func _pick_size(location_kind: String) -> Dictionary:
	var size_ranges: Dictionary = _config.get("size_ranges", {}) as Dictionary
	var rows: Array = size_ranges.get(location_kind, []) as Array
	if rows.is_empty():
		return { "width": 64, "height": 64 }
	var row: Array = rows[_rng.randi_range(0, rows.size() - 1)] as Array
	if row.size() < 2:
		return { "width": 64, "height": 64 }
	return {
		"width": int(row[0]),
		"height": int(row[1]),
	}


func _derive_node_seed(index: int, salt: String) -> int:
	var salt_value: int = int(abs(hash("%s:%s:%d" % [_world_id, salt, index])) % 100000)
	return int(_world_seed + 1013 * (index + 1) + salt_value)


func _stable_seed(world_seed: int, profile_id: String) -> int:
	return int(abs(world_seed * 4099 + int(abs(hash(profile_id)) % 100000)))


func _edge_id(from_location_id: String, target_location_id: String) -> String:
	_edge_sequence += 1
	return "edge_%03d_%s_to_%s" % [_edge_sequence, _short_id(from_location_id), _short_id(target_location_id)]


func _short_id(location_id: String) -> String:
	var value := location_id.replace(_world_id, "w")
	value = value.replace("test_village", "village")
	value = value.replace("__", "_")
	value = value.replace("-", "_")
	return value


func _pick_side_for_pair(index_a: int, index_b: int) -> String:
	var sides: Array[String] = ["north", "east", "south", "west"]
	var value: int = int(abs(hash("%s:%d:%d:%d" % [_world_id, _world_seed, index_a, index_b])) % sides.size())
	return sides[value]


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


func _profile_slug(profile_id: String) -> String:
	var slug := profile_id.to_lower().replace(" ", "_").replace("-", "_")
	slug = slug.replace("__", "_")
	if slug.is_empty():
		return "wild"
	return slug


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
	}


func _is_connected(world_data: Dictionary) -> bool:
	var blueprint: RefCounted = WorldGraphBlueprintScript.new()
	blueprint.configure(world_data)
	var errors: Array[String] = blueprint.validate()
	for error in errors:
		if error == "world graph is not connected":
			return false
	return true
