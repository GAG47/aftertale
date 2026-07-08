class_name SemanticRoleExpander
extends RefCounted

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const RegionTypeProfileScript := preload("res://scripts/systems/regions/region_type_profile.gd")
const SemanticRoleResultValidatorScript := preload("res://scripts/systems/regions/semantic_role_result_validator.gd")

const SCHEMA_VERSION := 1
const COMPILER_VERSION := "v67.2"

var _rng := RandomNumberGenerator.new()


func expand_roles_result(input: Dictionary) -> Dictionary:
	var region_input: RefCounted = RegionInputScript.new()
	var input_errors: Array[String] = region_input.configure(input)
	if not input_errors.is_empty():
		return _failure("validate_region_input", input_errors, {})

	var region_data: Dictionary = region_input.to_dictionary()
	var region_type := str(region_data.get("region_type", ""))
	var profile_loader: RefCounted = RegionTypeProfileScript.new()
	var profile_result: Dictionary = profile_loader.load_profile_result(region_type)
	if not bool(profile_result.get("success", false)):
		return _failure("load_region_type_profile", profile_result.get("errors", []) as Array[String], {
			"region_input": region_data,
		})
	var profile: RefCounted = profile_result.get("profile") as RefCounted
	var profile_errors := _validate_input_against_profile(region_data, profile)
	if not profile_errors.is_empty():
		return _failure("validate_region_input_against_profile", profile_errors, {
			"region_input": region_data,
			"profile_path": str(profile_result.get("profile_path", "")),
		})

	_rng.seed = _stable_seed(int(region_data.get("seed", 0)), str(region_data.get("region_id", "")), "semantic_roles")
	var generation_result := _generate_roles(region_data, profile)
	if not bool(generation_result.get("success", false)):
		return _failure("expand_semantic_roles", generation_result.get("errors", []) as Array[String], {
			"region_input": region_data,
			"profile_path": str(profile_result.get("profile_path", "")),
		})

	var selected_roles: Array = generation_result.get("selected_roles", []) as Array
	_assign_role_ids(selected_roles, region_data)
	var semantic_result := {
		"schema_version": SCHEMA_VERSION,
		"compiler_version": COMPILER_VERSION,
		"stage": "semantic_roles",
		"region_id": str(region_data.get("region_id", "")),
		"region_type": region_type,
		"region_slug": str(region_data.get("region_slug", "")),
		"seed": int(region_data.get("seed", 0)),
		"source_hash": _source_hash(region_data),
		"profile_path": str(profile_result.get("profile_path", "")),
		"selected_roles": selected_roles,
		"debug_summary": _debug_summary(selected_roles),
	}
	var validator: RefCounted = SemanticRoleResultValidatorScript.new()
	var validation_errors: Array[String] = validator.validate(semantic_result)
	if not validation_errors.is_empty():
		return _failure("validate_semantic_role_result", validation_errors, {
			"region_input": region_data,
			"semantic_role_result": semantic_result,
		})
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"semantic_role_result": semantic_result,
	}


