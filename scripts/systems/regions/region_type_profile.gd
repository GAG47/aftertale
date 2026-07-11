class_name RegionTypeProfile
extends RefCounted

const RegionSemanticVocabularyScript := preload("res://scripts/systems/regions/region_semantic_vocabulary.gd")

const SCHEMA_VERSION := 2
const PROFILE_PATH_PATTERN := "res://data/regions/region_type_profiles/%s.json"

var source_data: Dictionary = {}


func configure(data: Dictionary) -> Array[String]:
	source_data = data.duplicate(true)
	return validate()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if source_data.is_empty():
		errors.append("RegionTypeProfile is empty")
		return errors
	if not source_data.has("schema_version"):
		errors.append("RegionTypeProfile.schema_version is missing")
	elif int(source_data.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("RegionTypeProfile.schema_version is unsupported: %s" % str(source_data.get("schema_version")))
	var region_type := str(source_data.get("region_type", ""))
	if region_type.is_empty():
		errors.append("RegionTypeProfile.region_type is missing")
	elif not _is_system_token(region_type) or not region_type.ends_with("_region"):
		errors.append("RegionTypeProfile.region_type must be a lowercase *_region token: %s" % region_type)
	errors.append_array(_validate_need_array("required_needs", true))
	errors.append_array(_validate_need_array("optional_needs", false))
	if not (source_data.get("role_definitions", null) is Dictionary):
		errors.append("RegionTypeProfile.role_definitions must be an object")
		return errors
	var role_definitions: Dictionary = source_data.get("role_definitions", {}) as Dictionary
	if role_definitions.is_empty():
		errors.append("RegionTypeProfile.role_definitions is empty")
	for role_type_value in role_definitions.keys():
		_validate_role_definition(str(role_type_value), role_definitions.get(role_type_value, {}) as Dictionary, errors)
	_validate_need_coverage(role_definitions, errors)
	if not (source_data.get("scale_optional_counts", null) is Dictionary):
		errors.append("RegionTypeProfile.scale_optional_counts must be an object")
	else:
		_validate_scale_optional_counts(errors)
	if source_data.has("external_intent_role_type"):
		errors.append("RegionTypeProfile.external_intent_role_type is not supported; Location nodes are the generation unit")
	if source_data.has("required_role_types"):
		errors.append("RegionTypeProfile.required_role_types is not supported in schema v%d; use required_needs" % SCHEMA_VERSION)
	if source_data.has("optional_role_types"):
		errors.append("RegionTypeProfile.optional_role_types is not supported in schema v%d; use optional_needs" % SCHEMA_VERSION)
	if not (source_data.get("role_weights", null) is Dictionary):
		errors.append("RegionTypeProfile.role_weights must be an object")
	else:
		_validate_role_weights(role_definitions, errors)
	if source_data.has("context_weight_modifiers"):
		errors.append("RegionTypeProfile.context_weight_modifiers is not supported in schema v%d; use context_semantic_modifiers" % SCHEMA_VERSION)
	if not (source_data.get("context_semantic_modifiers", null) is Dictionary):
		errors.append("RegionTypeProfile.context_semantic_modifiers must be an object")
	else:
		_validate_context_semantic_modifiers(role_definitions, errors)
	return errors


func to_dictionary() -> Dictionary:
	return source_data.duplicate(true)


func region_type() -> String:
	return str(source_data.get("region_type", ""))


func required_needs() -> Array[String]:
	return _string_array(source_data.get("required_needs", []) as Array)


func optional_needs() -> Array[String]:
	return _string_array(source_data.get("optional_needs", []) as Array)


func all_role_types() -> Array[String]:
	var result: Array[String] = []
	var definitions: Dictionary = source_data.get("role_definitions", {}) as Dictionary
	for role_type_value in definitions.keys():
		result.append(str(role_type_value))
	result.sort()
	return result


func role_types_for_source(source: String) -> Array[String]:
	var result: Array[String] = []
	for role_type in all_role_types():
		if allows_source(role_type, source):
			result.append(role_type)
	return result


func role_types_for_need(need_id: String, source: String) -> Array[String]:
	var result: Array[String] = []
	for role_type in all_role_types():
		if allows_source(role_type, source) and role_satisfies(role_type).has(need_id):
			result.append(role_type)
	return result


func role_definition(role_type: String) -> Dictionary:
	var definitions: Dictionary = source_data.get("role_definitions", {}) as Dictionary
	return (definitions.get(role_type, {}) as Dictionary).duplicate(true)


func role_tags(role_type: String) -> Array[String]:
	var definition := role_definition(role_type)
	return _string_array(definition.get("role_tags", []) as Array)


func role_satisfies(role_type: String) -> Array[String]:
	var definition := role_definition(role_type)
	return _string_array(definition.get("satisfies", []) as Array)


func allows_source(role_type: String, source: String) -> bool:
	var definition := role_definition(role_type)
	var sources := _string_array(definition.get("allowed_sources", []) as Array)
	return sources.has(source)


func allows_multiple(role_type: String) -> bool:
	var definition := role_definition(role_type)
	return bool(definition.get("allow_multiple", false))


func optional_count_range(scale: String) -> Array[int]:
	var counts: Dictionary = source_data.get("scale_optional_counts", {}) as Dictionary
	if not counts.has(scale):
		return []
	var row: Array = counts.get(scale, []) as Array
	if row.size() < 2:
		return []
	return [int(row[0]), int(row[1])]


func base_weight(role_type: String) -> float:
	var weights: Dictionary = source_data.get("role_weights", {}) as Dictionary
	return float(weights.get(role_type, -1.0))


func context_weight_multiplier(coarse_context: Dictionary, role_type: String) -> float:
	var multiplier := 1.0
	var modifiers: Dictionary = source_data.get("context_semantic_modifiers", {}) as Dictionary
	var role_definition_data := role_definition(role_type)
	var satisfies := _string_array(role_definition_data.get("satisfies", []) as Array)
	var properties := _string_array(role_definition_data.get("properties", []) as Array)
	var affinity := _string_array(role_definition_data.get("affinity", []) as Array)
	var category := str(role_definition_data.get("category", ""))
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


func load_profile_result(region_type: String) -> Dictionary:
	if region_type.is_empty():
		return _failure(["region_type is missing"])
	var resource_path := PROFILE_PATH_PATTERN % region_type
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return _failure(["RegionTypeProfile resource is missing: %s" % resource_path])
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return _failure(["RegionTypeProfile resource must be a JSON object: %s" % resource_path])
	var errors := configure(parsed as Dictionary)
	if str(self.region_type()) != region_type:
		errors.append("RegionTypeProfile.region_type does not match requested type: %s != %s" % [self.region_type(), region_type])
	if not errors.is_empty():
		return _failure(errors, resource_path)
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"profile": self,
		"profile_data": self.to_dictionary(),
		"profile_path": resource_path,
	}


