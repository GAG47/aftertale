class_name RegionInput
extends RefCounted

const RegionSemanticVocabularyScript := preload("res://scripts/systems/regions/region_semantic_vocabulary.gd")

const SCHEMA_VERSION := 2
const REGION_ID_PREFIX := "region"
const REGION_CODE_PREFIX := "rg_"
const FORBIDDEN_ROLE_POOL_KEYS := ["required_roles", "optional_role_pool"]

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

	errors.append_array(RegionSemanticVocabularyScript.validate_coarse_context(data.get("coarse_context", null), "coarse_context"))
	errors.append_array(RegionSemanticVocabularyScript.validate_trait_array(data.get("region_traits", null), "region_traits"))
	errors.append_array(RegionSemanticVocabularyScript.validate_fact_array(data.get("region_facts", null), "region_facts"))
	errors.append_array(RegionSemanticVocabularyScript.validate_need_array(data.get("required_needs", null), "required_needs"))
	errors.append_array(RegionSemanticVocabularyScript.validate_need_array(data.get("optional_needs", null), "optional_needs"))
	for key in FORBIDDEN_ROLE_POOL_KEYS:
		if data.has(key):
			errors.append("RegionInput.%s is not supported in schema v%d; use demand fields instead" % [key, SCHEMA_VERSION])
	errors.append_array(_validate_forced_role_specs(data.get("forced_role_specs", null)))
	if data.has("external_connection_intents"):
		errors.append("RegionInput.external_connection_intents is not supported; Location nodes are the generation unit")
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


static func _validate_forced_role_specs(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if value == null:
		errors.append("RegionInput.forced_role_specs is missing")
		return errors
	if not (value is Array):
		errors.append("RegionInput.forced_role_specs must be an array")
		return errors
	var specs: Array = value as Array
	var seen: Dictionary = {}
	for index in range(specs.size()):
		if not (specs[index] is Dictionary):
			errors.append("RegionInput.forced_role_specs[%d] must be an object" % index)
			continue
		var spec: Dictionary = specs[index] as Dictionary
		if spec.has("role_id"):
			errors.append("RegionInput.forced_role_specs[%d] must not include role_id; semantic role ids are compiler output" % index)
		var role_type := str(spec.get("role_type", ""))
		var role_slug := str(spec.get("role_slug", ""))
		if role_type.is_empty():
			errors.append("RegionInput.forced_role_specs[%d].role_type is missing" % index)
		elif not _is_system_token(role_type):
			errors.append("RegionInput.forced_role_specs[%d].role_type must be a lowercase system token: %s" % [index, role_type])
		if role_slug.is_empty():
			errors.append("RegionInput.forced_role_specs[%d].role_slug is missing" % index)
		elif not _is_system_token(role_slug):
			errors.append("RegionInput.forced_role_specs[%d].role_slug must be a lowercase system token: %s" % [index, role_slug])
		if spec.has("role_tags") and not _string_array_is_valid(spec.get("role_tags")):
			errors.append("RegionInput.forced_role_specs[%d].role_tags must be an array of lowercase system tokens" % index)
		if not role_slug.is_empty():
			if seen.has(role_slug):
				errors.append("RegionInput.forced_role_specs contains duplicate role_slug: %s" % role_slug)
			seen[role_slug] = true
	return errors


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


static func _string_array_is_valid(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item in (value as Array):
		var text := str(item)
		if text.is_empty() or not _is_system_token(text):
			return false
	return true
