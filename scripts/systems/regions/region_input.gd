class_name RegionInput
extends RefCounted

const SCHEMA_VERSION := 1
const REGION_ID_PREFIX := "region"
const REGION_CODE_PREFIX := "rg_"
const REQUIRED_CONTEXT_KEYS := ["terrain_context", "political_context", "scale"]

var source_data: Dictionary = {}


func configure(data: Dictionary) -> Array[String]:
	source_data = data.duplicate(true)
	return validate()


func validate() -> Array[String]:
	return validate_data(source_data)


func to_dictionary() -> Dictionary:
	return source_data.duplicate(true)


static func validate_data(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if data.is_empty():
		errors.append("RegionInput is empty")
		return errors

	if not data.has("schema_version"):
		errors.append("RegionInput.schema_version is missing")
	elif not _is_integer_like(data.get("schema_version")):
		errors.append("RegionInput.schema_version must be an integer value")
	elif int(data.get("schema_version")) != SCHEMA_VERSION:
		errors.append("RegionInput.schema_version is unsupported: %s" % str(data.get("schema_version")))

	var region_id := str(data.get("region_id", ""))
	var region_type := str(data.get("region_type", ""))
	var region_slug := str(data.get("region_slug", ""))
	if region_id.is_empty():
		errors.append("RegionInput.region_id is missing")
	else:
		errors.append_array(_validate_region_id(region_id, region_type, region_slug))

	if region_type.is_empty():
		errors.append("RegionInput.region_type is missing")
	elif not _is_system_token(region_type) or not region_type.ends_with("_region"):
		errors.append("RegionInput.region_type must be a lowercase *_region system token: %s" % region_type)

	if region_slug.is_empty():
		errors.append("RegionInput.region_slug is missing")
	elif not _is_system_token(region_slug):
		errors.append("RegionInput.region_slug must be a lowercase system token: %s" % region_slug)

	if str(data.get("display_name", "")).is_empty():
		errors.append("RegionInput.display_name is missing")

	if not data.has("seed"):
		errors.append("RegionInput.seed is missing")
	elif not _is_integer_like(data.get("seed")):
		errors.append("RegionInput.seed must be an integer value")

	if not (data.get("coarse_context", null) is Dictionary):
		errors.append("RegionInput.coarse_context must be an object")
	else:
		var coarse_context: Dictionary = data.get("coarse_context", {}) as Dictionary
		if coarse_context.is_empty():
			errors.append("RegionInput.coarse_context is missing")
		else:
			for key in REQUIRED_CONTEXT_KEYS:
				if not coarse_context.has(key) or _context_value_is_empty(coarse_context.get(key)):
					errors.append("RegionInput.coarse_context.%s is missing" % key)

	errors.append_array(_validate_role_list(data, "required_roles", true))
	errors.append_array(_validate_role_list(data, "optional_role_pool", false))
	errors.append_array(_validate_external_connection_intents(data.get("external_connection_intents", null)))
	return errors


static func _validate_region_id(region_id: String, region_type: String, region_slug: String) -> Array[String]:
	var errors: Array[String] = []
	var segments := region_id.split(".")
	if segments.size() != 5:
		errors.append("RegionInput.region_id must use region.<scope>.<region_type>.<slug>.rg_####: %s" % region_id)
		return errors
	if str(segments[0]) != REGION_ID_PREFIX:
		errors.append("RegionInput.region_id must start with 'region.': %s" % region_id)
	if not _is_system_token(str(segments[1])):
		errors.append("RegionInput.region_id scope must be a lowercase system token: %s" % str(segments[1]))
	if not region_type.is_empty() and str(segments[2]) != region_type:
		errors.append("RegionInput.region_id region_type segment does not match region_type: %s != %s" % [str(segments[2]), region_type])
	elif not _is_system_token(str(segments[2])) or not str(segments[2]).ends_with("_region"):
		errors.append("RegionInput.region_id region_type segment must be a lowercase *_region token: %s" % str(segments[2]))
	if not region_slug.is_empty() and str(segments[3]) != region_slug:
		errors.append("RegionInput.region_id slug segment does not match region_slug: %s != %s" % [str(segments[3]), region_slug])
	elif not _is_system_token(str(segments[3])):
		errors.append("RegionInput.region_id slug segment must be a lowercase system token: %s" % str(segments[3]))
	var code := str(segments[4])
	if not code.begins_with(REGION_CODE_PREFIX) or code.length() <= REGION_CODE_PREFIX.length():
		errors.append("RegionInput.region_id stable code must use rg_####: %s" % code)
	else:
		var number_part := code.substr(REGION_CODE_PREFIX.length())
		if not number_part.is_valid_int():
			errors.append("RegionInput.region_id stable code suffix must be numeric: %s" % code)
	return errors


static func _validate_role_list(data: Dictionary, key: String, require_non_empty: bool) -> Array[String]:
	var errors: Array[String] = []
	if not data.has(key):
		errors.append("RegionInput.%s is missing" % key)
		return errors
	if not (data.get(key) is Array):
		errors.append("RegionInput.%s must be an array" % key)
		return errors
	var values: Array = data.get(key, []) as Array
	if require_non_empty and values.is_empty():
		errors.append("RegionInput.%s must contain at least one role" % key)
	var seen: Dictionary = {}
	for index in range(values.size()):
		var role_id := _role_id(values[index])
		if role_id.is_empty():
			errors.append("RegionInput.%s[%d] is missing a role id" % [key, index])
			continue
		if not _is_system_token(role_id):
			errors.append("RegionInput.%s[%d] role id must be a lowercase system token: %s" % [key, index, role_id])
		if seen.has(role_id):
			errors.append("RegionInput.%s contains duplicate role id: %s" % [key, role_id])
		seen[role_id] = true
	return errors


static func _validate_external_connection_intents(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if value == null:
		errors.append("RegionInput.external_connection_intents is missing")
		return errors
	if not (value is Array):
		errors.append("RegionInput.external_connection_intents must be an array")
		return errors
	var intents: Array = value as Array
	var seen: Dictionary = {}
	for index in range(intents.size()):
		if not (intents[index] is Dictionary):
			errors.append("RegionInput.external_connection_intents[%d] must be an object" % index)
			continue
		var intent: Dictionary = intents[index] as Dictionary
		var intent_id := str(intent.get("intent_id", intent.get("id", "")))
		if intent_id.is_empty():
			errors.append("RegionInput.external_connection_intents[%d].intent_id is missing" % index)
		elif not _is_system_token(intent_id):
			errors.append("RegionInput.external_connection_intents[%d].intent_id must be a lowercase system token: %s" % [index, intent_id])
		elif seen.has(intent_id):
			errors.append("RegionInput.external_connection_intents contains duplicate intent_id: %s" % intent_id)
		seen[intent_id] = true
		var target_region_id := str(intent.get("target_region_id", ""))
		if not target_region_id.is_empty():
			errors.append_array(_validate_region_id(target_region_id, "", ""))
	return errors


static func _role_id(value: Variant) -> String:
	if value is String:
		return str(value)
	if value is Dictionary:
		var role: Dictionary = value as Dictionary
		return str(role.get("role_id", role.get("id", "")))
	return ""


static func _context_value_is_empty(value: Variant) -> bool:
	if value is String:
		return str(value).is_empty()
	if value is Array:
		return (value as Array).is_empty()
	return value == null


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
