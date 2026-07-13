extends Node

const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")

const TOWN_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const FOREST_REGION_INPUT_PATH := "res://data/regions/frontier_forest_region.json"
const EDGE_PROFILE_PATH := "res://data/location_graph/edge_contract_profiles/default.json"
const GRAPH_ID := "graph.frontier.test_town.lg_0001"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_region_types_expand():
		return
	if not _assert_same_seed_reproducible():
		return
	if not _assert_different_seed_can_change_optional_roles():
		return
	if not _assert_invalid_inputs_fail():
		return
	if not _assert_location_graph_boundary():
		return
	print("v67.2 semantic role expansion smoke test passed")
	get_tree().quit(0)


func _assert_region_types_expand() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var town_result: Dictionary = compiler.compile_semantic_roles_result(_load_json(TOWN_REGION_INPUT_PATH))
	if not bool(town_result.get("success", false)):
		_fail("v67.2 town_region semantic roles failed: %s" % str(town_result.get("errors", [])))
		return false
	var forest_result: Dictionary = compiler.compile_semantic_roles_result(_load_json(FOREST_REGION_INPUT_PATH))
	if not bool(forest_result.get("success", false)):
		_fail("v67.2 forest_region semantic roles failed: %s" % str(forest_result.get("errors", [])))
		return false
	var town_roles: Dictionary = town_result.get("semantic_role_result", {}) as Dictionary
	var forest_roles: Dictionary = forest_result.get("semantic_role_result", {}) as Dictionary
	if not _assert_semantic_only(town_roles) or not _assert_semantic_only(forest_roles):
		return false
	if _role_type_signature(town_roles) == _role_type_signature(forest_roles):
		_fail("v67.2 town_region and forest_region produced the same role type signature")
		return false
	if not _has_role_source(town_roles, "required") or not _has_role_source(town_roles, "optional"):
		_fail("v67.2 town_region did not include required and optional role sources")
		return false
	if (town_roles.get("demand_contract", {}) as Dictionary).is_empty():
		_fail("v67.2 SemanticRoleResult did not include the v67.7 demand contract")
		return false
	if (town_roles.get("need_coverage", []) as Array).is_empty():
		_fail("v67.2 SemanticRoleResult did not include demand coverage")
		return false
	if not _roles_have_need_sources(town_roles):
		return false
	if _has_role_source(town_roles, "external") or JSON.stringify(town_roles).contains("external_connection"):
		_fail("v67.2 SemanticRoleResult must not contain external connection roles or intents")
		return false
	return true


func _assert_same_seed_reproducible() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var input := _load_json(TOWN_REGION_INPUT_PATH)
	var first: Dictionary = compiler.compile_semantic_roles_result(input)
	var second: Dictionary = compiler.compile_semantic_roles_result(input)
	if not bool(first.get("success", false)) or not bool(second.get("success", false)):
		_fail("v67.2 same-seed reproducibility setup failed")
		return false
	var first_signature := _role_signature(first.get("semantic_role_result", {}) as Dictionary)
	var second_signature := _role_signature(second.get("semantic_role_result", {}) as Dictionary)
	if first_signature != second_signature:
		_fail("v67.2 same seed did not reproduce the same semantic roles")
		return false
	return true


func _assert_different_seed_can_change_optional_roles() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var signatures: Dictionary = {}
	for offset in range(20):
		var input := _load_json(TOWN_REGION_INPUT_PATH)
		input["seed"] = int(input.get("seed", 0)) + offset
		var result: Dictionary = compiler.compile_semantic_roles_result(input)
		if not bool(result.get("success", false)):
			_fail("v67.2 different-seed generation failed at offset %d: %s" % [offset, str(result.get("errors", []))])
			return false
		var signature := _optional_role_signature(result.get("semantic_role_result", {}) as Dictionary)
		signatures[signature] = true
	if signatures.size() < 2:
		_fail("v67.2 different seeds did not produce varied optional role signatures")
		return false
	return true


