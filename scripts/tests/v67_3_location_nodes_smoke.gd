extends Node

const LocationNodeExpanderScript := preload("res://scripts/systems/regions/location_node_expander.gd")
const LocationNodeProfileScript := preload("res://scripts/systems/regions/location_node_profile.gd")
const LocationNodeResultValidatorScript := preload("res://scripts/systems/regions/location_node_result_validator.gd")
const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")

const TOWN_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const FOREST_REGION_INPUT_PATH := "res://data/regions/frontier_forest_region.json"
const TOWN_LOCATION_PROFILE_PATH := "res://data/regions/location_node_profiles/town_region.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_region_types_expand_to_location_nodes():
		return
	if not _assert_same_seed_reproducible():
		return
	if not _assert_forced_role_slug_controls_node_slug():
		return
	if not _assert_external_connection_binding_is_boundary_only():
		return
	if not _assert_invalid_profile_and_mapping_fail():
		return
	if not _assert_validator_rejects_invalid_results():
		return
	if not _assert_location_graph_boundary():
		return
	print("v67.3 location nodes smoke test passed")
	get_tree().quit(0)


func _assert_region_types_expand_to_location_nodes() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var town_result: Dictionary = compiler.compile_location_nodes_result(_load_json(TOWN_REGION_INPUT_PATH))
	if not bool(town_result.get("success", false)):
		_fail("v67.3 town_region location nodes failed: %s" % str(town_result.get("errors", [])))
		return false
	var forest_result: Dictionary = compiler.compile_location_nodes_result(_load_json(FOREST_REGION_INPUT_PATH))
	if not bool(forest_result.get("success", false)):
		_fail("v67.3 forest_region location nodes failed: %s" % str(forest_result.get("errors", [])))
		return false
	var town_nodes: Dictionary = town_result.get("location_node_result", {}) as Dictionary
	var forest_nodes: Dictionary = forest_result.get("location_node_result", {}) as Dictionary
	if not _assert_location_node_only(town_nodes) or not _assert_location_node_only(forest_nodes):
		return false
	if _location_type_signature(town_nodes) == _location_type_signature(forest_nodes):
		_fail("v67.3 town_region and forest_region produced the same location type signature")
		return false
	if (town_nodes.get("location_nodes", []) as Array).size() != (town_nodes.get("role_node_bindings", []) as Array).size():
		_fail("v67.3 town_region did not produce one role binding per location node")
		return false
	return true


func _assert_same_seed_reproducible() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var input := _load_json(TOWN_REGION_INPUT_PATH)
	var first: Dictionary = compiler.compile_location_nodes_result(input)
	var second: Dictionary = compiler.compile_location_nodes_result(input)
	if not bool(first.get("success", false)) or not bool(second.get("success", false)):
		_fail("v67.3 same-seed reproducibility setup failed")
		return false
	if _location_node_signature(first.get("location_node_result", {}) as Dictionary) != _location_node_signature(second.get("location_node_result", {}) as Dictionary):
		_fail("v67.3 same seed did not reproduce the same location nodes")
		return false
	return true


func _assert_forced_role_slug_controls_node_slug() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var input := _load_json(TOWN_REGION_INPUT_PATH)
	input["forced_role_specs"] = [
		{
			"role_type": "landmark",
			"role_slug": "old_tree",
			"role_tags": ["ancient"]
		}
	]
	var result: Dictionary = compiler.compile_location_nodes_result(input)
	if not bool(result.get("success", false)):
		_fail("v67.3 forced role location node failed: %s" % str(result.get("errors", [])))
		return false
	var location_node_result: Dictionary = result.get("location_node_result", {}) as Dictionary
	for node_value in (location_node_result.get("location_nodes", []) as Array):
		var node: Dictionary = node_value as Dictionary
		if str(node.get("source_role_slug", "")) == "old_tree":
			if str(node.get("node_slug", "")) != "old_tree":
				_fail("v67.3 forced role_slug did not control node_slug")
				return false
			if str(node.get("location_type", "")) != "landmark_site":
				_fail("v67.3 forced landmark did not use the landmark_site location type")
				return false
			if not str(node.get("location_id", "")).contains(".old_tree."):
				_fail("v67.3 forced node location_id did not include the forced slug")
				return false
			return true
	_fail("v67.3 forced old_tree role did not produce a location node")
	return false