func _validate_input_against_profile(region_data: Dictionary, profile: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var required_roles := _role_type_array(region_data.get("required_roles", []) as Array)
	var required_set := _set_from_array(required_roles)
	for role_type in profile.required_role_types():
		if not required_set.has(role_type):
			errors.append("RegionInput.required_roles is missing profile-required role_type: %s" % role_type)
	for role_type in required_roles:
		if not profile.role_definition(role_type).is_empty() and profile.allows_source(role_type, "required"):
			continue
		errors.append("RegionInput.required_roles contains unsupported required role_type for %s: %s" % [profile.region_type(), role_type])

	var optional_roles := _role_type_array(region_data.get("optional_role_pool", []) as Array)
	for role_type in optional_roles:
		if not profile.optional_role_types().has(role_type):
			errors.append("RegionInput.optional_role_pool contains unsupported optional role_type for %s: %s" % [profile.region_type(), role_type])
		elif not profile.allows_source(role_type, "optional"):
			errors.append("RegionInput.optional_role_pool role_type does not allow optional source: %s" % role_type)

	for forced_value in (region_data.get("forced_role_specs", []) as Array):
		var forced: Dictionary = forced_value as Dictionary
		var role_type := str(forced.get("role_type", ""))
		if profile.role_definition(role_type).is_empty():
			errors.append("RegionInput.forced_role_specs contains unsupported role_type for %s: %s" % [profile.region_type(), role_type])
		elif not profile.allows_source(role_type, "forced"):
			errors.append("RegionInput.forced_role_specs role_type does not allow forced source: %s" % role_type)

	var scale := str((region_data.get("coarse_context", {}) as Dictionary).get("scale", ""))
	if profile.optional_count_range(scale).is_empty():
		errors.append("RegionTypeProfile has no optional role count range for scale: %s" % scale)
	return errors


func _generate_roles(region_data: Dictionary, profile: RefCounted) -> Dictionary:
	var selected_roles: Array = []
	var selected_by_type: Dictionary = {}
	for role_type in profile.required_role_types():
		_add_role(selected_roles, selected_by_type, profile, role_type, role_type, "required", [])
	for forced_value in (region_data.get("forced_role_specs", []) as Array):
		var forced: Dictionary = forced_value as Dictionary
		var role_type := str(forced.get("role_type", ""))
		var role_slug := str(forced.get("role_slug", ""))
		var tags := _string_array(forced.get("role_tags", []) as Array)
		if selected_by_type.has(role_type) and not profile.allows_multiple(role_type):
			return _failure("expand_semantic_roles", ["forced role_type duplicates a non-multiple role_type: %s" % role_type], {})
		_add_role(selected_roles, selected_by_type, profile, role_type, role_slug, "forced", tags)

	var optional_result := _select_optional_roles(region_data, profile, selected_by_type)
	if not bool(optional_result.get("success", false)):
		return optional_result
	for optional_value in (optional_result.get("roles", []) as Array):
		var optional: Dictionary = optional_value as Dictionary
		_add_role(selected_roles, selected_by_type, profile, str(optional.get("role_type", "")), str(optional.get("role_type", "")), "optional", [])

	return {
		"success": true,
		"errors": [],
		"selected_roles": selected_roles,
	}


func _select_optional_roles(region_data: Dictionary, profile: RefCounted, selected_by_type: Dictionary) -> Dictionary:
	var coarse_context: Dictionary = region_data.get("coarse_context", {}) as Dictionary
	var scale := str(coarse_context.get("scale", ""))
	var count_range: Array[int] = profile.optional_count_range(scale)
	if count_range.is_empty():
		return _failure("select_optional_roles", ["RegionTypeProfile has no optional role count range for scale: %s" % scale], {})
	var desired_count := _rng.randi_range(count_range[0], count_range[1])
	var candidates: Array[Dictionary] = []
	for role_type in _role_type_array(region_data.get("optional_role_pool", []) as Array):
		if selected_by_type.has(role_type) and not profile.allows_multiple(role_type):
			continue
		var weight: float = profile.base_weight(role_type) * profile.context_weight_multiplier(coarse_context, role_type)
		if weight <= 0.0:
			continue
		candidates.append({
			"role_type": role_type,
			"weight": weight,
		})
	if desired_count > candidates.size():
		return _failure("select_optional_roles", [
			"not enough optional role candidates for %s scale %s: requested %d, available %d" % [
				str(region_data.get("region_type", "")),
				scale,
				desired_count,
				candidates.size(),
			],
		], {})
	var selected: Array[Dictionary] = []
	while selected.size() < desired_count:
		var index := _pick_weighted_candidate_index(candidates)
		if index < 0:
			return _failure("select_optional_roles", ["optional role weighted selection failed"], {})
		selected.append((candidates[index] as Dictionary).duplicate(true))
		candidates.remove_at(index)
	return {
		"success": true,
		"errors": [],
		"roles": selected,
	}


func _pick_weighted_candidate_index(candidates: Array[Dictionary]) -> int:
	var total := 0.0
	for candidate in candidates:
		total += maxf(0.0, float(candidate.get("weight", 0.0)))
	if total <= 0.0:
		return -1
	var roll := _rng.randf() * total
	var cursor := 0.0
	for index in range(candidates.size()):
		var candidate: Dictionary = candidates[index] as Dictionary
		cursor += maxf(0.0, float(candidate.get("weight", 0.0)))
		if roll <= cursor:
			return index
	return candidates.size() - 1


func _add_role(selected_roles: Array, selected_by_type: Dictionary, profile: RefCounted, role_type: String, role_slug: String, role_source: String, extra_tags: Array[String]) -> void:
	selected_roles.append(_role_template(profile, role_type, role_slug, role_source, extra_tags))
	selected_by_type[role_type] = int(selected_by_type.get(role_type, 0)) + 1


func _role_template(profile: RefCounted, role_type: String, role_slug: String, role_source: String, extra_tags: Array[String]) -> Dictionary:
	return {
		"role_id": "",
		"role_type": role_type,
		"role_slug": role_slug,
		"role_source": role_source,
		"role_tags": _unique_tags(profile.role_tags(role_type), extra_tags),
	}


func _assign_role_ids(selected_roles: Array, region_data: Dictionary) -> void:
	var segments := str(region_data.get("region_id", "")).split(".")
	var scope := str(segments[1])
	var region_type := str(region_data.get("region_type", ""))
	var region_slug := str(region_data.get("region_slug", ""))
	for index in range(selected_roles.size()):
		var role: Dictionary = selected_roles[index] as Dictionary
		role["role_id"] = "role.%s.%s.%s.%s.rr_%04d" % [
			scope,
			region_type,
			region_slug,
			str(role.get("role_slug", "")),
			index + 1,
		]
		selected_roles[index] = role


func _debug_summary(selected_roles: Array) -> Dictionary:
	var source_counts: Dictionary = {}
	var role_types: Array[String] = []
	for role_value in selected_roles:
		var role: Dictionary = role_value as Dictionary
		var source := str(role.get("role_source", ""))
		source_counts[source] = int(source_counts.get(source, 0)) + 1
		role_types.append(str(role.get("role_type", "")))
	role_types.sort()
	return {
		"role_count": selected_roles.size(),
		"source_counts": source_counts,
		"role_types": role_types,
	}


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result


static func _role_type_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if value is String:
			result.append(str(value))
		elif value is Dictionary:
			result.append(str((value as Dictionary).get("role_type", "")))
	return result


static func _set_from_array(values: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[value] = true
	return result


static func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


static func _unique_tags(base_tags: Array[String], extra_tags: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for tag in base_tags + extra_tags:
		if tag.is_empty() or seen.has(tag):
			continue
		seen[tag] = true
		result.append(tag)
	return result


static func _stable_seed(seed: int, region_id: String, salt: String) -> int:
	return int(abs(seed * 4099 + _stable_text_hash("%s:%s" % [region_id, salt])) % 2147483647)


static func _source_hash(data: Dictionary) -> String:
	return "sh_%d" % _stable_text_hash(_canonical_value(data))


static func _stable_text_hash(text: String) -> int:
	var value := 2166136261
	for index in range(text.length()):
		value = int((value ^ text.unicode_at(index)) * 16777619) % 2147483647
	return abs(value)


static func _canonical_value(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for key_value in dictionary.keys():
			keys.append(str(key_value))
		keys.sort()
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s:%s" % [JSON.stringify(key), _canonical_value(dictionary.get(key))])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts: Array[String] = []
		for item in (value as Array):
			parts.append(_canonical_value(item))
		return "[%s]" % ",".join(parts)
	return JSON.stringify(value)
