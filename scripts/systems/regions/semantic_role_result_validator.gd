class_name SemanticRoleResultValidator
extends RefCounted

const SCHEMA_VERSION := 1
const FORBIDDEN_LOCATION_GRAPH_KEYS := {
	"location_id": true,
	"edge_id": true,
	"scene_path": true,
	"spawn_id": true,
	"tilemap": true,
	"target_location_id": true,
}
const ALLOWED_ROLE_SOURCES := ["required", "optional", "forced", "external"]


func validate(result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if result.is_empty():
		errors.append("SemanticRoleResult is empty")
		return errors
	_scan_for_forbidden_keys(result, "", errors)
	if int(result.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("SemanticRoleResult.schema_version is unsupported: %s" % str(result.get("schema_version", "")))
	if str(result.get("stage", "")) != "semantic_roles":
		errors.append("SemanticRoleResult.stage must be semantic_roles")
	for key in ["compiler_version", "region_id", "region_type", "region_slug", "seed", "source_hash"]:
		if str(result.get(key, "")).is_empty():
			errors.append("SemanticRoleResult.%s is missing" % key)
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
		var role: Dictionary = selected_roles[index] as Dictionary
		_validate_role(index, role, role_ids, role_slugs, errors)
	if not (result.get("external_connection_intents", null) is Array):
		errors.append("SemanticRoleResult.external_connection_intents must be an array")
	return errors


func _validate_role(index: int, role: Dictionary, role_ids: Dictionary, role_slugs: Dictionary, errors: Array[String]) -> void:
	for key in ["role_id", "role_type", "role_slug", "role_source", "role_tags"]:
		if not role.has(key):
			errors.append("SemanticRoleResult.selected_roles[%d].%s is missing" % [index, key])
	var role_id := str(role.get("role_id", ""))
	var role_type := str(role.get("role_type", ""))
	var role_slug := str(role.get("role_slug", ""))
	var role_source := str(role.get("role_source", ""))
	if role_id.is_empty() or not _is_role_id(role_id):
		errors.append("SemanticRoleResult.selected_roles[%d].role_id is invalid: %s" % [index, role_id])
	elif role_ids.has(role_id):
		errors.append("SemanticRoleResult contains duplicate role_id: %s" % role_id)
	role_ids[role_id] = true
	if role_type.is_empty() or not _is_system_token(role_type):
		errors.append("SemanticRoleResult.selected_roles[%d].role_type is invalid: %s" % [index, role_type])
	if role_slug.is_empty() or not _is_system_token(role_slug):
		errors.append("SemanticRoleResult.selected_roles[%d].role_slug is invalid: %s" % [index, role_slug])
	elif role_slugs.has(role_slug):
		errors.append("SemanticRoleResult contains duplicate role_slug: %s" % role_slug)
	role_slugs[role_slug] = true
	if not ALLOWED_ROLE_SOURCES.has(role_source):
		errors.append("SemanticRoleResult.selected_roles[%d].role_source is invalid: %s" % [index, role_source])
	if not (role.get("role_tags", null) is Array):
		errors.append("SemanticRoleResult.selected_roles[%d].role_tags must be an array" % index)
	elif not _string_array_is_valid(role.get("role_tags")):
		errors.append("SemanticRoleResult.selected_roles[%d].role_tags must contain lowercase system tokens" % index)


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


static func _is_role_id(value: String) -> bool:
	var segments := value.split(".")
	if segments.size() != 6:
		return false
	if str(segments[0]) != "role":
		return false
	if not _is_system_token(str(segments[1])):
		return false
	if not _is_system_token(str(segments[2])) or not str(segments[2]).ends_with("_region"):
		return false
	if not _is_system_token(str(segments[3])):
		return false
	if not _is_system_token(str(segments[4])):
		return false
	var code := str(segments[5])
	if not code.begins_with("rr_"):
		return false
	return code.substr(3).is_valid_int()


static func _string_array_is_valid(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item in (value as Array):
		var text := str(item)
		if text.is_empty() or not _is_system_token(text):
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