func _assert_external_connection_binding_is_boundary_only() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_location_nodes_result(_load_json(TOWN_REGION_INPUT_PATH))
	if not bool(result.get("success", false)):
		_fail("v67.3 external binding setup failed: %s" % str(result.get("errors", [])))
		return false
	var location_node_result: Dictionary = result.get("location_node_result", {}) as Dictionary
	var bindings: Array = location_node_result.get("external_connection_bindings", []) as Array
	if bindings.size() != 1:
		_fail("v67.3 expected one external_connection_binding, got %d" % bindings.size())
		return false
	var binding: Dictionary = bindings[0] as Dictionary
	for forbidden in ["target_location_id", "target_region_id", "edge_id", "resolved_connection", "from_location_id", "to_location_id"]:
		if binding.has(forbidden):
			_fail("v67.3 external_connection_binding contains edge-like field: %s" % forbidden)
			return false
	var boundary_location_id := str(binding.get("boundary_location_id", ""))
	for node_value in (location_node_result.get("location_nodes", []) as Array):
		var node: Dictionary = node_value as Dictionary
		if str(node.get("location_id", "")) == boundary_location_id:
			if not bool(node.get("is_boundary", false)):
				_fail("v67.3 external binding did not point at a boundary node")
				return false
			if str(node.get("source_role_id", "")) != str(binding.get("source_role_id", "")):
				_fail("v67.3 external binding did not point at its source role node")
				return false
			return true
	_fail("v67.3 external binding boundary_location_id did not resolve")
	return false


func _assert_invalid_profile_and_mapping_fail() -> bool:
	var profile_data := _load_json(TOWN_LOCATION_PROFILE_PATH)
	var rules: Dictionary = profile_data.get("role_to_location_rules", {}) as Dictionary
	var settlement_rule: Dictionary = rules.get("settlement_core", {}) as Dictionary
	settlement_rule["count"] = 2
	rules["settlement_core"] = settlement_rule
	profile_data["role_to_location_rules"] = rules
	var profile: RefCounted = LocationNodeProfileScript.new()
	var profile_errors: Array[String] = profile.configure(profile_data)
	if not str(profile_errors).contains("count must be exactly 1"):
		_fail("v67.3 invalid profile count did not fail clearly: %s" % str(profile_errors))
		return false

	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var semantic_result: Dictionary = compiler.compile_semantic_roles_result(_load_json(TOWN_REGION_INPUT_PATH))
	if not bool(semantic_result.get("success", false)):
		_fail("v67.3 missing mapping setup failed")
		return false
	var semantic_roles: Dictionary = semantic_result.get("semantic_role_result", {}) as Dictionary
	var roles: Array = semantic_roles.get("selected_roles", []) as Array
	var first_role: Dictionary = roles[0] as Dictionary
	first_role["role_type"] = "castle"
	first_role["role_slug"] = "castle"
	roles[0] = first_role
	semantic_roles["selected_roles"] = roles
	var expander: RefCounted = LocationNodeExpanderScript.new()
	var node_result: Dictionary = expander.expand_locations_result(semantic_roles)
	if bool(node_result.get("success", false)):
		_fail("v67.3 unsupported semantic role mapping unexpectedly passed")
		return false
	if not str(node_result.get("errors", [])).contains("no location rule"):
		_fail("v67.3 unsupported semantic role mapping did not fail clearly: %s" % str(node_result.get("errors", [])))
		return false
	return true


