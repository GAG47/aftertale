class_name LocationNodeProfile
extends RefCounted

const SCHEMA_VERSION := 1
const PROFILE_PATH_PATTERN := "res://data/regions/location_node_profiles/%s.json"
const FORBIDDEN_EDGE_KEYS := {
	"edge_id": true,
	"from_location_id": true,
	"to_location_id": true,
	"target_location_id": true,
	"target_region_id": true,
	"resolved_connection": true,
	"scene_path": true,
	"spawn_id": true,
	"tilemap": true,
	"exit_id": true,
}

var source_data: Dictionary = {}


func configure(data: Dictionary) -> Array[String]:
	source_data = data.duplicate(true)
	return validate()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if source_data.is_empty():
		errors.append("LocationNodeProfile is empty")
		return errors
	_scan_for_forbidden_keys(source_data, "", errors)
	if not source_data.has("schema_version"):
		errors.append("LocationNodeProfile.schema_version is missing")
	elif int(source_data.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("LocationNodeProfile.schema_version is unsupported: %s" % str(source_data.get("schema_version")))
	var region_type := str(source_data.get("region_type", ""))
	if region_type.is_empty():
		errors.append("LocationNodeProfile.region_type is missing")
	elif not _is_system_token(region_type) or not region_type.ends_with("_region"):
		errors.append("LocationNodeProfile.region_type must be a lowercase *_region token: %s" % region_type)
	if not (source_data.get("role_to_location_rules", null) is Dictionary):
		errors.append("LocationNodeProfile.role_to_location_rules must be an object")
		return errors
	var rules: Dictionary = source_data.get("role_to_location_rules", {}) as Dictionary
	if rules.is_empty():
		errors.append("LocationNodeProfile.role_to_location_rules is empty")
	for role_type_value in rules.keys():
		_validate_rule(str(role_type_value), rules.get(role_type_value), errors)
	return errors


func to_dictionary() -> Dictionary:
	return source_data.duplicate(true)


func region_type() -> String:
	return str(source_data.get("region_type", ""))


func role_rule(role_type: String) -> Dictionary:
	var rules: Dictionary = source_data.get("role_to_location_rules", {}) as Dictionary
	return (rules.get(role_type, {}) as Dictionary).duplicate(true)


func has_role_rule(role_type: String) -> bool:
	var rules: Dictionary = source_data.get("role_to_location_rules", {}) as Dictionary
	return rules.has(role_type)


func location_type_for_role(role_type: String) -> String:
	return str(role_rule(role_type).get("location_type", ""))


func node_tags_for_role(role_type: String) -> Array[String]:
	return _string_array(role_rule(role_type).get("node_tags", []) as Array)


func is_boundary_role(role_type: String) -> bool:
	return bool(role_rule(role_type).get("boundary", false))


func is_hidden_role(role_type: String) -> bool:
	return bool(role_rule(role_type).get("hidden", false))


func supports_location_type(location_type: String) -> bool:
	var rules: Dictionary = source_data.get("role_to_location_rules", {}) as Dictionary
	for role_type_value in rules.keys():
		var rule: Dictionary = rules.get(role_type_value, {}) as Dictionary
		if str(rule.get("location_type", "")) == location_type:
			return true
	return false


func load_profile_result(region_type: String) -> Dictionary:
	if region_type.is_empty():
		return _failure(["region_type is missing"])
	var resource_path := PROFILE_PATH_PATTERN % region_type
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return _failure(["LocationNodeProfile resource is missing: %s" % resource_path], resource_path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return _failure(["LocationNodeProfile resource must be a JSON object: %s" % resource_path], resource_path)
	var errors := configure(parsed as Dictionary)
	if str(self.region_type()) != region_type:
		errors.append("LocationNodeProfile.region_type does not match requested type: %s != %s" % [self.region_type(), region_type])
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


func _validate_rule(role_type: String, value: Variant, errors: Array[String]) -> void:
	if role_type.is_empty() or not _is_system_token(role_type):
		errors.append("LocationNodeProfile role type must be a lowercase system token: %s" % role_type)
		return
	if role_type == "external_connection":
		errors.append("LocationNodeProfile external_connection role rules are not supported")
		return
	if not (value is Dictionary):
		errors.append("LocationNodeProfile role rule must be an object: %s" % role_type)
		return
	var rule: Dictionary = value as Dictionary
	if str(rule.get("location_type", "")).is_empty():
		errors.append("LocationNodeProfile role rule location_type is missing: %s" % role_type)
	elif not _is_system_token(str(rule.get("location_type", ""))):
		errors.append("LocationNodeProfile role rule location_type must be a lowercase system token: %s" % role_type)
	if not (rule.get("node_tags", null) is Array):
		errors.append("LocationNodeProfile role rule node_tags must be an array: %s" % role_type)
	elif not _string_array_is_valid(rule.get("node_tags")):
		errors.append("LocationNodeProfile role rule node_tags must contain lowercase system tokens: %s" % role_type)
	if not rule.has("count"):
		errors.append("LocationNodeProfile role rule count is missing: %s" % role_type)
	elif not _is_integer_like(rule.get("count")) or int(rule.get("count")) != 1:
		errors.append("LocationNodeProfile role rule count must be exactly 1 in v67.3: %s" % role_type)
	if rule.has("boundary") and not (rule.get("boundary") is bool):
		errors.append("LocationNodeProfile role rule boundary must be a boolean: %s" % role_type)
	if rule.has("hidden") and not (rule.get("hidden") is bool):
		errors.append("LocationNodeProfile role rule hidden must be a boolean: %s" % role_type)


func _scan_for_forbidden_keys(value: Variant, path: String, errors: Array[String]) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		for key_value in dictionary.keys():
			var key := str(key_value)
			var next_path := key if path.is_empty() else "%s.%s" % [path, key]
			if bool(FORBIDDEN_EDGE_KEYS.get(key, false)):
				errors.append("LocationNodeProfile must not contain v67.4 edge/scene field: %s" % next_path)
			_scan_for_forbidden_keys(dictionary.get(key_value), next_path, errors)
	elif value is Array:
		var values: Array = value as Array
		for index in range(values.size()):
			_scan_for_forbidden_keys(values[index], "%s[%d]" % [path, index], errors)


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


static func _string_array_is_valid(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item in (value as Array):
		var text := str(item)
		if text.is_empty() or not _is_system_token(text):
			return false
	return true


static func _is_integer_like(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_equal_approx(float(value), float(int(value)))
	if value is String:
		return str(value).is_valid_int()
	return false


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