static func _failure(errors: Array[String], resource_path: String = "") -> Dictionary:
	return {
		"success": false,
		"errors": errors.duplicate(),
		"warnings": [],
		"profile_path": resource_path,
	}


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


func _validate_role_definition(role_type: String, definition: Dictionary, errors: Array[String]) -> void:
	if not _is_system_token(role_type):
		errors.append("RegionTypeProfile role type must be a lowercase system token: %s" % role_type)
		return
	if definition.is_empty():
		errors.append("RegionTypeProfile role definition is empty: %s" % role_type)
		return
	if not (definition.get("satisfies", null) is Array):
		errors.append("RegionTypeProfile satisfies must be an array: %s" % role_type)
	else:
		for need_id in _string_array(definition.get("satisfies", []) as Array):
			if not RegionSemanticVocabularyScript.is_need_id(need_id):
				errors.append("RegionTypeProfile satisfies contains unsupported need_id for %s: %s" % [role_type, need_id])
	if not (definition.get("role_tags", null) is Array):
		errors.append("RegionTypeProfile role_tags must be an array: %s" % role_type)
	elif not _string_array_is_valid(definition.get("role_tags")):
		errors.append("RegionTypeProfile role_tags must contain lowercase system tokens: %s" % role_type)
	if not (definition.get("allowed_sources", null) is Array):
		errors.append("RegionTypeProfile allowed_sources must be an array: %s" % role_type)
	elif not _sources_are_valid(definition.get("allowed_sources")):
		errors.append("RegionTypeProfile allowed_sources contains an illegal value: %s" % role_type)
	if definition.has("properties") and not _string_array_is_valid(definition.get("properties")):
		errors.append("RegionTypeProfile properties must contain lowercase system tokens: %s" % role_type)
	if definition.has("affinity") and not _string_array_is_valid(definition.get("affinity")):
		errors.append("RegionTypeProfile affinity must contain lowercase system tokens: %s" % role_type)
	if definition.has("category") and not _is_system_token(str(definition.get("category", ""))):
		errors.append("RegionTypeProfile category must be a lowercase system token: %s" % role_type)
	if not definition.has("allow_multiple"):
		errors.append("RegionTypeProfile allow_multiple is missing: %s" % role_type)


func _validate_need_coverage(role_definitions: Dictionary, errors: Array[String]) -> void:
	for need_id in required_needs():
		if _role_types_matching_need(role_definitions, need_id, "required").is_empty():
			errors.append("RegionTypeProfile.required_needs has no required role candidate: %s" % need_id)
	for need_id in optional_needs():
		if _role_types_matching_need(role_definitions, need_id, "optional").is_empty():
			errors.append("RegionTypeProfile.optional_needs has no optional role candidate: %s" % need_id)


func _role_types_matching_need(role_definitions: Dictionary, need_id: String, source: String) -> Array[String]:
	var result: Array[String] = []
	for role_type_value in role_definitions.keys():
		var role_type := str(role_type_value)
		var definition: Dictionary = role_definitions.get(role_type_value, {}) as Dictionary
		var satisfies := _string_array(definition.get("satisfies", []) as Array)
		var sources := _string_array(definition.get("allowed_sources", []) as Array)
		if satisfies.has(need_id) and sources.has(source):
			result.append(role_type)
	return result


