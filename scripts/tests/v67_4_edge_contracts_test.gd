extends SceneTree

const EdgeContractProfileScript := preload("res://scripts/systems/regions/edge_contract_profile.gd")
const EdgeContractResultValidatorScript := preload("res://scripts/systems/regions/edge_contract_result_validator.gd")
const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")
const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")

const TOWN_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const FOREST_REGION_INPUT_PATH := "res://data/regions/frontier_forest_region.json"
const EDGE_PROFILE_PATH := "res://data/location_graph/edge_contract_profiles/default.json"
const GRAPH_ID := "graph.frontier.test_overworld.lg_0001"


func _initialize() -> void:
	if not _assert_edge_contract_generation():
		return
	if not _assert_same_input_is_stable():
		return
	if not _assert_profile_rejects_region_selectors():
		return
	if not _assert_missing_required_endpoint_fails():
		return
	if not _assert_ambiguous_matching_fails():
		return
	if not _assert_unmatched_node_does_not_gain_default_edge():
		return
	if not _assert_validator_rejects_unknown_endpoint():
		return
	if not _assert_snapshot_boundary():
		return
	print("v67.4 edge contracts test passed")
	quit(0)


func _assert_edge_contract_generation() -> bool:
	var result := _compile_default_edges()
	if not bool(result.get("success", false)):
		return _fail("v67.4 default edge generation failed: %s" % str(result.get("errors", [])))
	var edge_result: Dictionary = result.get("edge_contract_result", {}) as Dictionary
	if str(edge_result.get("stage", "")) != "edge_contracts":
		return _fail("v67.4 result has wrong stage: %s" % str(edge_result.get("stage", "")))
	var edges: Array = edge_result.get("edge_contracts", []) as Array
	if edges.is_empty():
		return _fail("v67.4 generated no edge contracts")
	var node_ids: Dictionary = {}
	for source_value in (result.get("location_node_results", []) as Array):
		var source: Dictionary = source_value as Dictionary
		for node_value in (source.get("location_nodes", []) as Array):
			var node: Dictionary = node_value as Dictionary
			node_ids[str(node.get("location_id", ""))] = true
	var found_cross_region_edge := false
	for edge_value in edges:
		var edge: Dictionary = edge_value as Dictionary
		var from_id := str(edge.get("from_location_id", ""))
		var to_id := str(edge.get("to_location_id", ""))
		if not node_ids.has(from_id) or not node_ids.has(to_id):
			return _fail("v67.4 edge references a node outside the supplied node set: %s" % str(edge))
		if not from_id.begins_with("loc.") or not to_id.begins_with("loc."):
			return _fail("v67.4 edge endpoint is not a Location Node id: %s" % str(edge))
		if str(edge.get("source_rule_id", "")).is_empty():
			return _fail("v67.4 edge is missing source_rule_id: %s" % str(edge))
		if str(edge.get("source_rule_id", "")) == "road_gate_to_forest_trailhead":
			if str(edge.get("endpoint_region_relation", "")) != "cross_region":
				return _fail("v67.4 cross-region relation was not derived after endpoint selection")
			found_cross_region_edge = true
	if not found_cross_region_edge:
		return _fail("v67.8 did not generate the rule-backed road gate to forest trailhead edge")
	var text := JSON.stringify(edge_result)
	for forbidden in ["start_location_id", "scene_path", "spawn_id", "exit_id", "exit_style", "direction_hint", "tilemap", "location_graph_snapshot", "external_connection_intent"]:
		if text.contains("\"%s\"" % forbidden):
			return _fail("v67.4 EdgeContractResult contains a forbidden later-stage field: %s" % forbidden)
	return true


func _assert_same_input_is_stable() -> bool:
	var first := _compile_default_edges()
	var second := _compile_default_edges()
	if not bool(first.get("success", false)) or not bool(second.get("success", false)):
		return _fail("v67.4 stability setup failed")
	if JSON.stringify(first.get("edge_contract_result", {})) != JSON.stringify(second.get("edge_contract_result", {})):
		return _fail("v67.4 produced different EdgeContractResult values for the same inputs")
	return true


func _assert_profile_rejects_region_selectors() -> bool:
	var profile_data := _load_json(EDGE_PROFILE_PATH)
	var rules: Array = profile_data.get("rules", []) as Array
	var first_rule: Dictionary = rules[0] as Dictionary
	var selector: Dictionary = first_rule.get("from_selector", {}) as Dictionary
	selector["region_type"] = "town_region"
	first_rule["from_selector"] = selector
	rules[0] = first_rule
	profile_data["rules"] = rules
	var profile: RefCounted = EdgeContractProfileScript.new()
	var errors: Array[String] = profile.configure(profile_data)
	if not str(errors).contains("region_type"):
		return _fail("v67.4 EdgeContractProfile accepted a Region selector: %s" % str(errors))
	return true


