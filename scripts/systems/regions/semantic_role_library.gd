class_name SemanticRoleLibrary
extends RefCounted

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const RegionSemanticVocabularyScript := preload("res://scripts/systems/regions/region_semantic_vocabulary.gd")

const SCHEMA_VERSION := 1
const DEFAULT_LIBRARY_PATH := "res://data/regions/semantic_role_libraries/core.json"
const TOP_LEVEL_KEYS := {
	"schema_version": true,
	"library_id": true,
	"library_type": true,
	"role_definitions": true,
}
const ROLE_DEFINITION_KEYS := {
	"role_definition_id": true,
	"satisfies": true,
	"properties": true,
	"affinity": true,
	"category": true,
	"requires_traits": true,
	"excludes_traits": true,
	"requires_facts": true,
	"excludes_facts": true,
	"requires_context": true,
	"excludes_context": true,
	"allowed_sources": true,
	"allow_multiple": true,
}
const ALLOWED_SOURCES := ["required", "optional", "forced"]

var source_data: Dictionary = {}
var source_path := ""
var source_content_hash := ""


func configure(data: Dictionary, resource_path: String = "") -> Array[String]:
	source_data = data.duplicate(true)
	source_path = resource_path
	source_content_hash = CanonicalDataSerializerScript.profile_content_hash(source_data)
	return validate()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if source_data.is_empty():
		errors.append("SemanticRoleLibrary is empty")
		return errors
	_validate_known_keys(source_data, TOP_LEVEL_KEYS, "SemanticRoleLibrary", errors)
	if int(source_data.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("SemanticRoleLibrary.schema_version is unsupported: %s" % str(source_data.get("schema_version", "")))
	if str(source_data.get("library_type", "")) != "semantic_role_library":
		errors.append("SemanticRoleLibrary.library_type must be semantic_role_library")
	var id := library_id()
	if not _is_namespaced_id(id, "semantic_role_library"):
		errors.append("SemanticRoleLibrary.library_id is invalid: %s" % id)
	if not (source_data.get("role_definitions", null) is Dictionary):
		errors.append("SemanticRoleLibrary.role_definitions must be an object")
		return errors
	var definitions: Dictionary = source_data.get("role_definitions", {}) as Dictionary
	if definitions.is_empty():
		errors.append("SemanticRoleLibrary.role_definitions must not be empty")
	var definition_ids: Dictionary = {}
	for role_type_value in definitions.keys():
		var role_type := str(role_type_value)
		if not (definitions.get(role_type_value, null) is Dictionary):
			errors.append("SemanticRoleLibrary role definition must be an object: %s" % role_type)
			continue
		_validate_role_definition(role_type, definitions.get(role_type_value, {}) as Dictionary, definition_ids, errors)
	if source_content_hash.is_empty():
		errors.append("SemanticRoleLibrary content hash could not be calculated")
	return errors


func to_dictionary() -> Dictionary:
	return source_data.duplicate(true)


func library_id() -> String:
	return str(source_data.get("library_id", ""))


func library_path() -> String:
	return source_path


func library_content_hash() -> String:
	return source_content_hash


func role_types() -> Array[String]:
	var result: Array[String] = []
	var definitions: Dictionary = source_data.get("role_definitions", {}) as Dictionary
	for role_type_value in definitions.keys():
		result.append(str(role_type_value))
	result.sort()
	return result


func role_definition(role_type: String) -> Dictionary:
	var definitions: Dictionary = source_data.get("role_definitions", {}) as Dictionary
	if not (definitions.get(role_type, null) is Dictionary):
		return {}
	return (definitions.get(role_type, {}) as Dictionary).duplicate(true)


func role_definition_id(role_type: String) -> String:
	return str(role_definition(role_type).get("role_definition_id", ""))


func role_definition_hash(role_type: String) -> String:
	var definition := role_definition(role_type)
	if definition.is_empty():
		return ""
	return CanonicalDataSerializerScript.hash_value({
		"role_type": role_type,
		"definition": definition,
	})


func role_satisfies(role_type: String) -> Array[String]:
	return _string_array(role_definition(role_type).get("satisfies", []) as Array)


func role_properties(role_type: String) -> Array[String]:
	return _string_array(role_definition(role_type).get("properties", []) as Array)


func role_affinity(role_type: String) -> Array[String]:
	return _string_array(role_definition(role_type).get("affinity", []) as Array)


func role_category(role_type: String) -> String:
	return str(role_definition(role_type).get("category", ""))


func allows_source(role_type: String, source: String) -> bool:
	return _string_array(role_definition(role_type).get("allowed_sources", []) as Array).has(source)


func allows_multiple(role_type: String) -> bool:
	return bool(role_definition(role_type).get("allow_multiple", false))


func conditions_match(role_type: String, region_data: Dictionary) -> bool:
	var definition := role_definition(role_type)
	if definition.is_empty():
		return false
	var traits := _string_array(region_data.get("region_traits", []) as Array)
	var facts := _string_array(region_data.get("region_facts", []) as Array)
	if not _contains_all(traits, _string_array(definition.get("requires_traits", []) as Array)):
		return false
	if _contains_any(traits, _string_array(definition.get("excludes_traits", []) as Array)):
		return false
	if not _contains_all(facts, _string_array(definition.get("requires_facts", []) as Array)):
		return false
	if _contains_any(facts, _string_array(definition.get("excludes_facts", []) as Array)):
		return false
	var context: Dictionary = region_data.get("coarse_context", {}) as Dictionary
	if not _required_context_matches(definition.get("requires_context", {}) as Dictionary, context):
		return false
	if _excluded_context_matches(definition.get("excludes_context", {}) as Dictionary, context):
		return false
	return true


func load_library_result(resource_path: String = DEFAULT_LIBRARY_PATH) -> Dictionary:
	if resource_path.is_empty():
		return _failure(["SemanticRoleLibrary path is missing"], resource_path)
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return _failure(["SemanticRoleLibrary resource is missing: %s" % resource_path], resource_path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return _failure(["SemanticRoleLibrary resource must be a JSON object: %s" % resource_path], resource_path)
	var errors := configure(parsed as Dictionary, resource_path)
	if not errors.is_empty():
		return _failure(errors, resource_path)
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"library": self,
		"library_data": to_dictionary(),
		"library_id": library_id(),
		"library_path": library_path(),
		"library_content_hash": library_content_hash(),
	}


func _validate_role_definition(role_type: String, definition: Dictionary, definition_ids: Dictionary, errors: Array[String]) -> void:
	var path := "SemanticRoleLibrary.role_definitions.%s" % role_type
	if not _is_system_token(role_type):
		errors.append("SemanticRoleLibrary role_type must be a lowercase system token: %s" % role_type)
		return
	_validate_known_keys(definition, ROLE_DEFINITION_KEYS, path, errors)
	var definition_id := str(definition.get("role_definition_id", ""))
	if not _is_namespaced_id(definition_id, "role_definition") or not definition_id.ends_with(".%s" % role_type):
		errors.append("%s.role_definition_id is invalid: %s" % [path, definition_id])
	elif definition_ids.has(definition_id):
		errors.append("SemanticRoleLibrary contains duplicate role_definition_id: %s" % definition_id)
	definition_ids[definition_id] = true
	_validate_semantic_array(definition.get("satisfies"), "%s.satisfies" % path, "satisfies", true, errors)
	_validate_semantic_array(definition.get("properties"), "%s.properties" % path, "properties", false, errors)
	_validate_semantic_array(definition.get("affinity"), "%s.affinity" % path, "affinity", false, errors)
	var category := str(definition.get("category", ""))
	if not RegionSemanticVocabularyScript.is_role_category(category):
		errors.append("%s.category is not in the role category vocabulary: %s" % [path, category])
	_validate_semantic_array(definition.get("requires_traits"), "%s.requires_traits" % path, "traits", false, errors)
	_validate_semantic_array(definition.get("excludes_traits"), "%s.excludes_traits" % path, "traits", false, errors)
	_validate_semantic_array(definition.get("requires_facts"), "%s.requires_facts" % path, "facts", false, errors)
	_validate_semantic_array(definition.get("excludes_facts"), "%s.excludes_facts" % path, "facts", false, errors)
	_validate_disjoint_arrays(definition, "requires_traits", "excludes_traits", path, errors)
	_validate_disjoint_arrays(definition, "requires_facts", "excludes_facts", path, errors)
	_validate_context_conditions(definition.get("requires_context"), "%s.requires_context" % path, errors)
	_validate_context_conditions(definition.get("excludes_context"), "%s.excludes_context" % path, errors)
	_validate_context_overlap(definition, path, errors)
	_validate_semantic_array(definition.get("allowed_sources"), "%s.allowed_sources" % path, "sources", true, errors)
	if not (definition.get("allow_multiple", null) is bool):
		errors.append("%s.allow_multiple must be a boolean" % path)


func _validate_semantic_array(value: Variant, path: String, dimension: String, require_non_empty: bool, errors: Array[String]) -> void:
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
		var supported := false
		match dimension:
			"satisfies":
				supported = RegionSemanticVocabularyScript.is_need_id(token)
			"properties":
				supported = RegionSemanticVocabularyScript.is_role_property(token)
			"affinity":
				supported = RegionSemanticVocabularyScript.is_role_affinity(token)
			"traits":
				supported = RegionSemanticVocabularyScript.is_trait(token)
			"facts":
				supported = RegionSemanticVocabularyScript.is_fact(token)
			"sources":
				supported = ALLOWED_SOURCES.has(token)
		if not supported:
			errors.append("%s contains a token outside the %s vocabulary: %s" % [path, dimension, token])


func _validate_context_conditions(value: Variant, path: String, errors: Array[String]) -> void:
	if not (value is Dictionary):
		errors.append("%s must be an object" % path)
		return
	var conditions: Dictionary = value as Dictionary
	for key_value in conditions.keys():
		var context_key := str(key_value)
		if not RegionSemanticVocabularyScript.is_coarse_context_key(context_key):
			errors.append("%s contains unsupported context key: %s" % [path, context_key])
			continue
		if not (conditions.get(key_value, null) is Array):
			errors.append("%s.%s must be an array" % [path, context_key])
			continue
		var values: Array = conditions.get(key_value, []) as Array
		if values.is_empty():
			errors.append("%s.%s must not be empty" % [path, context_key])
		var seen: Dictionary = {}
		for item in values:
			var context_value := str(item)
			if not RegionSemanticVocabularyScript.is_coarse_context_value(context_key, context_value):
				errors.append("%s.%s contains unsupported context value: %s" % [path, context_key, context_value])
			if seen.has(context_value):
				errors.append("%s.%s contains duplicate context value: %s" % [path, context_key, context_value])
			seen[context_value] = true


func _validate_disjoint_arrays(definition: Dictionary, required_key: String, excluded_key: String, path: String, errors: Array[String]) -> void:
	if not (definition.get(required_key, null) is Array) or not (definition.get(excluded_key, null) is Array):
		return
	for token in _string_array(definition.get(required_key, []) as Array):
		if (definition.get(excluded_key, []) as Array).has(token):
			errors.append("%s.%s and %s overlap at: %s" % [path, required_key, excluded_key, token])


func _validate_context_overlap(definition: Dictionary, path: String, errors: Array[String]) -> void:
	if not (definition.get("requires_context", null) is Dictionary) or not (definition.get("excludes_context", null) is Dictionary):
		return
	var required: Dictionary = definition.get("requires_context", {}) as Dictionary
	var excluded: Dictionary = definition.get("excludes_context", {}) as Dictionary
	for key_value in required.keys():
		var context_key := str(key_value)
		if not excluded.has(context_key):
			continue
		for context_value in RegionSemanticVocabularyScript.context_values(required.get(key_value)):
			if RegionSemanticVocabularyScript.context_values(excluded.get(context_key)).has(context_value):
				errors.append("%s requires_context and excludes_context overlap at %s=%s" % [path, context_key, context_value])


static func _required_context_matches(requirements: Dictionary, context: Dictionary) -> bool:
	for key_value in requirements.keys():
		var context_key := str(key_value)
		if not context.has(context_key):
			return false
		if not _arrays_intersect(
			RegionSemanticVocabularyScript.context_values(requirements.get(key_value)),
			RegionSemanticVocabularyScript.context_values(context.get(context_key))
		):
			return false
	return true


static func _excluded_context_matches(exclusions: Dictionary, context: Dictionary) -> bool:
	for key_value in exclusions.keys():
		var context_key := str(key_value)
		if not context.has(context_key):
			continue
		if _arrays_intersect(
			RegionSemanticVocabularyScript.context_values(exclusions.get(key_value)),
			RegionSemanticVocabularyScript.context_values(context.get(context_key))
		):
			return true
	return false


static func _contains_all(values: Array[String], required: Array[String]) -> bool:
	for token in required:
		if not values.has(token):
			return false
	return true


static func _contains_any(values: Array[String], excluded: Array[String]) -> bool:
	for token in excluded:
		if values.has(token):
			return true
	return false


static func _arrays_intersect(first: Array[String], second: Array[String]) -> bool:
	for token in first:
		if second.has(token):
			return true
	return false


static func _validate_known_keys(data: Dictionary, allowed: Dictionary, path: String, errors: Array[String]) -> void:
	for key_value in data.keys():
		var key := str(key_value)
		if not allowed.has(key):
			errors.append("%s contains unsupported field: %s" % [path, key])


static func _failure(errors: Array[String], resource_path: String) -> Dictionary:
	return {
		"success": false,
		"errors": errors.duplicate(),
		"warnings": [],
		"library_path": resource_path,
	}


static func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


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
