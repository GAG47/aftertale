extends SceneTree

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const LocationNodeProfileScript := preload("res://scripts/systems/regions/location_node_profile.gd")
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
const REMOVED_PLACEHOLDERS := [
	"settlement_core",
	"support_area",
	"landmark",
	"main_exit",
	"entrance",
	"common_woods",
	"inner_area",
	"clearing",
	"river_edge",
	"stream",
	"hidden_grove",
	"forest_shrine",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_library_has_two_semantic_layers():
		return
	if not _assert_old_placeholders_and_circular_facts_are_gone():
		return
	if not _assert_typed_vocabulary_and_form_boundary_are_strict():
		return
	if not _assert_region_profiles_filter_semantics_not_form_pools():
		return
	if not _assert_result_provenance_contains_both_layers():
		return
	if not _assert_concrete_forms_expand_to_real_nodes():
		return
	if not _assert_snapshot_records_library_and_both_identities():
		return
	print("v67.8 semantic role archetype and form test passed")
	quit(0)


func _assert_library_has_two_semantic_layers() -> bool:
	var data := _load_json(ROLE_LIBRARY_PATH)
	if int(data.get("schema_version", 0)) != 2:
		return _fail("v67.8 SemanticRoleLibrary must use schema_version 2")
	if data.has("role_definitions"):
		return _fail("v67.8 SemanticRoleLibrary still contains flat role_definitions")
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(ROLE_LIBRARY_PATH)
	if not bool(library_result.get("success", false)):
		return _fail("v67.8 SemanticRoleLibrary failed to load: %s" % str(library_result.get("errors", [])))
	var library: RefCounted = library_result.get("library") as RefCounted
	if library.archetype_ids().size() < 10 or library.form_ids().size() < library.archetype_ids().size():
		return _fail("v67.8 library does not contain a reusable archetype/form layer")
	for archetype_id in library.archetype_ids():
		if library.forms_for_archetype(archetype_id).is_empty():
			return _fail("v67.8 archetype has no concrete form: %s" % archetype_id)
	for form_id in library.form_ids():
		var form: Dictionary = library.form_definition(form_id)
		if form.has("satisfies"):
			return _fail("v67.8 concrete form owns planning capabilities: %s" % form_id)
		if library.archetype_definition(library.form_archetype_id(form_id)).is_empty():
			return _fail("v67.8 concrete form references an unknown archetype: %s" % form_id)
	return true


func _assert_old_placeholders_and_circular_facts_are_gone() -> bool:
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(ROLE_LIBRARY_PATH)
	var library: RefCounted = library_result.get("library") as RefCounted
	for removed_id in REMOVED_PLACEHOLDERS:
		if library.archetype_ids().has(removed_id) or library.form_ids().has(removed_id):
			return _fail("v67.8 retained an old structural or mixed-level role: %s" % removed_id)
	var farmland: Dictionary = library.form_definition("farmland")
	if not (farmland.get("requires_facts", []) as Array).has("arable_land"):
		return _fail("v67.8 farmland does not depend on the pre-existing arable_land fact")
	if JSON.stringify(library.to_dictionary()).contains("has_farmland"):
		return _fail("v67.8 retained the circular has_farmland requirement")
	for water_form in ["town_well", "woodland_spring"]:
		if library.form_satisfies(water_form).has("travel.crossing"):
			return _fail("v67.8 water-source form incorrectly satisfies crossing: %s" % water_form)
	if not library.form_satisfies("ford").has("travel.crossing"):
		return _fail("v67.8 ford does not provide the crossing capability")
	return true


func _assert_typed_vocabulary_and_form_boundary_are_strict() -> bool:
	var data := _load_json(ROLE_LIBRARY_PATH)
	var invalid_property := data.duplicate(true)
	var archetypes: Dictionary = invalid_property.get("archetype_definitions", {}) as Dictionary
	var gathering: Dictionary = archetypes.get("gathering_place", {}) as Dictionary
	var properties: Array = gathering.get("properties", []) as Array
	properties.append("terrain.plain")
	gathering["properties"] = properties
	archetypes["gathering_place"] = gathering
	invalid_property["archetype_definitions"] = archetypes
	var property_errors: Array[String] = SemanticRoleLibraryScript.new().configure(invalid_property)
	if not str(property_errors).contains("outside the properties vocabulary"):
		return _fail("v67.8 accepted an affinity token as an archetype property: %s" % str(property_errors))

	var invalid_form := data.duplicate(true)
	var forms: Dictionary = invalid_form.get("form_definitions", {}) as Dictionary
	var square: Dictionary = forms.get("village_square", {}) as Dictionary
	square["satisfies"] = ["public.gathering"]
	forms["village_square"] = square
	invalid_form["form_definitions"] = forms
	var form_errors: Array[String] = SemanticRoleLibraryScript.new().configure(invalid_form)
	if not str(form_errors).contains("planning capabilities belong to its archetype"):
		return _fail("v67.8 allowed a concrete form to declare planning capabilities: %s" % str(form_errors))
	return true


func _assert_region_profiles_filter_semantics_not_form_pools() -> bool:
	for path in [TOWN_PROFILE_PATH, FOREST_PROFILE_PATH]:
		var data := _load_json(path)
		if int(data.get("schema_version", 0)) != 4:
			return _fail("v67.8 RegionTypeProfile must use schema_version 4: %s" % path)
		for forbidden in ["role_definitions", "role_weights", "allowed_role_types", "allowed_form_ids", "role_weight_overrides", "excluded_role_types"]:
			if data.has(forbidden):
				return _fail("v67.8 RegionTypeProfile retains concrete pool field %s: %s" % [forbidden, path])
		for required_scope in ["allowed_categories", "allowed_satisfies_domains", "required_properties", "allowed_properties", "excluded_form_ids"]:
			if not (data.get(required_scope, null) is Array):
				return _fail("v67.8 RegionTypeProfile is missing typed scope field %s: %s" % [required_scope, path])
		var errors: Array[String] = RegionTypeProfileScript.new().configure(data)
		if not errors.is_empty():
			return _fail("v67.8 RegionTypeProfile failed validation at %s: %s" % [path, str(errors)])
	return true


func _assert_result_provenance_contains_both_layers() -> bool:
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(ROLE_LIBRARY_PATH)
	var library: RefCounted = library_result.get("library") as RefCounted
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	for input_path in [TOWN_REGION_INPUT_PATH, FOREST_REGION_INPUT_PATH]:
		var compile_result: Dictionary = compiler.compile_semantic_roles_result(_load_json(input_path))
		if not bool(compile_result.get("success", false)):
			return _fail("v67.8 semantic role compilation failed at %s: %s" % [input_path, str(compile_result.get("errors", []))])
		var result: Dictionary = compile_result.get("semantic_role_result", {}) as Dictionary
		if int(result.get("schema_version", 0)) != 3:
			return _fail("v67.8 SemanticRoleResult did not advance to schema 3")
		for role_value in (result.get("selected_roles", []) as Array):
			var role: Dictionary = role_value as Dictionary
			var archetype_id := str(role.get("archetype_id", ""))
			var form_id := str(role.get("form_id", ""))
			if str(role.get("role_type", "")) != form_id:
				return _fail("v67.8 concrete role_type does not equal form_id: %s" % form_id)
			if str(role.get("archetype_definition_id", "")) != library.archetype_definition_id(archetype_id):
				return _fail("v67.8 selected role has the wrong archetype_definition_id: %s" % archetype_id)
			if str(role.get("archetype_definition_hash", "")) != library.archetype_definition_hash(archetype_id):
				return _fail("v67.8 selected role has the wrong archetype_definition_hash: %s" % archetype_id)
			if str(role.get("form_definition_id", "")) != library.form_definition_id(form_id):
				return _fail("v67.8 selected role has the wrong form_definition_id: %s" % form_id)
			if str(role.get("form_definition_hash", "")) != library.form_definition_hash(form_id):
				return _fail("v67.8 selected role has the wrong form_definition_hash: %s" % form_id)
			if not (role.get("gameplay_affordances", null) is Array) or not (role.get("narrative_affordances", null) is Array):
				return _fail("v67.8 selected role does not carry its affordances: %s" % form_id)
		var tampered := result.duplicate(true)
		var roles: Array = tampered.get("selected_roles", []) as Array
		var role: Dictionary = roles[0] as Dictionary
		role["form_definition_hash"] = "sha256_0000000000000000000000000000000000000000000000000000000000000000"
		roles[0] = role
		tampered["selected_roles"] = roles
		var errors: Array[String] = SemanticRoleResultValidatorScript.new().validate(tampered)
		if not str(errors).contains("form_definition_hash does not match"):
			return _fail("v67.8 validator accepted a forged form hash: %s" % str(errors))
	return true


func _assert_concrete_forms_expand_to_real_nodes() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var all_mapped_forms: Dictionary = {}
	for profile_path in [TOWN_LOCATION_PROFILE_PATH, FOREST_LOCATION_PROFILE_PATH]:
		var profile_data := _load_json(profile_path)
		if int(profile_data.get("schema_version", 0)) != 2 or profile_data.has("role_to_location_rules"):
			return _fail("v67.8 LocationNodeProfile did not migrate to form_to_location_rules: %s" % profile_path)
		for form_id_value in (profile_data.get("form_to_location_rules", {}) as Dictionary).keys():
			all_mapped_forms[str(form_id_value)] = true
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(ROLE_LIBRARY_PATH)
	var library: RefCounted = library_result.get("library") as RefCounted
	for form_id in library.form_ids():
		if not all_mapped_forms.has(form_id):
			return _fail("v67.8 concrete form has no LocationNodeProfile mapping: %s" % form_id)
	for input_path in [TOWN_REGION_INPUT_PATH, FOREST_REGION_INPUT_PATH]:
		var node_result: Dictionary = compiler.compile_location_nodes_result(_load_json(input_path))
		if not bool(node_result.get("success", false)):
			return _fail("v67.8 concrete node expansion failed at %s: %s" % [input_path, str(node_result.get("errors", []))])
		var result: Dictionary = node_result.get("location_node_result", {}) as Dictionary
		if int(result.get("schema_version", 0)) != 3:
			return _fail("v67.8 LocationNodeResult did not advance to schema 3")
		for node_value in (result.get("location_nodes", []) as Array):
			var node: Dictionary = node_value as Dictionary
			if str(node.get("source_archetype_id", "")).is_empty() or str(node.get("source_form_id", "")).is_empty():
				return _fail("v67.8 node does not preserve both semantic identities: %s" % str(node))
			if str(node.get("source_role_type", "")) != str(node.get("source_form_id", "")):
				return _fail("v67.8 node concrete role identity differs from form identity")
			if not (node.get("gameplay_affordances", null) is Array) or not (node.get("narrative_affordances", null) is Array):
				return _fail("v67.8 node does not carry semantic affordances")
	return true


func _assert_snapshot_records_library_and_both_identities() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_to_location_graph_result([
		_load_json(TOWN_REGION_INPUT_PATH),
		_load_json(FOREST_REGION_INPUT_PATH),
	], EDGE_PROFILE_PATH, GRAPH_ID)
	if not bool(result.get("success", false)):
		return _fail("v67.8 full LocationGraphSnapshot compilation failed: %s" % str(result.get("errors", [])))
	var snapshot: Dictionary = result.get("location_graph_snapshot", {}) as Dictionary
	if int(snapshot.get("schema_version", 0)) != 3 or str(snapshot.get("compiler_version", "")) != "v67.8":
		return _fail("v67.8 Snapshot schema or compiler label is stale")
	var role_library_rows := 0
	for row_value in (snapshot.get("rule_manifest", []) as Array):
		var row: Dictionary = row_value as Dictionary
		if str(row.get("profile_kind", "")) == "semantic_role_library":
			role_library_rows += 1
	if role_library_rows != 1:
		return _fail("v67.8 Snapshot must contain exactly one semantic role library manifest row")
	for node_value in (snapshot.get("location_nodes", []) as Array):
		var node: Dictionary = node_value as Dictionary
		if str(node.get("source_archetype_id", "")).is_empty() or str(node.get("source_form_id", "")).is_empty():
			return _fail("v67.8 Snapshot dropped archetype/form provenance")
	if not CanonicalDataSerializerScript.is_sha256_hash(str(snapshot.get("content_hash", ""))):
		return _fail("v67.8 Snapshot content hash is invalid")
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
