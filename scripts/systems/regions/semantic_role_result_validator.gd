class_name SemanticRoleResultValidator
extends RefCounted

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const RegionSemanticVocabularyScript := preload("res://scripts/systems/regions/region_semantic_vocabulary.gd")
const SemanticRoleLibraryScript := preload("res://scripts/systems/regions/semantic_role_library.gd")

const SCHEMA_VERSION := 3
const FORBIDDEN_LOCATION_GRAPH_KEYS := {
	"location_id": true,
	"edge_id": true,
	"scene_path": true,
	"spawn_id": true,
	"tilemap": true,
	"target_location_id": true,
	"external_connection_intents": true,
	"external_connection_bindings": true,
	"source_intent_id": true,
	"boundary_location_id": true,
}
const ALLOWED_ROLE_SOURCES := ["required", "optional", "forced"]
const RESULT_KEYS := {
	"schema_version": true,
	"compiler_version": true,
	"stage": true,
	"region_id": true,
	"region_type": true,
	"region_slug": true,
	"seed": true,
	"source_hash": true,
	"profile_path": true,
	"role_library_id": true,
	"role_library_path": true,
	"role_library_content_hash": true,
	"demand_contract": true,
	"selected_roles": true,
	"need_coverage": true,
	"debug_summary": true,
}
const ROLE_KEYS := {
	"role_id": true,
	"role_type": true,
	"archetype_id": true,
	"form_id": true,
	"role_slug": true,
	"role_source": true,
	"role_tags": true,
	"satisfies": true,
	"properties": true,
	"affinity": true,
	"gameplay_affordances": true,
	"narrative_affordances": true,
	"category": true,
	"matched_need_ids": true,
	"archetype_definition_id": true,
	"archetype_definition_hash": true,
	"form_definition_id": true,
	"form_definition_hash": true,
	"role_library_id": true,
	"role_library_path": true,
	"role_library_content_hash": true,
}
const DEMAND_KEYS := {
	"required_needs": true,
	"optional_needs": true,
	"region_traits": true,
	"region_facts": true,
	"coarse_context": true,
}
const COVERAGE_KEYS := {
	"need_id": true,
	"required": true,
	"role_ids": true,
}


