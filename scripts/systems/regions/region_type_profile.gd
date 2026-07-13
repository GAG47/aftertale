class_name RegionTypeProfile
extends RefCounted

const RegionSemanticVocabularyScript := preload("res://scripts/systems/regions/region_semantic_vocabulary.gd")

const SCHEMA_VERSION := 4
const PROFILE_PATH_PATTERN := "res://data/regions/region_type_profiles/%s.json"
const PROFILE_KEYS := {
	"schema_version": true,
	"region_type": true,
	"required_needs": true,
	"optional_needs": true,
	"scale_optional_counts": true,
	"allowed_categories": true,
	"allowed_satisfies_domains": true,
	"required_properties": true,
	"allowed_properties": true,
	"excluded_form_ids": true,
	"context_semantic_modifiers": true,
}
const FORBIDDEN_ROLE_POOL_KEYS := [
	"role_definitions",
	"role_weights",
	"allowed_role_types",
	"role_weight_overrides",
	"required_role_types",
	"optional_role_types",
	"context_weight_modifiers",
	"excluded_role_types",
]

var source_data: Dictionary = {}


func configure(data: Dictionary) -> Array[String]:
	source_data = data.duplicate(true)
	return validate()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if source_data.is_empty():
		errors.append("RegionTypeProfile is empty")
		return errors
	_validate_known_keys(errors)
	if not source_data.has("schema_version"):
		errors.append("RegionTypeProfile.schema_version is missing")
	elif int(source_data.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("RegionTypeProfile.schema_version is unsupported: %s" % str(source_data.get("schema_version")))
	var type := region_type()
	if type.is_empty():
		errors.append("RegionTypeProfile.region_type is missing")
	elif not _is_system_token(type) or not type.ends_with("_region"):
		errors.append("RegionTypeProfile.region_type must be a lowercase *_region token: %s" % type)
	errors.append_array(_validate_need_array("required_needs", true))
	errors.append_array(_validate_need_array("optional_needs", false))
	_validate_semantic_scope(errors)
	if not (source_data.get("scale_optional_counts", null) is Dictionary):
		errors.append("RegionTypeProfile.scale_optional_counts must be an object")
	else:
		_validate_scale_optional_counts(errors)
	if not (source_data.get("context_semantic_modifiers", null) is Dictionary):
		errors.append("RegionTypeProfile.context_semantic_modifiers must be an object")
	else:
		_validate_context_semantic_modifiers(errors)
	if source_data.has("external_intent_role_type"):
		errors.append("RegionTypeProfile.external_intent_role_type is not supported; Location nodes are the generation unit")
	return errors


func to_dictionary() -> Dictionary:
	return source_data.duplicate(true)


func region_type() -> String:
	return str(source_data.get("region_type", ""))


func required_needs() -> Array[String]:
	return _string_array(source_data.get("required_needs", []) as Array)


func optional_needs() -> Array[String]:
	return _string_array(source_data.get("optional_needs", []) as Array)


func allowed_categories() -> Array[String]:
	return _string_array(source_data.get("allowed_categories", []) as Array)


func allowed_satisfies_domains() -> Array[String]:
	return _string_array(source_data.get("allowed_satisfies_domains", []) as Array)


func required_properties() -> Array[String]:
	return _string_array(source_data.get("required_properties", []) as Array)


func allowed_properties() -> Array[String]:
	return _string_array(source_data.get("allowed_properties", []) as Array)


func excluded_form_ids() -> Array[String]:
	return _string_array(source_data.get("excluded_form_ids", []) as Array)


func allows_form_definition(form_id: String, definition: Dictionary) -> bool:
	if form_id.is_empty() or definition.is_empty() or excluded_form_ids().has(form_id):
		return false
	if not allowed_categories().has(str(definition.get("category", ""))):
		return false
	var domains := allowed_satisfies_domains()
	var satisfies := _string_array(definition.get("satisfies", []) as Array)
	if satisfies.is_empty():
		return false
	for need_id in satisfies:
		if not domains.has(RegionSemanticVocabularyScript.need_domain(need_id)):
			return false
	var properties := _string_array(definition.get("properties", []) as Array)
	for property in properties:
		if not allowed_properties().has(property):
			return false
	for required_property in required_properties():
		if not properties.has(required_property):
			return false
	return true


func optional_count_range(scale: String) -> Array[int]:
	var counts: Dictionary = source_data.get("scale_optional_counts", {}) as Dictionary
	if not counts.has(scale) or not (counts.get(scale, null) is Array):
		return []
	var row: Array = counts.get(scale, []) as Array
	if row.size() != 2:
		return []
	return [int(row[0]), int(row[1])]


func context_weight_multiplier(coarse_context: Dictionary, role_definition: Dictionary) -> float:
	var multiplier := 1.0
	var modifiers: Dictionary = source_data.get("context_semantic_modifiers", {}) as Dictionary
	var satisfies := _string_array(role_definition.get("satisfies", []) as Array)
	var properties := _string_array(role_definition.get("properties", []) as Array)
	var affinity := _string_array(role_definition.get("affinity", []) as Array)
	var category := str(role_definition.get("category", ""))
	for context_key_value in modifiers.keys():
		var context_key := str(context_key_value)
		if not coarse_context.has(context_key):
			continue
		var by_value: Dictionary = modifiers.get(context_key, {}) as Dictionary
		for context_value in RegionSemanticVocabularyScript.context_values(coarse_context.get(context_key)):
			if not (by_value.get(context_value, null) is Dictionary):
				continue
			var semantic_modifiers: Dictionary = by_value.get(context_value, {}) as Dictionary
			multiplier *= _matched_modifier_multiplier(semantic_modifiers.get("satisfies", {}), satisfies)
			multiplier *= _matched_modifier_multiplier(semantic_modifiers.get("properties", {}), properties)
			multiplier *= _matched_modifier_multiplier(semantic_modifiers.get("affinity", {}), affinity)
			multiplier *= _category_modifier_multiplier(semantic_modifiers.get("category", {}), category)
	return multiplier


func load_profile_result(requested_region_type: String) -> Dictionary:
	if requested_region_type.is_empty():
		return _failure(["region_type is missing"])
	var resource_path := PROFILE_PATH_PATTERN % requested_region_type
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return _failure(["RegionTypeProfile resource is missing: %s" % resource_path])
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return _failure(["RegionTypeProfile resource must be a JSON object: %s" % resource_path])
	var errors := configure(parsed as Dictionary)
	if region_type() != requested_region_type:
		errors.append("RegionTypeProfile.region_type does not match requested type: %s != %s" % [region_type(), requested_region_type])
	if not errors.is_empty():
		return _failure(errors, resource_path)
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"profile": self,
		"profile_data": to_dictionary(),
		"profile_path": resource_path,
	}


