class_name EdgeContractProfile
extends RefCounted

const SCHEMA_VERSION := 1
const ALLOWED_ACTIVATIONS := ["required", "when_both_present"]
const ALLOWED_MATCH_MODES := ["unique_pair", "one_to_each", "each_to_one"]
const TOP_LEVEL_KEYS := {
	"schema_version": true,
	"profile_id": true,
	"allowed_edge_types": true,
	"allowed_access_rules": true,
	"allowed_traversal_tags": true,
	"allowed_validation_flags": true,
	"rules": true,
}
const RULE_KEYS := {
	"rule_id": true,
	"activation": true,
	"match_mode": true,
	"from_selector": true,
	"to_selector": true,
	"edge": true,
}
const SELECTOR_KEYS := {
	"location_types": true,
	"source_role_types": true,
	"required_tags": true,
	"excluded_tags": true,
}
const EDGE_KEYS := {
	"edge_type": true,
	"bidirectional": true,
	"access_rule": true,
	"traversal_tags": true,
	"validation_flags": true,
}
const FORBIDDEN_KEYS := {
	"region_id": true,
	"region_type": true,
	"region_slug": true,
	"from_region_id": true,
	"to_region_id": true,
	"target_region_id": true,
	"external_connection": true,
	"external_connection_intent": true,
	"boundary_location_id": true,
	"direction_hint": true,
	"exit_style": true,
	"scene_path": true,
	"spawn_id": true,
	"tilemap": true,
	"start_location_id": true,
}

var source_data: Dictionary = {}