func validate(result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if result.is_empty():
		errors.append("SemanticRoleResult is empty")
		return errors
	_scan_for_forbidden_keys(result, "", errors)
	_validate_known_keys(result, RESULT_KEYS, "SemanticRoleResult", errors)
	if int(result.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("SemanticRoleResult.schema_version is unsupported: %s" % str(result.get("schema_version", "")))
	if str(result.get("stage", "")) != "semantic_roles":
		errors.append("SemanticRoleResult.stage must be semantic_roles")
	for key in ["compiler_version", "region_id", "region_type", "region_slug", "source_hash", "profile_path", "role_library_id", "role_library_path"]:
		if str(result.get(key, "")).is_empty():
			errors.append("SemanticRoleResult.%s is missing" % key)
	if not result.has("seed"):
		errors.append("SemanticRoleResult.seed is missing")
	var library_hash := str(result.get("role_library_content_hash", ""))
	if not CanonicalDataSerializerScript.is_sha256_hash(library_hash):
		errors.append("SemanticRoleResult.role_library_content_hash is invalid")
	var declared_library := _load_declared_library(result, errors)
	_validate_demand_contract(result.get("demand_contract", null), errors)
	if not (result.get("selected_roles", null) is Array):
		errors.append("SemanticRoleResult.selected_roles must be an array")
		return errors
	var selected_roles: Array = result.get("selected_roles", []) as Array
	if selected_roles.is_empty():
		errors.append("SemanticRoleResult.selected_roles must not be empty")
	var role_ids: Dictionary = {}
	var role_slugs: Dictionary = {}
	for index in range(selected_roles.size()):
		if not (selected_roles[index] is Dictionary):
			errors.append("SemanticRoleResult.selected_roles[%d] must be an object" % index)
			continue
		_validate_role(index, selected_roles[index] as Dictionary, result, declared_library, role_ids, role_slugs, errors)
	_validate_need_coverage(result.get("need_coverage", null), role_ids, errors)
	return errors


func _validate_role(index: int, role: Dictionary, result: Dictionary, library: RefCounted, role_ids: Dictionary, role_slugs: Dictionary, errors: Array[String]) -> void:
	var path := "SemanticRoleResult.selected_roles[%d]" % index
	_validate_known_keys(role, ROLE_KEYS, path, errors)
	for key in ROLE_KEYS.keys():
		if not role.has(key):
			errors.append("%s.%s is missing" % [path, str(key)])
	var role_id := str(role.get("role_id", ""))
	var role_type := str(role.get("role_type", ""))
	var archetype_id := str(role.get("archetype_id", ""))
	var form_id := str(role.get("form_id", ""))
	var role_slug := str(role.get("role_slug", ""))
	var role_source := str(role.get("role_source", ""))
	if role_id.is_empty() or not _is_role_id(role_id):
		errors.append("%s.role_id is invalid: %s" % [path, role_id])
	elif role_ids.has(role_id):
		errors.append("SemanticRoleResult contains duplicate role_id: %s" % role_id)
	role_ids[role_id] = role
	if role_type.is_empty() or not _is_system_token(role_type):
		errors.append("%s.role_type is invalid: %s" % [path, role_type])
	if archetype_id.is_empty() or not _is_system_token(archetype_id):
		errors.append("%s.archetype_id is invalid: %s" % [path, archetype_id])
	if form_id.is_empty() or not _is_system_token(form_id):
		errors.append("%s.form_id is invalid: %s" % [path, form_id])
	if role_type != form_id:
		errors.append("%s.role_type must equal form_id for the concrete semantic role" % path)
	if role_slug.is_empty() or not _is_system_token(role_slug):
		errors.append("%s.role_slug is invalid: %s" % [path, role_slug])
	elif role_slugs.has(role_slug):
		errors.append("SemanticRoleResult contains duplicate role_slug: %s" % role_slug)
	role_slugs[role_slug] = true
	if not ALLOWED_ROLE_SOURCES.has(role_source):
		errors.append("%s.role_source is invalid: %s" % [path, role_source])
	_validate_system_token_array(role.get("role_tags"), "%s.role_tags" % path, errors)
	_validate_typed_array(role.get("satisfies"), "%s.satisfies" % path, "needs", true, errors)
	_validate_typed_array(role.get("properties"), "%s.properties" % path, "properties", false, errors)
	_validate_typed_array(role.get("affinity"), "%s.affinity" % path, "affinity", false, errors)
	_validate_typed_array(role.get("gameplay_affordances"), "%s.gameplay_affordances" % path, "gameplay", true, errors)
	_validate_typed_array(role.get("narrative_affordances"), "%s.narrative_affordances" % path, "narrative", false, errors)
	_validate_typed_array(role.get("matched_need_ids"), "%s.matched_need_ids" % path, "needs", false, errors)
	var category := str(role.get("category", ""))
	if not RegionSemanticVocabularyScript.is_role_category(category):
		errors.append("%s.category is outside the role category vocabulary: %s" % [path, category])
	if role.get("satisfies", null) is Array and role.get("matched_need_ids", null) is Array:
		for need_id in (role.get("matched_need_ids", []) as Array):
			if not (role.get("satisfies", []) as Array).has(need_id):
				errors.append("%s.matched_need_ids contains a need not satisfied by the role: %s" % [path, str(need_id)])
	var archetype_definition_id := str(role.get("archetype_definition_id", ""))
	if not _is_namespaced_id(archetype_definition_id, "location_archetype") or not archetype_definition_id.ends_with(".%s" % archetype_id):
		errors.append("%s.archetype_definition_id is invalid: %s" % [path, archetype_definition_id])
	var form_definition_id := str(role.get("form_definition_id", ""))
	if not _is_namespaced_id(form_definition_id, "location_form") or not form_definition_id.ends_with(".%s" % form_id):
		errors.append("%s.form_definition_id is invalid: %s" % [path, form_definition_id])
	if not CanonicalDataSerializerScript.is_sha256_hash(str(role.get("archetype_definition_hash", ""))):
		errors.append("%s.archetype_definition_hash is invalid" % path)
	if not CanonicalDataSerializerScript.is_sha256_hash(str(role.get("form_definition_hash", ""))):
		errors.append("%s.form_definition_hash is invalid" % path)
	for key in ["role_library_id", "role_library_path", "role_library_content_hash"]:
		if str(role.get(key, "")) != str(result.get(key, "")):
			errors.append("%s.%s does not match SemanticRoleResult.%s" % [path, key, key])
	_validate_role_against_library(role, path, library, errors)


func _load_declared_library(result: Dictionary, errors: Array[String]) -> RefCounted:
	var library_path := str(result.get("role_library_path", ""))
	if library_path.is_empty():
		return null
	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result(library_path)
	if not bool(library_result.get("success", false)):
		for error in (library_result.get("errors", []) as Array):
			errors.append("SemanticRoleResult declared role library is invalid: %s" % str(error))
		return null
	var library: RefCounted = library_result.get("library") as RefCounted
	if str(result.get("role_library_id", "")) != str(library.library_id()):
		errors.append("SemanticRoleResult.role_library_id does not match the declared role library")
	if str(result.get("role_library_content_hash", "")) != str(library.library_content_hash()):
		errors.append("SemanticRoleResult.role_library_content_hash does not match the declared role library")
	return library


func _validate_role_against_library(role: Dictionary, path: String, library: RefCounted, errors: Array[String]) -> void:
	if library == null:
		return
	var archetype_id := str(role.get("archetype_id", ""))
	var form_id := str(role.get("form_id", ""))
	var definition: Dictionary = library.composed_definition(form_id)
	if definition.is_empty():
		errors.append("%s.form_id is not defined in the declared SemanticRoleLibrary: %s" % [path, form_id])
		return
	if str(library.form_archetype_id(form_id)) != archetype_id:
		errors.append("%s.form_id does not belong to archetype_id" % path)
	if not library.allows_source(form_id, str(role.get("role_source", ""))):
		errors.append("%s.role_source is not allowed by its archetype definition" % path)
	if str(role.get("archetype_definition_id", "")) != str(library.archetype_definition_id(archetype_id)):
		errors.append("%s.archetype_definition_id does not match the declared archetype definition" % path)
	if str(role.get("archetype_definition_hash", "")) != str(library.archetype_definition_hash(archetype_id)):
		errors.append("%s.archetype_definition_hash does not match the declared archetype definition" % path)
	if str(role.get("form_definition_id", "")) != str(library.form_definition_id(form_id)):
		errors.append("%s.form_definition_id does not match the declared form definition" % path)
	if str(role.get("form_definition_hash", "")) != str(library.form_definition_hash(form_id)):
		errors.append("%s.form_definition_hash does not match the declared form definition" % path)
	for field_name in ["satisfies", "properties", "affinity", "gameplay_affordances", "narrative_affordances"]:
		if CanonicalDataSerializerScript.serialize(role.get(field_name, [])) != CanonicalDataSerializerScript.serialize(definition.get(field_name, [])):
			errors.append("%s.%s does not match the declared archetype/form definitions" % [path, field_name])
	if str(role.get("category", "")) != str(definition.get("category", "")):
		errors.append("%s.category does not match the declared archetype definition" % path)


func _validate_demand_contract(value: Variant, errors: Array[String]) -> void:
	if not (value is Dictionary):
		errors.append("SemanticRoleResult.demand_contract must be an object")
		return
	var demand_contract: Dictionary = value as Dictionary
	_validate_known_keys(demand_contract, DEMAND_KEYS, "SemanticRoleResult.demand_contract", errors)
	_validate_typed_array(demand_contract.get("required_needs"), "SemanticRoleResult.demand_contract.required_needs", "needs", true, errors)
	_validate_typed_array(demand_contract.get("optional_needs"), "SemanticRoleResult.demand_contract.optional_needs", "needs", false, errors)
	_validate_typed_array(demand_contract.get("region_traits"), "SemanticRoleResult.demand_contract.region_traits", "traits", false, errors)
	_validate_typed_array(demand_contract.get("region_facts"), "SemanticRoleResult.demand_contract.region_facts", "facts", false, errors)
	if not (demand_contract.get("coarse_context", null) is Dictionary):
		errors.append("SemanticRoleResult.demand_contract.coarse_context must be an object")
	else:
		var context: Dictionary = demand_contract.get("coarse_context", {}) as Dictionary
		for key_value in context.keys():
			var context_key := str(key_value)
			if not RegionSemanticVocabularyScript.is_coarse_context_key(context_key):
				errors.append("SemanticRoleResult.demand_contract.coarse_context contains unsupported key: %s" % context_key)
				continue
			for context_value in RegionSemanticVocabularyScript.context_values(context.get(key_value)):
				if not RegionSemanticVocabularyScript.is_coarse_context_value(context_key, context_value):
					errors.append("SemanticRoleResult.demand_contract.coarse_context.%s contains unsupported value: %s" % [context_key, context_value])


func _validate_need_coverage(value: Variant, role_ids: Dictionary, errors: Array[String]) -> void:
	if not (value is Array):
		errors.append("SemanticRoleResult.need_coverage must be an array")
		return
	var coverage_values: Array = value as Array
	if coverage_values.is_empty():
		errors.append("SemanticRoleResult.need_coverage must not be empty")
	var seen_needs: Dictionary = {}
	for index in range(coverage_values.size()):
		var path := "SemanticRoleResult.need_coverage[%d]" % index
		if not (coverage_values[index] is Dictionary):
			errors.append("%s must be an object" % path)
			continue
		var coverage: Dictionary = coverage_values[index] as Dictionary
		_validate_known_keys(coverage, COVERAGE_KEYS, path, errors)
		var need_id := str(coverage.get("need_id", ""))
		if not RegionSemanticVocabularyScript.is_need_id(need_id):
			errors.append("%s.need_id is unsupported: %s" % [path, need_id])
		if seen_needs.has(need_id):
			errors.append("SemanticRoleResult.need_coverage contains duplicate need_id: %s" % need_id)
		seen_needs[need_id] = true
		if not (coverage.get("required", null) is bool):
			errors.append("%s.required must be a bool" % path)
		if not (coverage.get("role_ids", null) is Array):
			errors.append("%s.role_ids must be an array" % path)
			continue
		var covered_role_ids: Array = coverage.get("role_ids", []) as Array
		if bool(coverage.get("required", false)) and covered_role_ids.is_empty():
			errors.append("%s required need has no covering role: %s" % [path, need_id])
		for role_id_value in covered_role_ids:
			var role_id := str(role_id_value)
			if not role_ids.has(role_id):
				errors.append("%s references unknown role_id: %s" % [path, role_id])
				continue
			var role: Dictionary = role_ids.get(role_id, {}) as Dictionary
			if not (role.get("satisfies", []) as Array).has(need_id):
				errors.append("%s references role_id that does not satisfy %s: %s" % [path, need_id, role_id])


func _validate_typed_array(value: Variant, path: String, dimension: String, require_non_empty: bool, errors: Array[String]) -> void:
	if not (value is Array):
		errors.append("%s must be an array" % path)
		return
	var values: Array = value as Array
	if require_non_empty and values.is_empty():
		errors.append("%s must not be empty" % path)
	var seen: Dictionary = {}
	for item in values:
		var token := str(item)
		if seen.has(token):
			errors.append("%s contains duplicate token: %s" % [path, token])
		seen[token] = true
		var valid := false
		match dimension:
			"needs":
				valid = RegionSemanticVocabularyScript.is_need_id(token)
			"properties":
				valid = RegionSemanticVocabularyScript.is_role_property(token)
			"affinity":
				valid = RegionSemanticVocabularyScript.is_role_affinity(token)
			"gameplay":
				valid = RegionSemanticVocabularyScript.is_gameplay_affordance(token)
			"narrative":
				valid = RegionSemanticVocabularyScript.is_narrative_affordance(token)
			"traits":
				valid = RegionSemanticVocabularyScript.is_trait(token)
			"facts":
				valid = RegionSemanticVocabularyScript.is_fact(token)
		if not valid:
			errors.append("%s contains a token outside the %s vocabulary: %s" % [path, dimension, token])


func _validate_system_token_array(value: Variant, path: String, errors: Array[String]) -> void:
	if not (value is Array):
		errors.append("%s must be an array" % path)
		return
	var seen: Dictionary = {}
	for item in (value as Array):
		var token := str(item)
		if not _is_system_token(token):
			errors.append("%s must contain lowercase system tokens: %s" % [path, token])
		if seen.has(token):
			errors.append("%s contains duplicate token: %s" % [path, token])
		seen[token] = true


func _scan_for_forbidden_keys(value: Variant, path: String, errors: Array[String]) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		for key_value in dictionary.keys():
			var key := str(key_value)
			var next_path := key if path.is_empty() else "%s.%s" % [path, key]
			if bool(FORBIDDEN_LOCATION_GRAPH_KEYS.get(key, false)):
				errors.append("SemanticRoleResult must not contain Location Graph field before v67.3: %s" % next_path)
			_scan_for_forbidden_keys(dictionary.get(key_value), next_path, errors)
	elif value is Array:
		var values: Array = value as Array
		for index in range(values.size()):
			_scan_for_forbidden_keys(values[index], "%s[%d]" % [path, index], errors)


static func _validate_known_keys(data: Dictionary, allowed: Dictionary, path: String, errors: Array[String]) -> void:
	for key_value in data.keys():
		var key := str(key_value)
		if not allowed.has(key):
			errors.append("%s contains unsupported field: %s" % [path, key])


static func _is_role_id(value: String) -> bool:
	var segments := value.split(".")
	if segments.size() != 6 or str(segments[0]) != "role":
		return false
	if not _is_system_token(str(segments[1])):
		return false
	if not _is_system_token(str(segments[2])) or not str(segments[2]).ends_with("_region"):
		return false
	if not _is_system_token(str(segments[3])) or not _is_system_token(str(segments[4])):
		return false
	var code := str(segments[5])
	return code.begins_with("rr_") and code.substr(3).is_valid_int()


static func _is_namespaced_id(value: String, prefix: String) -> bool:
	var segments := value.split(".")
	if segments.size() < 2 or str(segments[0]) != prefix:
		return false
	for segment in segments:
		if not _is_system_token(str(segment)):
			return false
	return true


static func _is_system_token(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_lower := code >= 97 and code <= 122
		if not is_digit and not is_lower and code != 95:
			return false
	return true