func _assert_validator_rejects_invalid_results() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var semantic_result: Dictionary = compiler.compile_semantic_roles_result(_load_json(TOWN_REGION_INPUT_PATH))
	var location_result: Dictionary = compiler.compile_location_nodes_result(_load_json(TOWN_REGION_INPUT_PATH))
	if not bool(semantic_result.get("success", false)) or not bool(location_result.get("success", false)):
		_fail("v67.3 validator setup failed")
		return false
	var semantic_roles: Dictionary = semantic_result.get("semantic_role_result", {}) as Dictionary
	var profile_load: Dictionary = LocationNodeProfileScript.new().load_profile_result("town_region")
	var profile: RefCounted = profile_load.get("profile") as RefCounted
	var validator: RefCounted = LocationNodeResultValidatorScript.new()
	var duplicate_slug: Dictionary = (location_result.get("location_node_result", {}) as Dictionary).duplicate(true)
	var nodes: Array = duplicate_slug.get("location_nodes", []) as Array
	var first_node: Dictionary = nodes[0] as Dictionary
	var second_node: Dictionary = nodes[1] as Dictionary
	second_node["node_slug"] = str(first_node.get("node_slug", ""))
	nodes[1] = second_node
	duplicate_slug["location_nodes"] = nodes
	if not str(validator.validate(duplicate_slug, semantic_roles, profile)).contains("duplicate node_slug"):
		_fail("v67.3 validator accepted duplicate node_slug")
		return false
	var edge_field: Dictionary = (location_result.get("location_node_result", {}) as Dictionary).duplicate(true)
	var edge_nodes: Array = edge_field.get("location_nodes", []) as Array
	var edge_node: Dictionary = edge_nodes[0] as Dictionary
	edge_node["edge_id"] = "edge.frontier.invalid"
	edge_nodes[0] = edge_node
	edge_field["location_nodes"] = edge_nodes
	if not str(validator.validate(edge_field, semantic_roles, profile)).contains("v67.4 edge/scene/runtime field"):
		_fail("v67.3 validator accepted edge_id in LocationNodeResult")
		return false
	return true


func _assert_location_graph_boundary() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_to_location_graph_result(_load_json(TOWN_REGION_INPUT_PATH))
	if bool(result.get("success", false)):
		_fail("v67.3 compile_to_location_graph_result unexpectedly succeeded")
		return false
	if str(result.get("stage", "")) != "location_nodes_to_edge_contracts":
		_fail("v67.3 Location Graph boundary failed at wrong stage: %s" % str(result.get("stage", "")))
		return false
	if not str(result.get("errors", [])).contains("v67.4 edge contract generation is not implemented"):
		_fail("v67.3 Location Graph boundary did not expose v67.4: %s" % str(result.get("errors", [])))
		return false
	if (result.get("location_node_result", {}) as Dictionary).is_empty():
		_fail("v67.3 Location Graph boundary did not include the valid LocationNodeResult")
		return false
	return true


func _assert_location_node_only(result: Dictionary) -> bool:
	if str(result.get("stage", "")) != "location_nodes":
		_fail("v67.3 result has wrong stage: %s" % str(result.get("stage", "")))
		return false
	if not result.has("location_nodes") or result.has("locations"):
		_fail("v67.3 result must expose location_nodes and not locations")
		return false
	for forbidden in ["edge_id", "edges", "scene_path", "spawn_id", "tilemap", "target_location_id", "target_region_id", "start_location_id"]:
		if JSON.stringify(result).contains("\"%s\"" % forbidden):
			_fail("v67.3 LocationNodeResult contains forbidden next-stage field: %s" % forbidden)
			return false
	for node_value in (result.get("location_nodes", []) as Array):
		var node: Dictionary = node_value as Dictionary
		if str(node.get("source_role_id", "")).is_empty():
			_fail("v67.3 location node is missing source_role_id")
			return false
	return true


func _location_type_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	for node_value in (result.get("location_nodes", []) as Array):
		var node: Dictionary = node_value as Dictionary
		parts.append(str(node.get("location_type", "")))
	parts.sort()
	return "|".join(parts)


func _location_node_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	for node_value in (result.get("location_nodes", []) as Array):
		var node: Dictionary = node_value as Dictionary
		parts.append("%s:%s:%s" % [
			str(node.get("location_id", "")),
			str(node.get("location_type", "")),
			str(node.get("source_role_id", "")),
		])
	parts.sort()
	return "|".join(parts)


func _load_json(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