func configure(data: Dictionary) -> Array[String]:
	source_data = data.duplicate(true)
	return validate()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if source_data.is_empty():
		errors.append("EdgeContractProfile is empty")
		return errors
	_validate_known_keys(source_data, TOP_LEVEL_KEYS, "EdgeContractProfile", errors)
	_scan_for_forbidden_keys(source_data, "", errors)
	if int(source_data.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("EdgeContractProfile.schema_version is unsupported: %s" % str(source_data.get("schema_version", "")))
	var current_profile_id := str(source_data.get("profile_id", ""))
	if not _is_system_token(current_profile_id):
		errors.append("EdgeContractProfile.profile_id must be a lowercase system token: %s" % current_profile_id)
	for key in ["allowed_edge_types", "allowed_access_rules", "allowed_traversal_tags", "allowed_validation_flags"]:
		if not (source_data.get(key, null) is Array):
			errors.append("EdgeContractProfile.%s must be an array" % key)
		elif not _string_array_is_valid(source_data.get(key), key != "allowed_validation_flags"):
			errors.append("EdgeContractProfile.%s must contain unique lowercase system tokens" % key)
	if not (source_data.get("rules", null) is Array):
		errors.append("EdgeContractProfile.rules must be an array")
		return errors
	var rules_value: Array = source_data.get("rules", []) as Array
	if rules_value.is_empty():
		errors.append("EdgeContractProfile.rules must not be empty")
	var seen_rule_ids: Dictionary = {}
	for index in range(rules_value.size()):
		_validate_rule(index, rules_value[index], seen_rule_ids, errors)
	return errors


func load_profile_result(resource_path: String) -> Dictionary:
	if resource_path.is_empty():
		return _failure(["EdgeContractProfile path is missing"], resource_path)
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return _failure(["EdgeContractProfile resource is missing: %s" % resource_path], resource_path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return _failure(["EdgeContractProfile resource must be a JSON object: %s" % resource_path], resource_path)
	var errors := configure(parsed as Dictionary)
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


func to_dictionary() -> Dictionary:
	return source_data.duplicate(true)


func profile_id() -> String:
	return str(source_data.get("profile_id", ""))


func rules() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in (source_data.get("rules", []) as Array):
		result.append((value as Dictionary).duplicate(true))
	return result


func rule(rule_id: String) -> Dictionary:
	for value in (source_data.get("rules", []) as Array):
		var current: Dictionary = value as Dictionary
		if str(current.get("rule_id", "")) == rule_id:
			return current.duplicate(true)
	return {}


func supports_edge_type(edge_type: String) -> bool:
	return _string_array(source_data.get("allowed_edge_types", []) as Array).has(edge_type)


func supports_access_rule(access_rule: String) -> bool:
	return _string_array(source_data.get("allowed_access_rules", []) as Array).has(access_rule)


func supports_traversal_tag(tag: String) -> bool:
	return _string_array(source_data.get("allowed_traversal_tags", []) as Array).has(tag)


func supports_validation_flag(flag: String) -> bool:
	return _string_array(source_data.get("allowed_validation_flags", []) as Array).has(flag)


func _validate_rule(index: int, value: Variant, seen_rule_ids: Dictionary, errors: Array[String]) -> void:
	var path := "EdgeContractProfile.rules[%d]" % index
	if not (value is Dictionary):
		errors.append("%s must be an object" % path)
		return
	var rule_data: Dictionary = value as Dictionary
	_validate_known_keys(rule_data, RULE_KEYS, path, errors)
	var rule_id := str(rule_data.get("rule_id", ""))
	if not _is_system_token(rule_id):
		errors.append("%s.rule_id must be a lowercase system token: %s" % [path, rule_id])
	elif seen_rule_ids.has(rule_id):
		errors.append("EdgeContractProfile contains duplicate rule_id: %s" % rule_id)
	seen_rule_ids[rule_id] = true
	var activation := str(rule_data.get("activation", ""))
	if not ALLOWED_ACTIVATIONS.has(activation):
		errors.append("%s.activation is unsupported: %s" % [path, activation])
	var match_mode := str(rule_data.get("match_mode", ""))
	if not ALLOWED_MATCH_MODES.has(match_mode):
		errors.append("%s.match_mode is unsupported: %s" % [path, match_mode])
	_validate_selector(rule_data.get("from_selector"), "%s.from_selector" % path, errors)
	_validate_selector(rule_data.get("to_selector"), "%s.to_selector" % path, errors)
	_validate_edge_spec(rule_data.get("edge"), "%s.edge" % path, errors)


func _validate_selector(value: Variant, path: String, errors: Array[String]) -> void:
	if not (value is Dictionary):
		errors.append("%s must be an object" % path)
		return
	var selector: Dictionary = value as Dictionary
	_validate_known_keys(selector, SELECTOR_KEYS, path, errors)
	var has_positive_selector := false
	for key in SELECTOR_KEYS.keys():
		if not selector.has(key):
			continue
		if not (selector.get(key) is Array) or not _string_array_is_valid(selector.get(key), false):
			errors.append("%s.%s must contain unique lowercase system tokens" % [path, key])
			continue
		if key != "excluded_tags" and not (selector.get(key) as Array).is_empty():
			has_positive_selector = true
	if not has_positive_selector:
		errors.append("%s must contain at least one positive node selector" % path)


func _validate_edge_spec(value: Variant, path: String, errors: Array[String]) -> void:
	if not (value is Dictionary):
		errors.append("%s must be an object" % path)
		return
	var edge: Dictionary = value as Dictionary
	_validate_known_keys(edge, EDGE_KEYS, path, errors)
	var edge_type := str(edge.get("edge_type", ""))
	if not supports_edge_type(edge_type):
		errors.append("%s.edge_type is not declared by the profile: %s" % [path, edge_type])
	if not (edge.get("bidirectional", null) is bool):
		errors.append("%s.bidirectional must be a boolean" % path)
	var access_rule := str(edge.get("access_rule", ""))
	if not supports_access_rule(access_rule):
		errors.append("%s.access_rule is not declared by the profile: %s" % [path, access_rule])
	if not (edge.get("traversal_tags", null) is Array) or not _string_array_is_valid(edge.get("traversal_tags"), true):
		errors.append("%s.traversal_tags must contain unique lowercase system tokens" % path)
	else:
		for tag_value in (edge.get("traversal_tags", []) as Array):
			var tag := str(tag_value)
			if not supports_traversal_tag(tag):
				errors.append("%s.traversal_tags contains an undeclared tag: %s" % [path, tag])
	if not (edge.get("validation_flags", null) is Array) or not _string_array_is_valid(edge.get("validation_flags"), false):
		errors.append("%s.validation_flags must contain unique lowercase system tokens" % path)
	else:
		for flag_value in (edge.get("validation_flags", []) as Array):
			var flag := str(flag_value)
			if not supports_validation_flag(flag):
				errors.append("%s.validation_flags contains an undeclared flag: %s" % [path, flag])


func _scan_for_forbidden_keys(value: Variant, path: String, errors: Array[String]) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		for key_value in dictionary.keys():
			var key := str(key_value)
			var next_path := key if path.is_empty() else "%s.%s" % [path, key]
			if FORBIDDEN_KEYS.has(key):
				errors.append("EdgeContractProfile must not contain Region, Scene, Runtime, or connection-intent field: %s" % next_path)
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


static func _failure(errors: Array[String], resource_path: String) -> Dictionary:
	return {
		"success": false,
		"errors": errors.duplicate(),
		"warnings": [],
		"profile_path": resource_path,
	}


static func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


static func _string_array_is_valid(value: Variant, require_non_empty: bool) -> bool:
	if not (value is Array):
		return false
	var values: Array = value as Array
	if require_non_empty and values.is_empty():
		return false
	var seen: Dictionary = {}
	for item in values:
		var text := str(item)
		if not _is_system_token(text) or seen.has(text):
			return false
		seen[text] = true
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