func _validate_scale_optional_counts(errors: Array[String]) -> void:
	var counts: Dictionary = source_data.get("scale_optional_counts", {}) as Dictionary
	for scale_value in counts.keys():
		var scale := str(scale_value)
		if not _is_system_token(scale):
			errors.append("RegionTypeProfile scale key must be a lowercase system token: %s" % scale)
			continue
		var row: Array = counts.get(scale, []) as Array
		if row.size() < 2:
			errors.append("RegionTypeProfile scale_optional_counts row must contain min and max: %s" % scale)
			continue
		var min_count := int(row[0])
		var max_count := int(row[1])
		if min_count < 0 or max_count < min_count:
			errors.append("RegionTypeProfile scale_optional_counts row is invalid: %s" % scale)


func _validate_role_weights(role_definitions: Dictionary, errors: Array[String]) -> void:
	var weights: Dictionary = source_data.get("role_weights", {}) as Dictionary
	for role_type in _role_types_for_source(role_definitions, "optional"):
		if not weights.has(role_type):
			errors.append("RegionTypeProfile.role_weights missing optional role type: %s" % role_type)
		elif float(weights.get(role_type, 0.0)) <= 0.0:
			errors.append("RegionTypeProfile.role_weights must be positive for optional role type: %s" % role_type)
	for key_value in weights.keys():
		var role_type := str(key_value)
		if not role_definitions.has(role_type):
			errors.append("RegionTypeProfile.role_weights references undefined role type: %s" % role_type)


func _validate_context_semantic_modifiers(role_definitions: Dictionary, errors: Array[String]) -> void:
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
			var row: Dictionary = by_value.get(context_value_value, {}) as Dictionary
			_validate_context_semantic_modifier_row(context_key, context_value, row, role_definitions, errors)


func _validate_context_semantic_modifier_row(context_key: String, context_value: String, row: Dictionary, role_definitions: Dictionary, errors: Array[String]) -> void:
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
			var weight := float(weights.get(token_value, -1.0))
			if weight < 0.0:
				errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s.%s.%s must be non-negative" % [context_key, context_value, semantic_key, token])
			match semantic_key:
				"satisfies":
					if not RegionSemanticVocabularyScript.is_need_id(token):
						errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s.satisfies has unsupported need_id: %s" % [context_key, context_value, token])
				"properties":
					if not _role_semantic_token_exists(role_definitions, "properties", token):
						errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s.properties references unused semantic token: %s" % [context_key, context_value, token])
				"affinity":
					if not _role_semantic_token_exists(role_definitions, "affinity", token):
						errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s.affinity references unused semantic token: %s" % [context_key, context_value, token])
				"category":
					if not _role_category_exists(role_definitions, token):
						errors.append("RegionTypeProfile.context_semantic_modifiers.%s.%s.category references unused semantic token: %s" % [context_key, context_value, token])


func _role_semantic_token_exists(role_definitions: Dictionary, field_name: String, token: String) -> bool:
	for role_type_value in role_definitions.keys():
		var definition: Dictionary = role_definitions.get(role_type_value, {}) as Dictionary
		if _string_array(definition.get(field_name, []) as Array).has(token):
			return true
	return false


func _role_category_exists(role_definitions: Dictionary, token: String) -> bool:
	for role_type_value in role_definitions.keys():
		var definition: Dictionary = role_definitions.get(role_type_value, {}) as Dictionary
		if str(definition.get("category", "")) == token:
			return true
	return false


func _role_types_for_source(role_definitions: Dictionary, source: String) -> Array[String]:
	var result: Array[String] = []
	for role_type_value in role_definitions.keys():
		var definition: Dictionary = role_definitions.get(role_type_value, {}) as Dictionary
		if _string_array(definition.get("allowed_sources", []) as Array).has(source):
			result.append(str(role_type_value))
	return result


static func _matched_modifier_multiplier(value: Variant, role_tokens: Array[String]) -> float:
	if not (value is Dictionary):
		return 1.0
	var multiplier := 1.0
	var weights: Dictionary = value as Dictionary
	for token_value in weights.keys():
		var token := str(token_value)
		if role_tokens.has(token):
			multiplier *= maxf(0.0, float(weights.get(token_value, 1.0)))
	return multiplier


static func _category_modifier_multiplier(value: Variant, category: String) -> float:
	if not (value is Dictionary):
		return 1.0
	var weights: Dictionary = value as Dictionary
	if category.is_empty() or not weights.has(category):
		return 1.0
	return maxf(0.0, float(weights.get(category, 1.0)))


static func _sources_are_valid(value: Variant) -> bool:
	for source in _string_array(value as Array):
		if not ["required", "optional", "forced"].has(source):
			return false
	return true


static func _string_array_is_valid(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item in (value as Array):
		var text := str(item)
		if text.is_empty() or not _is_system_token(text):
			return false
	return true


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
