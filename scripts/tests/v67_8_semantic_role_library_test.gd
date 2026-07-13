extends SceneTree

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")
const RegionTypeProfileScript := preload("res://scripts/systems/regions/region_type_profile.gd")
const SemanticRoleLibraryScript := preload("res://scripts/systems/regions/semantic_role_library.gd")
const SemanticRoleResultValidatorScript := preload("res://scripts/systems/regions/semantic_role_result_validator.gd")

const TOWN_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const FOREST_REGION_INPUT_PATH := "res://data/regions/frontier_forest_region.json"
const TOWN_PROFILE_PATH := "res://data/regions/region_type_profiles/town_region.json"
const FOREST_PROFILE_PATH := "res://data/regions/region_type_profiles/forest_region.json"
const ROLE_LIBRARY_PATH := "res://data/regions/semantic_role_libraries/core.json"
const TOWN_LOCATION_PROFILE_PATH := "res://data/regions/location_node_profiles/town_region.json"
const FOREST_LOCATION_PROFILE_PATH := "res://data/regions/location_node_profiles/forest_region.json"
const EDGE_PROFILE_PATH := "res://data/location_graph/edge_contract_profiles/default.json"
const GRAPH_ID := "graph.frontier.v67_8_role_library.lg_0001"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_role_definitions_have_one_owner():
		return
	if not _assert_typed_vocabulary_is_strict():
		return
	if not _assert_scope_and_hard_conditions_are_applied():
		return
	if not _assert_result_provenance_is_complete():
		return
	if not _assert_snapshot_records_role_library():
		return
	if not _assert_current_library_closes_downstream():
		return
	print("v67.8 semantic role library test passed")
	quit(0)


func _assert_role_definitions_have_one_owner() -> bool:
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(ROLE_LIBRARY_PATH)
	if not bool(library_result.get("success", false)):
		return _fail("v67.8 SemanticRoleLibrary failed to load: %s" % str(library_result.get("errors", [])))
	var library: RefCounted = library_result.get("library") as RefCounted
	if library.role_types().is_empty():
		return _fail("v67.8 SemanticRoleLibrary contains no roles")
	for path in [TOWN_PROFILE_PATH, FOREST_PROFILE_PATH]:
		var profile_data := _load_json(path)
		if int(profile_data.get("schema_version", 0)) != 3:
			return _fail("v67.8 RegionTypeProfile must use schema_version 3: %s" % path)
		for forbidden in ["role_definitions", "role_weights", "allowed_role_types", "role_weight_overrides"]:
			if profile_data.has(forbidden):
				return _fail("v67.8 RegionTypeProfile retains concrete role-pool field %s: %s" % [forbidden, path])
		for required_scope in ["allowed_categories", "allowed_satisfies_domains", "required_properties", "allowed_properties", "excluded_role_types"]:
			if not (profile_data.get(required_scope, null) is Array):
				return _fail("v67.8 RegionTypeProfile is missing typed scope field %s: %s" % [required_scope, path])
		var profile: RefCounted = RegionTypeProfileScript.new()
		var errors: Array[String] = profile.configure(profile_data)
		if not errors.is_empty():
			return _fail("v67.8 RegionTypeProfile failed validation at %s: %s" % [path, str(errors)])
	var old_profile := _load_json(TOWN_PROFILE_PATH)
	old_profile["role_definitions"] = {}
	old_profile["role_weights"] = {"farmland": 1.0}
	old_profile["allowed_role_types"] = ["farmland"]
	var old_errors: Array[String] = RegionTypeProfileScript.new().configure(old_profile)
	for forbidden in ["role_definitions", "role_weights", "allowed_role_types"]:
		if not str(old_errors).contains("%s is not supported" % forbidden):
			return _fail("v67.8 old concrete role field did not fail clearly: %s / %s" % [forbidden, str(old_errors)])
	return true