func _assert_invalid_inputs_fail() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var old_required_roles := _load_json(TOWN_REGION_INPUT_PATH)
	old_required_roles["required_roles"] = ["settlement_core"]
	if not _fails_with(compiler.compile_semantic_roles_result(old_required_roles), "required_roles is not supported"):
		return false

	var unsupported_region := _load_json(TOWN_REGION_INPUT_PATH)
	unsupported_region["region_type"] = "desert_region"
	unsupported_region["region_id"] = "region.frontier.desert_region.dry_march.rg_0099"
	unsupported_region["region_slug"] = "dry_march"
	if not _fails_with(compiler.compile_semantic_roles_result(unsupported_region), "RegionTypeProfile resource is missing"):
		return false

	var unsupported_need := _load_json(TOWN_REGION_INPUT_PATH)
	(unsupported_need.get("optional_needs", []) as Array).append("imperial.taxation")
	if not _fails_with(compiler.compile_semantic_roles_result(unsupported_need), "not supported by the controlled vocabulary"):
		return false

	var duplicate_required_need := _load_json(TOWN_REGION_INPUT_PATH)
	(duplicate_required_need.get("required_needs", []) as Array).append("travel.access")
	if not _fails_with(compiler.compile_semantic_roles_result(duplicate_required_need), "duplicate need_id"):
		return false

	var unsupported_required_need := _load_json(TOWN_REGION_INPUT_PATH)
	unsupported_required_need["required_needs"] = ["danger.local"]
	if not _fails_with(compiler.compile_semantic_roles_result(unsupported_required_need), "has no required concrete form candidate"):
		return false

	var forced_unsupported := _load_json(TOWN_REGION_INPUT_PATH)
	forced_unsupported["forced_role_specs"] = [
		{
			"archetype_id": "castle",
			"role_slug": "old_castle"
		}
	]
	if not _fails_with(compiler.compile_semantic_roles_result(forced_unsupported), "unsupported archetype_id"):
		return false

	var external_field := _load_json(TOWN_REGION_INPUT_PATH)
	external_field["external_connection_intents"] = [
		{
			"intent_id": "east_road"
		}
	]
	if not _fails_with(compiler.compile_semantic_roles_result(external_field), "external_connection_intents is not supported"):
		return false

	return true


func _assert_location_graph_boundary() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_to_location_graph_result([_load_json(TOWN_REGION_INPUT_PATH)], EDGE_PROFILE_PATH, GRAPH_ID)
	if not bool(result.get("success", false)):
		_fail("v67.2 current Location Graph compilation failed: %s" % str(result.get("errors", [])))
		return false
	if (result.get("location_graph_snapshot", {}) as Dictionary).is_empty():
		_fail("v67.2 current Location Graph compilation did not include LocationGraphSnapshot")
		return false
	return true


func _fails_with(result: Dictionary, expected_text: String) -> bool:
	if bool(result.get("success", false)):
		_fail("v67.2 invalid input unexpectedly succeeded; expected %s" % expected_text)
		return false
	if not str(result.get("errors", [])).contains(expected_text):
		_fail("v67.2 invalid input did not report '%s': %s" % [expected_text, str(result.get("errors", []))])
		return false
	return true


func _assert_semantic_only(result: Dictionary) -> bool:
	for forbidden in ["location_id", "edge_id", "scene_path", "spawn_id", "target_location_id"]:
		if JSON.stringify(result).contains("\"%s\"" % forbidden):
			_fail("v67.2 SemanticRoleResult contains forbidden Location Graph field: %s" % forbidden)
			return false
	return true


func _has_role_source(result: Dictionary, source: String) -> bool:
	for role_value in (result.get("selected_roles", []) as Array):
		var role: Dictionary = role_value as Dictionary
		if str(role.get("role_source", "")) == source:
			return true
	return false


func _roles_have_need_sources(result: Dictionary) -> bool:
	for role_value in (result.get("selected_roles", []) as Array):
		var role: Dictionary = role_value as Dictionary
		if not (role.get("satisfies", null) is Array):
			_fail("v67.2 selected role is missing satisfies: %s" % str(role))
			return false
		if not (role.get("matched_need_ids", null) is Array):
			_fail("v67.2 selected role is missing matched_need_ids: %s" % str(role))
			return false
	return true


func _role_type_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	for role_value in (result.get("selected_roles", []) as Array):
		var role: Dictionary = role_value as Dictionary
		parts.append(str(role.get("role_type", "")))
	parts.sort()
	return "|".join(parts)


func _role_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	for role_value in (result.get("selected_roles", []) as Array):
		var role: Dictionary = role_value as Dictionary
		parts.append("%s:%s:%s" % [
			str(role.get("role_type", "")),
			str(role.get("role_slug", "")),
			str(role.get("role_source", "")),
		])
	parts.sort()
	return "|".join(parts)


func _optional_role_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	for role_value in (result.get("selected_roles", []) as Array):
		var role: Dictionary = role_value as Dictionary
		if str(role.get("role_source", "")) == "optional":
			parts.append(str(role.get("role_type", "")))
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
