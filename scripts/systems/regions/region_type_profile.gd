class_name RegionTypeProfile
extends RefCounted

const SCHEMA_VERSION := 1
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
	if not (source_data.get("role_definitions", null) is Dictionary):
		errors.append("RegionTypeProfile.role_definitions must be an object")
		return errors
	var role_definitions: Dictionary = source_data.get("role_definitions", {}) as Dictionary
	if role_definitions.is_empty():
		errors.append("RegionTypeProfile.role_definitions is empty")
	for role_type_value in role_definitions.keys():
		var role_type := str(role_type_value)
		if not _is_system_token(role_type):
			errors.append("RegionTypeProfile role type must be a lowercase system token: %s" % role_type)
			continue
		var definition: Dictionary = role_definitions.get(role_type, {}) as Dictionary
		if definition.is_empty():
			errors.append("RegionTypeProfile role definition is empty: %s" % role_type)
			continue
		if not (definition.get("role_tags", null) is Array):
			errors.append("RegionTypeProfile role_tags must be an array: %s" % role_type)
		elif not _string_array_is_valid(definition.get("role_tags")):
			errors.append("RegionTypeProfile role_tags must contain lowercase system tokens: %s" % role_type)
		if not (definition.get("allowed_sources", null) is Array):
			errors.append("RegionTypeProfile allowed_sources must be an array: %s" % role_type)
		elif not _sources_are_valid(definition.get("allowed_sources")):
			errors.append("RegionTypeProfile allowed_sources contains an illegal value: %s" % role_type)
		if not definition.has("allow_multiple"):
			errors.append("RegionTypeProfile allow_multiple is missing: %s" % role_type)
	if not _role_type_array_is_valid("required_role_types", role_definitions, true, errors):
		return errors
	_role_type_array_is_valid("optional_role_types", role_definitions, false, errors)
	if not (source_data.get("scale_optional_counts", null) is Dictionary):
		errors.append("RegionTypeProfile.scale_optional_counts must be an object")
	else:
		_validate_scale_optional_counts(errors)
	if not (source_data.get("role_weights", null) is Dictionary):
		errors.append("RegionTypeProfile.role_weights must be an object")
	else:
		_validate_role_weights(role_definitions, errors)
	var external_role_type := str(source_data.get("external_intent_role_type", ""))
	if external_role_type.is_empty():
		errors.append("RegionTypeProfile.external_intent_role_type is missing")
	elif not role_definitions.has(external_role_type):
		errors.append("RegionTypeProfile.external_intent_role_type is not defined: %s" % external_role_type)
	elif not allows_source(external_role_type, "external"):
		errors.append("RegionTypeProfile.external_intent_role_type does not allow external source: %s" % external_role_type)
	return errors


func to_dictionary() -> Dictionary:
	return source_data.duplicate(true)


func region_type() -> String:
	return str(source_data.get("region_type", ""))


func required_role_types() -> Array[String]:
	return _string_array(source_data.get("required_role_types", []) as Array)


func optional_role_types() -> Array[String]:
	return _string_array(source_data.get("optional_role_types", []) as Array)


func external_intent_role_type() -> String:
	return str(source_data.get("external_intent_role_type", ""))


func role_definition(role_type: String) -> Dictionary:
	var definitions: Dictionary = source_data.get("role_definitions", {}) as Dictionary
	return (definitions.get(role_type, {}) as Dictionary).duplicate(true)


func role_tags(role_type: String) -> Array[String]:
	var definition := role_definition(role_type)
	return _string_array(definition.get("role_tags", []) as Array)


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
	var modifiers: Dictionary = source_data.get("context_weight_modifiers", {}) as Dictionary
	for context_key_value in modifiers.keys():
		var context_key := str(context_key_value)
		if not coarse_context.has(context_key):
			continue
		var by_value: Dictionary = modifiers.get(context_key, {}) as Dictionary
		for context_value in _context_values(coarse_context.get(context_key)):
			var role_modifiers: Dictionary = by_value.get(context_value, {}) as Dictionary
			if role_modifiers.has(role_type):
				multiplier *= maxf(0.0, float(role_modifiers.get(role_type, 1.0)))
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


func _role_type_array_is_valid(key: String, role_definitions: Dictionary, require_non_empty: bool, errors: Array[String]) -> bool:
	if not (source_data.get(key, null) is Array):
		errors.append("RegionTypeProfile.%s must be an array" % key)
		return false
	var values := _string_array(source_data.get(key, []) as Array)
	if require_non_empty and values.is_empty():
		errors.append("RegionTypeProfile.%s must not be empty" % key)
	var seen: Dictionary = {}
	for role_type in values:
		if not role_definitions.has(role_type):
			errors.append("RegionTypeProfile.%s references undefined role type: %s" % [key, role_type])
		if seen.has(role_type):
			errors.append("RegionTypeProfile.%s contains duplicate role type: %s" % [key, role_type])
		seen[role_type] = true
	return true


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
	for role_type in optional_role_types():
		if not weights.has(role_type):
			errors.append("RegionTypeProfile.role_weights missing optional role type: %s" % role_type)
		elif float(weights.get(role_type, 0.0)) <= 0.0:
			errors.append("RegionTypeProfile.role_weights must be positive for optional role type: %s" % role_type)
	for key_value in weights.keys():
		var role_type := str(key_value)
		if not role_definitions.has(role_type):
			errors.append("RegionTypeProfile.role_weights references undefined role type: %s" % role_type)


static func _sources_are_valid(value: Variant) -> bool:
	for source in _string_array(value as Array):
		if not ["required", "optional", "forced", "external"].has(source):
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


static func _context_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in (value as Array):
			var text := str(item)
			if not text.is_empty():
				result.append(text)
	else:
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