func _assert_typed_vocabulary_is_strict() -> bool:
	var library_data := _load_json(ROLE_LIBRARY_PATH)
	var invalid_library := library_data.duplicate(true)
	var definitions: Dictionary = invalid_library.get("role_definitions", {}) as Dictionary
	var core: Dictionary = definitions.get("settlement_core", {}) as Dictionary
	var properties: Array = core.get("properties", []) as Array
	properties.append("terrain.plain")
	core["properties"] = properties
	definitions["settlement_core"] = core
	invalid_library["role_definitions"] = definitions
	var library_errors: Array[String] = SemanticRoleLibraryScript.new().configure(invalid_library)
	if not str(library_errors).contains("outside the properties vocabulary"):
		return _fail("v67.8 accepted an affinity token in role properties: %s" % str(library_errors))

	var invalid_profile := _load_json(TOWN_PROFILE_PATH)
	var categories: Array = invalid_profile.get("allowed_categories", []) as Array
	categories.append("production")
	invalid_profile["allowed_categories"] = categories
	var profile_errors: Array[String] = RegionTypeProfileScript.new().configure(invalid_profile)
	if not str(profile_errors).contains("outside the category vocabulary"):
		return _fail("v67.8 accepted a need domain as a role category: %s" % str(profile_errors))

	var changed_library := library_data.duplicate(true)
	var changed_definitions: Dictionary = changed_library.get("role_definitions", {}) as Dictionary
	var landmark: Dictionary = changed_definitions.get("landmark", {}) as Dictionary
	var affinity: Array = landmark.get("affinity", []) as Array
	affinity.append("resource.abundant")
	landmark["affinity"] = affinity
	changed_definitions["landmark"] = landmark
	changed_library["role_definitions"] = changed_definitions
	var first: RefCounted = SemanticRoleLibraryScript.new()
	var second: RefCounted = SemanticRoleLibraryScript.new()
	if not first.configure(library_data).is_empty() or not second.configure(changed_library).is_empty():
		return _fail("v67.8 valid role-library hash fixtures failed validation")
	if first.library_content_hash() == second.library_content_hash():
		return _fail("v67.8 role library content change did not change its content hash")
	return true


func _assert_scope_and_hard_conditions_are_applied() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var invalid_context := _load_json(FOREST_REGION_INPUT_PATH)
	var context: Dictionary = invalid_context.get("coarse_context", {}) as Dictionary
	context["terrain_context"] = "plain"
	invalid_context["coarse_context"] = context
	var context_result: Dictionary = compiler.compile_semantic_roles_result(invalid_context)
	if bool(context_result.get("success", false)) or not str(context_result.get("errors", [])).contains("has no required role candidate"):
		return _fail("v67.8 requires_context did not reject a forest entrance in plain context: %s" % str(context_result.get("errors", [])))

	var out_of_scope := _load_json(TOWN_REGION_INPUT_PATH)
	out_of_scope["forced_role_specs"] = [{
		"role_type": "hidden_grove",
		"role_slug": "hidden_grove",
	}]
	var scope_result: Dictionary = compiler.compile_semantic_roles_result(out_of_scope)
	if bool(scope_result.get("success", false)) or not str(scope_result.get("errors", [])).contains("outside RegionTypeProfile semantic scope"):
		return _fail("v67.8 typed profile scope did not reject hidden_grove in town: %s" % str(scope_result.get("errors", [])))
	return true


func _assert_result_provenance_is_complete() -> bool:
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(ROLE_LIBRARY_PATH)
	if not bool(library_result.get("success", false)):
		return _fail("v67.8 provenance library setup failed")
	var library: RefCounted = library_result.get("library") as RefCounted
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	for input_path in [TOWN_REGION_INPUT_PATH, FOREST_REGION_INPUT_PATH]:
		var compile_result: Dictionary = compiler.compile_semantic_roles_result(_load_json(input_path))
		if not bool(compile_result.get("success", false)):
			return _fail("v67.8 semantic role compilation failed at %s: %s" % [input_path, str(compile_result.get("errors", []))])
		var result: Dictionary = compile_result.get("semantic_role_result", {}) as Dictionary
		if str(result.get("role_library_id", "")) != library.library_id():
			return _fail("v67.8 SemanticRoleResult has the wrong role_library_id")
		if str(result.get("role_library_path", "")) != ROLE_LIBRARY_PATH:
			return _fail("v67.8 SemanticRoleResult has the wrong role_library_path")
		if str(result.get("role_library_content_hash", "")) != library.library_content_hash():
			return _fail("v67.8 SemanticRoleResult has the wrong role_library_content_hash")
		for role_value in (result.get("selected_roles", []) as Array):
			var role: Dictionary = role_value as Dictionary
			var role_type := str(role.get("role_type", ""))
			if str(role.get("role_definition_id", "")) != library.role_definition_id(role_type):
				return _fail("v67.8 selected role has the wrong role_definition_id: %s" % role_type)
			if str(role.get("role_definition_hash", "")) != library.role_definition_hash(role_type):
				return _fail("v67.8 selected role has the wrong role_definition_hash: %s" % role_type)
			for key in ["role_library_id", "role_library_path", "role_library_content_hash"]:
				if str(role.get(key, "")) != str(result.get(key, "")):
					return _fail("v67.8 selected role source does not match result source: %s / %s" % [role_type, key])
		if input_path == TOWN_REGION_INPUT_PATH:
			var tampered := result.duplicate(true)
			var tampered_roles: Array = tampered.get("selected_roles", []) as Array
			var tampered_role: Dictionary = tampered_roles[0] as Dictionary
			tampered_role["role_definition_hash"] = "sha256_0000000000000000000000000000000000000000000000000000000000000000"
			tampered_roles[0] = tampered_role
			tampered["selected_roles"] = tampered_roles
			var tamper_errors: Array[String] = SemanticRoleResultValidatorScript.new().validate(tampered)
			if not str(tamper_errors).contains("role_definition_hash does not match"):
				return _fail("v67.8 SemanticRoleResultValidator accepted a forged role_definition_hash: %s" % str(tamper_errors))
	return true