func _validate_known_keys(errors: Array[String]) -> void:
	for key_value in source_data.keys():
		var key := str(key_value)
		if FORBIDDEN_ROLE_POOL_KEYS.has(key):
			errors.append("RegionTypeProfile.%s is not supported in schema v%d; use typed semantic scope or modifiers" % [key, SCHEMA_VERSION])
		elif not PROFILE_KEYS.has(key):
			errors.append("RegionTypeProfile contains unsupported field: %s" % key)


func _validate_need_array(key: String, require_non_empty: bool) -> Array[String]:
	var errors: Array[String] = []
	if not (source_data.get(key, null) is Array):
		errors.append("RegionTypeProfile.%s must be an array" % key)
		return errors
	var values := _string_array(source_data.get(key, []) as Array)
	if require_non_empty and values.is_empty():
		errors.append("RegionTypeProfile.%s must not be empty" % key)
	var seen: Dictionary = {}
	for need_id in values:
		if not RegionSemanticVocabularyScript.is_need_id(need_id):
			errors.append("RegionTypeProfile.%s contains unsupported need_id: %s" % [key, need_id])
		if seen.has(need_id):
			errors.append("RegionTypeProfile.%s contains duplicate need_id: %s" % [key, need_id])
		seen[need_id] = true
	return errors


func _validate_semantic_scope(errors: Array[String]) -> void:
	_validate_scope_array("allowed_categories", "category", true, errors)
	_validate_scope_array("allowed_satisfies_domains", "satisfies_domain", true, errors)
	_validate_scope_array("required_properties", "property", false, errors)
	_validate_scope_array("allowed_properties", "property", true, errors)
	_validate_scope_array("excluded_form_ids", "form_id", false, errors)
	if source_data.get("required_properties", null) is Array and source_data.get("allowed_properties", null) is Array:
		for property in required_properties():
			if not allowed_properties().has(property):
				errors.append("RegionTypeProfile.required_properties must be a subset of allowed_properties: %s" % property)


func _validate_scope_array(key: String, dimension: String, require_non_empty: bool, errors: Array[String]) -> void:
	if not (source_data.get(key, null) is Array):
		errors.append("RegionTypeProfile.%s must be an array" % key)
		return
	var values := _string_array(source_data.get(key, []) as Array)
	if require_non_empty and values.is_empty():
		errors.append("RegionTypeProfile.%s must not be empty" % key)
	var seen: Dictionary = {}
	for token in values:
		if seen.has(token):
			errors.append("RegionTypeProfile.%s contains duplicate token: %s" % [key, token])
		seen[token] = true
		var valid := false
		match dimension:
			"category":
				valid = RegionSemanticVocabularyScript.is_role_category(token)
			"satisfies_domain":
				valid = RegionSemanticVocabularyScript.is_need_domain(token)
			"property":
				valid = RegionSemanticVocabularyScript.is_role_property(token)
			"form_id":
				valid = _is_system_token(token)
		if not valid:
			errors.append("RegionTypeProfile.%s contains a token outside the %s vocabulary: %s" % [key, dimension, token])


