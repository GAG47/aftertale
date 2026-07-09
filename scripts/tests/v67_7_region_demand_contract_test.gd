extends Node

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")

const TOWN_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const FOREST_REGION_INPUT_PATH := "res://data/regions/frontier_forest_region.json"
const EDGE_PROFILE_PATH := "res://data/location_graph/edge_contract_profiles/default.json"
const GRAPH_ID := "graph.frontier.v67_7_demand_contract.lg_0001"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_region_input_uses_demand_contract():
		return
	if not _assert_semantic_roles_cover_required_needs():
		return
	if not _assert_old_role_pool_contract_fails():
		return
	if not _assert_full_location_graph_still_compiles():
		return
	print("v67.7 region demand contract test passed")
	get_tree().quit(0)


func _assert_region_input_uses_demand_contract() -> bool:
	for path in [TOWN_REGION_INPUT_PATH, FOREST_REGION_INPUT_PATH]:
		var data := _load_json(path)
		if int(data.get("schema_version", 0)) != 2:
			_fail("v67.7 RegionInput must use schema_version 2: %s" % path)
			return false
		for forbidden in ["required_roles", "optional_role_pool"]:
			if data.has(forbidden):
				_fail("v67.7 RegionInput still contains role-pool field %s at %s" % [forbidden, path])
				return false
		var input: RefCounted = RegionInputScript.new()
		var errors: Array[String] = input.configure(data)
		if not errors.is_empty():
			_fail("v67.7 RegionInput failed demand validation at %s: %s" % [path, str(errors)])
			return false
	return true


func _assert_semantic_roles_cover_required_needs() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	for path in [TOWN_REGION_INPUT_PATH, FOREST_REGION_INPUT_PATH]:
		var result: Dictionary = compiler.compile_semantic_roles_result(_load_json(path))
		if not bool(result.get("success", false)):
			_fail("v67.7 semantic role demand expansion failed at %s: %s" % [path, str(result.get("errors", []))])
			return false
		var roles_result: Dictionary = result.get("semantic_role_result", {}) as Dictionary
		var demand_contract: Dictionary = roles_result.get("demand_contract", {}) as Dictionary
		var required_needs: Array = demand_contract.get("required_needs", []) as Array
		if required_needs.is_empty():
			_fail("v67.7 SemanticRoleResult required_needs is empty at %s" % path)
			return false
		for need_id in required_needs:
			if not _required_need_has_role(roles_result, str(need_id)):
				_fail("v67.7 required need is not covered by a selected role at %s: %s" % [path, str(need_id)])
				return false
		for role_value in (roles_result.get("selected_roles", []) as Array):
			var role: Dictionary = role_value as Dictionary
			if not (role.get("satisfies", null) is Array) or (role.get("satisfies", []) as Array).is_empty():
				_fail("v67.7 selected role lacks satisfies: %s" % str(role))
				return false
			if not (role.get("matched_need_ids", null) is Array):
				_fail("v67.7 selected role lacks matched_need_ids: %s" % str(role))
				return false
	return true


func _assert_old_role_pool_contract_fails() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var old_input := _load_json(TOWN_REGION_INPUT_PATH)
	old_input["required_roles"] = ["settlement_core"]
	old_input["optional_role_pool"] = ["market"]
	var result: Dictionary = compiler.compile_semantic_roles_result(old_input)
	if bool(result.get("success", false)):
		_fail("v67.7 RegionInput with old role-pool fields unexpectedly passed")
		return false
	if not str(result.get("errors", [])).contains("required_roles is not supported"):
		_fail("v67.7 old role-pool failure did not mention required_roles: %s" % str(result.get("errors", [])))
		return false
	return true


func _assert_full_location_graph_still_compiles() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_to_location_graph_result([
		_load_json(TOWN_REGION_INPUT_PATH),
		_load_json(FOREST_REGION_INPUT_PATH),
	], EDGE_PROFILE_PATH, GRAPH_ID)
	if not bool(result.get("success", false)):
		_fail("v67.7 full LocationGraphSnapshot compilation failed: %s" % str(result.get("errors", [])))
		return false
	if (result.get("location_graph_snapshot", {}) as Dictionary).is_empty():
		_fail("v67.7 full compilation did not produce LocationGraphSnapshot")
		return false
	return true


func _required_need_has_role(result: Dictionary, need_id: String) -> bool:
	for coverage_value in (result.get("need_coverage", []) as Array):
		var coverage: Dictionary = coverage_value as Dictionary
		if str(coverage.get("need_id", "")) == need_id and bool(coverage.get("required", false)):
			return not (coverage.get("role_ids", []) as Array).is_empty()
	return false


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