func _assert_missing_required_endpoint_fails() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var node_result: Dictionary = compiler.compile_location_nodes_result(_load_json(TOWN_REGION_INPUT_PATH))
	if not bool(node_result.get("success", false)):
		return _fail("v67.4 missing-endpoint setup failed")
	var source: Dictionary = (node_result.get("location_node_result", {}) as Dictionary).duplicate(true)
	var filtered_nodes: Array = []
	for node_value in (source.get("location_nodes", []) as Array):
		var node: Dictionary = node_value as Dictionary
		if str(node.get("location_type", "")) != "road_gate":
			filtered_nodes.append(node)
	source["location_nodes"] = filtered_nodes
	source["result_hash"] = CanonicalDataSerializerScript.location_node_result_hash(source)
	var result: Dictionary = compiler.compile_edge_contracts_from_location_nodes_result([source], EDGE_PROFILE_PATH)
	if bool(result.get("success", false)):
		return _fail("v67.4 generated edges after a required endpoint was removed")
	if not str(result.get("errors", [])).contains("required edge rule has no matching endpoint"):
		return _fail("v67.4 missing required endpoint did not fail clearly: %s" % str(result.get("errors", [])))
	return true


func _assert_ambiguous_matching_fails() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var first: Dictionary = compiler.compile_location_nodes_result(_load_json(TOWN_REGION_INPUT_PATH))
	var second_input: Dictionary = _load_json(TOWN_REGION_INPUT_PATH)
	second_input["region_id"] = "region.frontier.town_region.pine_crossing.rg_0003"
	second_input["region_slug"] = "pine_crossing"
	second_input["seed"] = 6703
	var second: Dictionary = compiler.compile_location_nodes_result(second_input)
	if not bool(first.get("success", false)) or not bool(second.get("success", false)):
		return _fail("v67.4 ambiguity setup failed")
	var result: Dictionary = compiler.compile_edge_contracts_from_location_nodes_result([
		first.get("location_node_result", {}),
		second.get("location_node_result", {}),
	], EDGE_PROFILE_PATH)
	if bool(result.get("success", false)):
		return _fail("v67.4 silently selected endpoints from an ambiguous node set")
	if not str(result.get("errors", [])).contains("ambiguous"):
		return _fail("v67.4 ambiguous endpoint selection did not fail clearly: %s" % str(result.get("errors", [])))
	return true


func _assert_unmatched_node_does_not_gain_default_edge() -> bool:
	var isolated_result := {
		"schema_version": 1,
		"compiler_version": "v67.3",
		"stage": "location_nodes",
		"region_id": "region.frontier.special_region.isolated_site.rg_0099",
		"region_type": "special_region",
		"region_slug": "isolated_site",
		"seed": 6799,
		"source_hash": "fixture_source",
		"semantic_role_source_hash": "fixture_role_source",
		"profile_path": "res://data/regions/location_node_profiles/town_region.json",
		"semantic_role_profile_path": "res://data/regions/region_type_profiles/town_region.json",
		"location_nodes": [
			{
				"location_id": "loc.frontier.special_region.isolated_site.landmark.ln_0001",
				"location_type": "isolated_site",
				"source_role_id": "role.frontier.special_region.isolated_site.landmark.rr_0001",
				"source_role_type": "landmark",
				"node_tags": ["landmark"],
			}
		],
		"role_node_bindings": [],
		"debug_summary": {},
	}
	isolated_result["result_hash"] = CanonicalDataSerializerScript.location_node_result_hash(isolated_result)
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_edge_contracts_from_location_nodes_result([isolated_result], EDGE_PROFILE_PATH)
	if not bool(result.get("success", false)):
		return _fail("v67.4 unmatched real node should remain valid without an edge: %s" % str(result.get("errors", [])))
	var edge_result: Dictionary = result.get("edge_contract_result", {}) as Dictionary
	if not (edge_result.get("edge_contracts", []) as Array).is_empty():
		return _fail("v67.4 generated a default edge for an unmatched node")
	return true


func _assert_validator_rejects_unknown_endpoint() -> bool:
	var compile_result := _compile_default_edges()
	if not bool(compile_result.get("success", false)):
		return _fail("v67.4 validator setup failed")
	var edge_result: Dictionary = (compile_result.get("edge_contract_result", {}) as Dictionary).duplicate(true)
	var edges: Array = edge_result.get("edge_contracts", []) as Array
	var first_edge: Dictionary = edges[0] as Dictionary
	first_edge["to_location_id"] = "loc.frontier.unknown_region.unknown.unknown.ln_9999"
	edges[0] = first_edge
	edge_result["edge_contracts"] = edges
	var profile_load: Dictionary = EdgeContractProfileScript.new().load_profile_result(EDGE_PROFILE_PATH)
	var validator: RefCounted = EdgeContractResultValidatorScript.new()
	var errors: Array[String] = validator.validate(
		edge_result,
		compile_result.get("location_node_results", []) as Array,
		profile_load.get("profile") as RefCounted
	)
	if not str(errors).contains("unknown node"):
		return _fail("v67.4 validator accepted an unknown edge endpoint: %s" % str(errors))
	return true


func _assert_snapshot_boundary() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_to_location_graph_result([
		_load_json(TOWN_REGION_INPUT_PATH),
		_load_json(FOREST_REGION_INPUT_PATH),
	], EDGE_PROFILE_PATH, GRAPH_ID)
	if not bool(result.get("success", false)):
		return _fail("v67.4 current Location Graph compilation failed: %s" % str(result.get("errors", [])))
	if (result.get("location_graph_snapshot", {}) as Dictionary).is_empty():
		return _fail("v67.4 current Location Graph compilation did not preserve a valid snapshot")
	return true


func _compile_default_edges() -> Dictionary:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	return compiler.compile_edge_contracts_result([
		_load_json(TOWN_REGION_INPUT_PATH),
		_load_json(FOREST_REGION_INPUT_PATH),
	], EDGE_PROFILE_PATH)


func _load_json(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