func _validate_scale_optional_counts(errors: Array[String]) -> void:
	var counts: Dictionary = source_data.get("scale_optional_counts", {}) as Dictionary
	var allowed_scales: Array = RegionSemanticVocabularyScript.ALLOWED_COARSE_CONTEXT.get("scale", []) as Array
	for scale in allowed_scales:
		if not counts.has(scale):
			errors.append("RegionTypeProfile.scale_optional_counts is missing scale: %s" % str(scale))
	for scale_value in counts.keys():
		var scale := str(scale_value)
		if not allowed_scales.has(scale):
			errors.append("RegionTypeProfile.scale_optional_counts contains unsupported scale: %s" % scale)
			continue
		if not (counts.get(scale_value, null) is Array):
			errors.append("RegionTypeProfile.scale_optional_counts.%s must be an array" % scale)
			continue
		var row: Array = counts.get(scale_value, []) as Array
		if row.size() != 2:
			errors.append("RegionTypeProfile.scale_optional_counts row must contain exactly min and max: %s" % scale)
			continue
		var min_count := int(row[0])
		var max_count := int(row[1])
		if min_count < 0 or max_count < min_count:
			errors.append("RegionTypeProfile.scale_optional_counts row is invalid: %s" % scale)


func _validate_context_semantic_modifiers(errors: Array[String]) -> void:
	var modifiers: Dictionary = source_data.get("context_semantic_modifiers", {}) as Dictionary
	for context_key_value in modifiers.keys():
		var context_key := str(context_key_value)
		if not RegionSemanticVocabularyScript.is_coarse_context_key(context_key):
			errors.append("RegionTypeProfile.context_semantic_modifiers contains unsupported context key: %s" % context_key)
			continue
		if not (modifiers.get(context_key_value, null) is Dictionary):
			errors.append("RegionTypeProfile.context_semantic_modifiers.%s must be an object" % context_key)
			continue
		var by_value: Dictionary = modifiers.get(context_key_value, {}) as Dictionary
		for context_value_value in by_value.keys():
			var context_value := str(context_value_value)
			if not RegionSemanticVocabularyScript.is_coarse_context_value(context_key, context_value):
				errors.append("RegionTypeProfile.context_semantic_modifiers.%s contains unsupported context value: %s" % [context_key, context_value])
				continue
			if not (by_value.get(context_value_value, null) is Dictionary):
				errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s must be an object" % [context_key, context_value])
				continue
			_validate_context_semantic_modifier_row(
				context_key,
				context_value,
				by_value.get(context_value_value, {}) as Dictionary,
				errors
			)


func _validate_context_semantic_modifier_row(context_key: String, context_value: String, row: Dictionary, errors: Array[String]) -> void:
	for key_value in row.keys():
		var semantic_key := str(key_value)
		if not ["satisfies", "properties", "affinity", "category"].has(semantic_key):
			errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s contains unsupported semantic key: %s" % [context_key, context_value, semantic_key])
			continue
		if not (row.get(key_value, null) is Dictionary):
			errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s.%s must be an object" % [context_key, context_value, semantic_key])
			continue
		var weights: Dictionary = row.get(key_value, {}) as Dictionary
		for token_value in weights.keys():
			var token := str(token_value)
			var weight := float(weights.get(token_value, 0.0))
			if weight <= 0.0:
				errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s.%s.%s must be positive" % [context_key, context_value, semantic_key, token])
			var valid := false
			match semantic_key:
				"satisfies":
					valid = RegionSemanticVocabularyScript.is_need_id(token)
				"properties":
					valid = RegionSemanticVocabularyScript.is_role_property(token)
				"affinity":
					valid = RegionSemanticVocabularyScript.is_role_affinity(token)
				"category":
					valid = RegionSemanticVocabularyScript.is_role_category(token)
			if not valid:
				errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s.%s contains a token outside its vocabulary: %s" % [context_key, context_value, semantic_key, token])


static func _matched_modifier_multiplier(value: Variant, role_tokens: Array[String]) -> float:
	if not (value is Dictionary):
		return 1.0
	var multiplier := 1.0
	var weights: Dictionary = value as Dictionary
	for token_value in weights.keys():
		var token := str(token_value)
		if role_tokens.has(token):
			multiplier *= float(weights.get(token_value, 1.0))
	return multiplier


static func _category_modifier_multiplier(value: Variant, category: String) -> float:
	if not (value is Dictionary):
		return 1.0
	var weights: Dictionary = value as Dictionary
	if category.is_empty() or not weights.has(category):
		return 1.0
	return float(weights.get(category, 1.0))


static func _failure(errors: Array[String], resource_path: String = "") -> Dictionary:
	return {
		"success": false,
		"errors": errors.duplicate(),
		"warnings": [],
		"profile_path": resource_path,
	}


static func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


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
