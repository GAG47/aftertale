class_name SemanticRoleLibrary
extends RefCounted

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const RegionSemanticVocabularyScript := preload("res://scripts/systems/regions/region_semantic_vocabulary.gd")

const SCHEMA_VERSION := 2
const DEFAULT_LIBRARY_PATH := "res://data/regions/semantic_role_libraries/core.json"
const TOP_LEVEL_KEYS := {
	"schema_version": true,
	"library_id": true,
	"library_type": true,
	"archetype_definitions": true,
	"form_definitions": true,
}
const ARCHETYPE_KEYS := {
	"archetype_definition_id": true,
	"satisfies": true,
	"properties": true,
	"gameplay_affordances": true,
	"narrative_affordances": true,
	"category": true,
	"allowed_sources": true,
	"allow_multiple": true,
}
const FORM_KEYS := {
	"form_definition_id": true,
	"archetype_id": true,
	"properties": true,
	"affinity": true,
	"gameplay_affordances": true,
	"narrative_affordances": true,
	"requires_traits": true,
	"excludes_traits": true,
	"requires_facts": true,
	"excludes_facts": true,
	"requires_context": true,
	"excludes_context": true,
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
	if source_data.has("role_definitions"):
		errors.append("SemanticRoleLibrary.role_definitions is not supported in schema v2; use archetype_definitions and form_definitions")
	if int(source_data.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("SemanticRoleLibrary.schema_version is unsupported: %s" % str(source_data.get("schema_version", "")))
	if str(source_data.get("library_type", "")) != "semantic_role_library":
		errors.append("SemanticRoleLibrary.library_type must be semantic_role_library")
	var id := library_id()
	if not _is_namespaced_id(id, "semantic_role_library"):
		errors.append("SemanticRoleLibrary.library_id is invalid: %s" % id)
	if not (source_data.get("archetype_definitions", null) is Dictionary):
		errors.append("SemanticRoleLibrary.archetype_definitions must be an object")
		return errors
	if not (source_data.get("form_definitions", null) is Dictionary):
		errors.append("SemanticRoleLibrary.form_definitions must be an object")
		return errors
	var archetypes: Dictionary = source_data.get("archetype_definitions", {}) as Dictionary
	var forms: Dictionary = source_data.get("form_definitions", {}) as Dictionary
	if archetypes.is_empty():
		errors.append("SemanticRoleLibrary.archetype_definitions must not be empty")
	if forms.is_empty():
		errors.append("SemanticRoleLibrary.form_definitions must not be empty")
	var definition_ids: Dictionary = {}
	for archetype_value in archetypes.keys():
		var archetype_id := str(archetype_value)
		if not (archetypes.get(archetype_value, null) is Dictionary):
			errors.append("SemanticRoleLibrary archetype definition must be an object: %s" % archetype_id)
			continue
		_validate_archetype(archetype_id, archetypes.get(archetype_value, {}) as Dictionary, definition_ids, errors)
	for form_value in forms.keys():
		var form_id := str(form_value)
		if not (forms.get(form_value, null) is Dictionary):
			errors.append("SemanticRoleLibrary form definition must be an object: %s" % form_id)
			continue
		_validate_form(form_id, forms.get(form_value, {}) as Dictionary, archetypes, definition_ids, errors)
	for archetype_id in archetype_ids():
		if forms_for_archetype(archetype_id).is_empty():
			errors.append("SemanticRoleLibrary archetype has no concrete form: %s" % archetype_id)
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


func archetype_ids() -> Array[String]:
	return _sorted_dictionary_keys(source_data.get("archetype_definitions", {}) as Dictionary)


func form_ids() -> Array[String]:
	return _sorted_dictionary_keys(source_data.get("form_definitions", {}) as Dictionary)


func archetype_definition(archetype_id: String) -> Dictionary:
	var definitions: Dictionary = source_data.get("archetype_definitions", {}) as Dictionary
	if not (definitions.get(archetype_id, null) is Dictionary):
		return {}
	return (definitions.get(archetype_id, {}) as Dictionary).duplicate(true)


func form_definition(form_id: String) -> Dictionary:
	var definitions: Dictionary = source_data.get("form_definitions", {}) as Dictionary
	if not (definitions.get(form_id, null) is Dictionary):
		return {}
	return (definitions.get(form_id, {}) as Dictionary).duplicate(true)


func forms_for_archetype(archetype_id: String) -> Array[String]:
	var result: Array[String] = []
	for form_id in form_ids():
		if form_archetype_id(form_id) == archetype_id:
			result.append(form_id)
	return result


func form_archetype_id(form_id: String) -> String:
	return str(form_definition(form_id).get("archetype_id", ""))


func composed_definition(form_id: String) -> Dictionary:
	var form := form_definition(form_id)
	var archetype_id := str(form.get("archetype_id", ""))
	var archetype := archetype_definition(archetype_id)
	if form.is_empty() or archetype.is_empty():
		return {}
	return {
		"archetype_id": archetype_id,
		"form_id": form_id,
		"satisfies": _unique_strings(_string_array(archetype.get("satisfies", []) as Array)),
		"properties": _unique_strings(
			_string_array(archetype.get("properties", []) as Array)
			+ _string_array(form.get("properties", []) as Array)
		),
		"affinity": _unique_strings(_string_array(form.get("affinity", []) as Array)),
		"gameplay_affordances": _unique_strings(
			_string_array(archetype.get("gameplay_affordances", []) as Array)
			+ _string_array(form.get("gameplay_affordances", []) as Array)
		),
		"narrative_affordances": _unique_strings(
			_string_array(archetype.get("narrative_affordances", []) as Array)
			+ _string_array(form.get("narrative_affordances", []) as Array)
		),
		"category": str(archetype.get("category", "")),
	}


func archetype_definition_id(archetype_id: String) -> String:
	return str(archetype_definition(archetype_id).get("archetype_definition_id", ""))


func archetype_definition_hash(archetype_id: String) -> String:
	var definition := archetype_definition(archetype_id)
	if definition.is_empty():
		return ""
	return CanonicalDataSerializerScript.hash_value({
		"archetype_id": archetype_id,
		"definition": definition,
	})


func form_definition_id(form_id: String) -> String:
	return str(form_definition(form_id).get("form_definition_id", ""))


func form_definition_hash(form_id: String) -> String:
	var definition := form_definition(form_id)
	if definition.is_empty():
		return ""
	return CanonicalDataSerializerScript.hash_value({
		"form_id": form_id,
		"definition": definition,
	})


func form_satisfies(form_id: String) -> Array[String]:
	return _string_array(composed_definition(form_id).get("satisfies", []) as Array)


func form_properties(form_id: String) -> Array[String]:
	return _string_array(composed_definition(form_id).get("properties", []) as Array)


func form_affinity(form_id: String) -> Array[String]:
	return _string_array(composed_definition(form_id).get("affinity", []) as Array)


func form_gameplay_affordances(form_id: String) -> Array[String]:
	return _string_array(composed_definition(form_id).get("gameplay_affordances", []) as Array)


func form_narrative_affordances(form_id: String) -> Array[String]:
	return _string_array(composed_definition(form_id).get("narrative_affordances", []) as Array)


func form_category(form_id: String) -> String:
	return str(composed_definition(form_id).get("category", ""))


func allows_source(form_id: String, source: String) -> bool:
	var archetype := archetype_definition(form_archetype_id(form_id))
	return _string_array(archetype.get("allowed_sources", []) as Array).has(source)


func allows_multiple(form_id: String) -> bool:
	return bool(archetype_definition(form_archetype_id(form_id)).get("allow_multiple", false))


func conditions_match(form_id: String, region_data: Dictionary) -> bool:
	var definition := form_definition(form_id)
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


func _validate_archetype(archetype_id: String, definition: Dictionary, definition_ids: Dictionary, errors: Array[String]) -> void:
	var path := "SemanticRoleLibrary.archetype_definitions.%s" % archetype_id
	if not _is_system_token(archetype_id):
		errors.append("SemanticRoleLibrary archetype_id must be a lowercase system token: %s" % archetype_id)
		return
	_validate_known_keys(definition, ARCHETYPE_KEYS, path, errors)
	var definition_id := str(definition.get("archetype_definition_id", ""))
	if not _is_namespaced_id(definition_id, "location_archetype") or not definition_id.ends_with(".%s" % archetype_id):
		errors.append("%s.archetype_definition_id is invalid: %s" % [path, definition_id])
	elif definition_ids.has(definition_id):
		errors.append("SemanticRoleLibrary contains duplicate definition id: %s" % definition_id)
	definition_ids[definition_id] = true
	_validate_semantic_array(definition.get("satisfies"), "%s.satisfies" % path, "needs", true, errors)
	_validate_semantic_array(definition.get("properties"), "%s.properties" % path, "properties", false, errors)
	_validate_semantic_array(definition.get("gameplay_affordances"), "%s.gameplay_affordances" % path, "gameplay", true, errors)
	_validate_semantic_array(definition.get("narrative_affordances"), "%s.narrative_affordances" % path, "narrative", false, errors)
	var category := str(definition.get("category", ""))
	if not RegionSemanticVocabularyScript.is_role_category(category):
		errors.append("%s.category is not in the role category vocabulary: %s" % [path, category])
	_validate_semantic_array(definition.get("allowed_sources"), "%s.allowed_sources" % path, "sources", true, errors)
	if not (definition.get("allow_multiple", null) is bool):
		errors.append("%s.allow_multiple must be a boolean" % path)


func _validate_form(form_id: String, definition: Dictionary, archetypes: Dictionary, definition_ids: Dictionary, errors: Array[String]) -> void:
	var path := "SemanticRoleLibrary.form_definitions.%s" % form_id
	if not _is_system_token(form_id):
		errors.append("SemanticRoleLibrary form_id must be a lowercase system token: %s" % form_id)
		return
	_validate_known_keys(definition, FORM_KEYS, path, errors)
	if definition.has("satisfies"):
		errors.append("%s must not declare satisfies; planning capabilities belong to its archetype" % path)
	var definition_id := str(definition.get("form_definition_id", ""))
	if not _is_namespaced_id(definition_id, "location_form") or not definition_id.ends_with(".%s" % form_id):
		errors.append("%s.form_definition_id is invalid: %s" % [path, definition_id])
	elif definition_ids.has(definition_id):
		errors.append("SemanticRoleLibrary contains duplicate definition id: %s" % definition_id)
	definition_ids[definition_id] = true
	var archetype_id := str(definition.get("archetype_id", ""))
	if not archetypes.has(archetype_id):
		errors.append("%s.archetype_id references an unknown archetype: %s" % [path, archetype_id])
	_validate_semantic_array(definition.get("properties"), "%s.properties" % path, "properties", false, errors)
	_validate_semantic_array(definition.get("affinity"), "%s.affinity" % path, "affinity", false, errors)
	_validate_semantic_array(definition.get("gameplay_affordances"), "%s.gameplay_affordances" % path, "gameplay", false, errors)
	_validate_semantic_array(definition.get("narrative_affordances"), "%s.narrative_affordances" % path, "narrative", false, errors)
	_validate_semantic_array(definition.get("requires_traits"), "%s.requires_traits" % path, "traits", false, errors)
	_validate_semantic_array(definition.get("excludes_traits"), "%s.excludes_traits" % path, "traits", false, errors)
	_validate_semantic_array(definition.get("requires_facts"), "%s.requires_facts" % path, "facts", false, errors)
	_validate_semantic_array(definition.get("excludes_facts"), "%s.excludes_facts" % path, "facts", false, errors)
	_validate_disjoint_arrays(definition, "requires_traits", "excludes_traits", path, errors)
	_validate_disjoint_arrays(definition, "requires_facts", "excludes_facts", path, errors)
	_validate_context_conditions(definition.get("requires_context"), "%s.requires_context" % path, errors)
	_validate_context_conditions(definition.get("excludes_context"), "%s.excludes_context" % path, errors)
	_validate_context_overlap(definition, path, errors)


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
			"needs":
				supported = RegionSemanticVocabularyScript.is_need_id(token)
			"properties":
				supported = RegionSemanticVocabularyScript.is_role_property(token)
			"affinity":
				supported = RegionSemanticVocabularyScript.is_role_affinity(token)
			"gameplay":
				supported = RegionSemanticVocabularyScript.is_gameplay_affordance(token)
			"narrative":
				supported = RegionSemanticVocabularyScript.is_narrative_affordance(token)
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
		var key := str(key_value)
		if not RegionSemanticVocabularyScript.is_coarse_context_key(key):
			errors.append("%s contains unsupported context key: %s" % [path, key])
			continue
		if not (conditions.get(key_value, null) is Array):
			errors.append("%s.%s must be an array" % [path, key])
			continue
		var seen: Dictionary = {}
		var values: Array = conditions.get(key_value, []) as Array
		if values.is_empty():
			errors.append("%s.%s must not be empty" % [path, key])
		for item in values:
			var token := str(item)
			if seen.has(token):
				errors.append("%s.%s contains duplicate value: %s" % [path, key, token])
			seen[token] = true
			if not RegionSemanticVocabularyScript.is_coarse_context_value(key, token):
				errors.append("%s.%s contains unsupported value: %s" % [path, key, token])


func _validate_context_overlap(definition: Dictionary, path: String, errors: Array[String]) -> void:
	var required: Dictionary = definition.get("requires_context", {}) as Dictionary
	var excluded: Dictionary = definition.get("excludes_context", {}) as Dictionary
	for key_value in required.keys():
		var key := str(key_value)
		if not excluded.has(key):
			continue
		for value in (required.get(key, []) as Array):
			if (excluded.get(key, []) as Array).has(value):
				errors.append("%s context value is both required and excluded: %s=%s" % [path, key, str(value)])


func _validate_disjoint_arrays(definition: Dictionary, first_key: String, second_key: String, path: String, errors: Array[String]) -> void:
	var first := _string_array(definition.get(first_key, []) as Array)
	var second := _string_array(definition.get(second_key, []) as Array)
	for token in first:
		if second.has(token):
			errors.append("%s token is both %s and %s: %s" % [path, first_key, second_key, token])


func _required_context_matches(required: Dictionary, context: Dictionary) -> bool:
	for key_value in required.keys():
		var key := str(key_value)
		if not context.has(key):
			return false
		var actual := RegionSemanticVocabularyScript.context_values(context.get(key))
		var allowed := _string_array(required.get(key_value, []) as Array)
		if not _contains_any(actual, allowed):
			return false
	return true


func _excluded_context_matches(excluded: Dictionary, context: Dictionary) -> bool:
	for key_value in excluded.keys():
		var key := str(key_value)
		if not context.has(key):
			continue
		var actual := RegionSemanticVocabularyScript.context_values(context.get(key))
		var blocked := _string_array(excluded.get(key_value, []) as Array)
		if _contains_any(actual, blocked):
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


static func _sorted_dictionary_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in values.keys():
		result.append(str(value))
	result.sort()
	return result


static func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


static func _unique_strings(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for value in values:
		if value.is_empty() or seen.has(value):
			continue
		seen[value] = true
		result.append(value)
	result.sort()
	return result


static func _contains_all(values: Array[String], required: Array[String]) -> bool:
	for value in required:
		if not values.has(value):
			return false
	return true


static func _contains_any(values: Array[String], possible: Array[String]) -> bool:
	for value in possible:
		if values.has(value):
			return true
	return false


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