func _assert_snapshot_records_role_library() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_to_location_graph_result([
		_load_json(TOWN_REGION_INPUT_PATH),
		_load_json(FOREST_REGION_INPUT_PATH),
	], EDGE_PROFILE_PATH, GRAPH_ID)
	if not bool(result.get("success", false)):
		return _fail("v67.8 full LocationGraphSnapshot compilation failed: %s" % str(result.get("errors", [])))
	var snapshot: Dictionary = result.get("location_graph_snapshot", {}) as Dictionary
	if int(snapshot.get("schema_version", 0)) != 2:
		return _fail("v67.8 LocationGraphSnapshot did not advance to provenance schema 2")
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(ROLE_LIBRARY_PATH)
	var library: RefCounted = library_result.get("library") as RefCounted
	var matching_rows := 0
	for row_value in (snapshot.get("rule_manifest", []) as Array):
		var row: Dictionary = row_value as Dictionary
		if str(row.get("profile_kind", "")) != "semantic_role_library":
			continue
		matching_rows += 1
		if str(row.get("profile_path", "")) != ROLE_LIBRARY_PATH:
			return _fail("v67.8 Snapshot role-library manifest has the wrong path")
		if str(row.get("profile_content_hash", "")) != library.library_content_hash():
			return _fail("v67.8 Snapshot role-library manifest has the wrong content hash")
	if matching_rows != 1:
		return _fail("v67.8 Snapshot rule_manifest must contain exactly one role library; found %d" % matching_rows)
	if not CanonicalDataSerializerScript.is_sha256_hash(str(snapshot.get("content_hash", ""))):
		return _fail("v67.8 Snapshot content hash is invalid")
	return true


func _assert_current_library_closes_downstream() -> bool:
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(ROLE_LIBRARY_PATH)
	var library: RefCounted = library_result.get("library") as RefCounted
	var location_types_by_role: Dictionary = {}
	for path in [TOWN_LOCATION_PROFILE_PATH, FOREST_LOCATION_PROFILE_PATH]:
		var profile := _load_json(path)
		var rules: Dictionary = profile.get("role_to_location_rules", {}) as Dictionary
		for role_type_value in rules.keys():
			var rule: Dictionary = rules.get(role_type_value, {}) as Dictionary
			location_types_by_role[str(role_type_value)] = str(rule.get("location_type", ""))
	var edge_location_types: Dictionary = {}
	var edge_profile := _load_json(EDGE_PROFILE_PATH)
	for rule_value in (edge_profile.get("rules", []) as Array):
		var rule: Dictionary = rule_value as Dictionary
		for selector_key in ["from_selector", "to_selector"]:
			var selector: Dictionary = rule.get(selector_key, {}) as Dictionary
			for location_type_value in (selector.get("location_types", []) as Array):
				edge_location_types[str(location_type_value)] = true
	for role_type in library.role_types():
		if not location_types_by_role.has(role_type):
			return _fail("v67.8 role library contains a role with no LocationNodeProfile mapping: %s" % role_type)
		var location_type := str(location_types_by_role.get(role_type, ""))
		if not edge_location_types.has(location_type):
			return _fail("v67.8 role library expands to a location type absent from EdgeContractProfile selectors: %s / %s" % [role_type, location_type])
	return true


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
