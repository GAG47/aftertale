class_name SemanticRoleExpander
extends RefCounted

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const RegionSemanticVocabularyScript := preload("res://scripts/systems/regions/region_semantic_vocabulary.gd")
const RegionTypeProfileScript := preload("res://scripts/systems/regions/region_type_profile.gd")
const SemanticRoleLibraryScript := preload("res://scripts/systems/regions/semantic_role_library.gd")
const SemanticRoleResultValidatorScript := preload("res://scripts/systems/regions/semantic_role_result_validator.gd")

const SCHEMA_VERSION := 2
const COMPILER_VERSION := "v67.8"

var _rng := RandomNumberGenerator.new()


func expand_roles_result(input: Dictionary) -> Dictionary:
	var region_input: RefCounted = RegionInputScript.new()
	var input_errors: Array[String] = region_input.configure(input)
	if not input_errors.is_empty():
		return _failure("validate_region_input", input_errors, {})
	var region_data: Dictionary = region_input.to_dictionary()
	var region_type := str(region_data.get("region_type", ""))

	var profile_result: Dictionary = RegionTypeProfileScript.new().load_profile_result(region_type)
	if not bool(profile_result.get("success", false)):
		return _failure("load_region_type_profile", profile_result.get("errors", []) as Array[String], {
			"region_input": region_data,
		})
	var profile: RefCounted = profile_result.get("profile") as RefCounted

	var library_result: Dictionary = SemanticRoleLibraryScript.new().load_library_result()
	if not bool(library_result.get("success", false)):
		return _failure("load_semantic_role_library", library_result.get("errors", []) as Array[String], {
			"region_input": region_data,
			"profile_path": str(profile_result.get("profile_path", "")),
		})
	var library: RefCounted = library_result.get("library") as RefCounted

	var profile_errors := _validate_input_against_profile(region_data, profile, library)
	if not profile_errors.is_empty():
		return _failure("validate_region_input_against_profile", profile_errors, {
			"region_input": region_data,
			"profile_path": str(profile_result.get("profile_path", "")),
			"role_library_path": str(library_result.get("library_path", "")),
		})

	_rng.seed = _stable_seed(int(region_data.get("seed", 0)), str(region_data.get("region_id", "")), "semantic_roles")
	var generation_result := _generate_roles(region_data, profile, library)
	if not bool(generation_result.get("success", false)):
		return _failure("expand_semantic_roles", generation_result.get("errors", []) as Array[String], {
			"region_input": region_data,
			"profile_path": str(profile_result.get("profile_path", "")),
			"role_library_path": str(library_result.get("library_path", "")),
		})

	var selected_roles: Array = generation_result.get("selected_roles", []) as Array
	_assign_role_ids(selected_roles, region_data)
	var demand_contract: Dictionary = generation_result.get("demand_contract", {}) as Dictionary
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
		"role_library_id": str(library_result.get("library_id", "")),
		"role_library_path": str(library_result.get("library_path", "")),
		"role_library_content_hash": str(library_result.get("library_content_hash", "")),
		"demand_contract": demand_contract,
		"selected_roles": selected_roles,
		"need_coverage": _need_coverage(selected_roles, demand_contract),
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


func _validate_input_against_profile(region_data: Dictionary, profile: RefCounted, library: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	for excluded_role_type in profile.excluded_role_types():
		if library.role_definition(excluded_role_type).is_empty():
			errors.append("RegionTypeProfile.excluded_role_types references an unknown library role: %s" % excluded_role_type)
	var demand_contract := _demand_contract(region_data, profile)
	for need_id in (demand_contract.get("required_needs", []) as Array):
		if _role_types_for_need(str(need_id), "required", region_data, profile, library).is_empty():
			errors.append("RegionInput.required_needs has no required role candidate for %s: %s" % [profile.region_type(), str(need_id)])
	for need_id in (demand_contract.get("optional_needs", []) as Array):
		if _role_types_for_need(str(need_id), "optional", region_data, profile, library).is_empty():
			errors.append("RegionInput.optional_needs has no optional role candidate for %s: %s" % [profile.region_type(), str(need_id)])
	for forced_value in (region_data.get("forced_role_specs", []) as Array):
		var forced: Dictionary = forced_value as Dictionary
		var role_type := str(forced.get("role_type", ""))
		var definition: Dictionary = library.role_definition(role_type)
		if definition.is_empty():
			errors.append("RegionInput.forced_role_specs contains unsupported role_type in SemanticRoleLibrary: %s" % role_type)
		elif not library.allows_source(role_type, "forced"):
			errors.append("RegionInput.forced_role_specs role_type does not allow forced source: %s" % role_type)
		elif not profile.allows_role_definition(role_type, definition):
			errors.append("RegionInput.forced_role_specs role_type is outside RegionTypeProfile semantic scope: %s" % role_type)
		elif not library.conditions_match(role_type, region_data):
			errors.append("RegionInput.forced_role_specs role_type does not satisfy its region conditions: %s" % role_type)
	var scale := str((region_data.get("coarse_context", {}) as Dictionary).get("scale", ""))
	if profile.optional_count_range(scale).is_empty():
		errors.append("RegionTypeProfile has no optional role count range for scale: %s" % scale)
	return errors


func _generate_roles(region_data: Dictionary, profile: RefCounted, library: RefCounted) -> Dictionary:
	var demand_contract := _demand_contract(region_data, profile)
	var selected_roles: Array = []
	var selected_by_type: Dictionary = {}
	for need_id in (demand_contract.get("required_needs", []) as Array):
		if _need_is_covered(selected_roles, str(need_id)):
			continue
		var required_role := _best_role_for_need(str(need_id), "required", region_data, profile, library, selected_by_type)
		if required_role.is_empty():
			return _failure("expand_semantic_roles", ["No semantic role can satisfy required need: %s" % str(need_id)], {})
		_add_role(
			selected_roles,
			selected_by_type,
			library,
			str(required_role.get("role_type", "")),
			str(required_role.get("role_type", "")),
			"required",
			[],
			[str(need_id)]
		)

	for forced_value in (region_data.get("forced_role_specs", []) as Array):
		var forced: Dictionary = forced_value as Dictionary
		var role_type := str(forced.get("role_type", ""))
		var role_slug := str(forced.get("role_slug", ""))
		var tags := _string_array(forced.get("role_tags", []) as Array)
		if selected_by_type.has(role_type) and not library.allows_multiple(role_type):
			return _failure("expand_semantic_roles", ["forced role_type duplicates a non-multiple role_type: %s" % role_type], {})
		_add_role(
			selected_roles,
			selected_by_type,
			library,
			role_type,
			role_slug,
			"forced",
			tags,
			_matched_needs_for_role(library, role_type, demand_contract)
		)

	var uncovered := _uncovered_required_needs(selected_roles, demand_contract)
	if not uncovered.is_empty():
		return _failure("expand_semantic_roles", ["Required semantic needs are not covered: %s" % ",".join(uncovered)], {})

	var optional_result := _select_optional_roles(region_data, profile, library, selected_by_type, demand_contract)
	if not bool(optional_result.get("success", false)):
		return optional_result
	for optional_value in (optional_result.get("roles", []) as Array):
		var optional: Dictionary = optional_value as Dictionary
		_add_role(
			selected_roles,
			selected_by_type,
			library,
			str(optional.get("role_type", "")),
			str(optional.get("role_type", "")),
			"optional",
			[],
			optional.get("matched_need_ids", []) as Array
		)
	return {
		"success": true,
		"errors": [],
		"demand_contract": demand_contract,
		"selected_roles": selected_roles,
	}


func _demand_contract(region_data: Dictionary, profile: RefCounted) -> Dictionary:
	var required: Array = []
	required.append_array(profile.required_needs())
	required.append_array(RegionSemanticVocabularyScript.need_array(region_data.get("required_needs", []) as Array))
	var optional: Array = []
	optional.append_array(profile.optional_needs())
	optional.append_array(RegionSemanticVocabularyScript.need_array(region_data.get("optional_needs", []) as Array))
	var required_needs := RegionSemanticVocabularyScript.unique_strings(required)
	var optional_needs := RegionSemanticVocabularyScript.unique_strings(optional)
	for need_id in required_needs:
		optional_needs.erase(need_id)
	return {
		"required_needs": required_needs,
		"optional_needs": optional_needs,
		"region_traits": RegionSemanticVocabularyScript.unique_strings(region_data.get("region_traits", []) as Array),
		"region_facts": RegionSemanticVocabularyScript.unique_strings(region_data.get("region_facts", []) as Array),
		"coarse_context": (region_data.get("coarse_context", {}) as Dictionary).duplicate(true),
	}


func _candidate_role_types(source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted) -> Array[String]:
	var result: Array[String] = []
	for role_type in library.role_types():
		var definition: Dictionary = library.role_definition(role_type)
		if not library.allows_source(role_type, source):
			continue
		if not profile.allows_role_definition(role_type, definition):
			continue
		if not library.conditions_match(role_type, region_data):
			continue
		result.append(role_type)
	return result


func _role_types_for_need(need_id: String, source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted) -> Array[String]:
	var result: Array[String] = []
	for role_type in _candidate_role_types(source, region_data, profile, library):
		if library.role_satisfies(role_type).has(need_id):
			result.append(role_type)
	return result


func _best_role_for_need(need_id: String, source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted, selected_by_type: Dictionary) -> Dictionary:
	var candidates := _role_types_for_need(need_id, source, region_data, profile, library)
	candidates.sort()
	var best_role_type := ""
	var best_score := -1.0
	for role_type in candidates:
		if selected_by_type.has(role_type) and not library.allows_multiple(role_type):
			continue
		var score := _role_score(region_data, profile, library, role_type)
		if score > best_score:
			best_score = score
			best_role_type = role_type
	if best_role_type.is_empty():
		return {}
	return {
		"role_type": best_role_type,
		"score": best_score,
	}


func _select_optional_roles(region_data: Dictionary, profile: RefCounted, library: RefCounted, selected_by_type: Dictionary, demand_contract: Dictionary) -> Dictionary:
	var coarse_context: Dictionary = region_data.get("coarse_context", {}) as Dictionary
	var scale := str(coarse_context.get("scale", ""))
	var count_range: Array[int] = profile.optional_count_range(scale)
	if count_range.is_empty():
		return _failure("select_optional_roles", ["RegionTypeProfile has no optional role count range for scale: %s" % scale], {})
	var desired_count := _rng.randi_range(count_range[0], count_range[1])
	var candidates: Array[Dictionary] = []
	for role_type in _candidate_role_types("optional", region_data, profile, library):
		if selected_by_type.has(role_type) and not library.allows_multiple(role_type):
			continue
		var matched_need_ids: Array[String] = _matched_optional_needs(library, role_type, demand_contract)
		if matched_need_ids.is_empty():
			continue
		var weight := _role_score(region_data, profile, library, role_type)
		if weight <= 0.0:
			continue
		candidates.append({
			"role_type": role_type,
			"weight": weight,
			"matched_need_ids": matched_need_ids,
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


func _role_score(region_data: Dictionary, profile: RefCounted, library: RefCounted, role_type: String) -> float:
	var coarse_context: Dictionary = region_data.get("coarse_context", {}) as Dictionary
	return profile.context_weight_multiplier(coarse_context, library.role_definition(role_type))


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


func _add_role(selected_roles: Array, selected_by_type: Dictionary, library: RefCounted, role_type: String, role_slug: String, role_source: String, extra_tags: Array[String], matched_need_ids: Array) -> void:
	selected_roles.append(_role_template(library, role_type, role_slug, role_source, extra_tags, matched_need_ids))
	selected_by_type[role_type] = int(selected_by_type.get(role_type, 0)) + 1


func _role_template(library: RefCounted, role_type: String, role_slug: String, role_source: String, extra_tags: Array[String], matched_need_ids: Array) -> Dictionary:
	return {
		"role_id": "",
		"role_type": role_type,
		"role_slug": role_slug,
		"role_source": role_source,
		"role_tags": _unique_tags([], extra_tags),
		"satisfies": library.role_satisfies(role_type),
		"properties": library.role_properties(role_type),
		"affinity": library.role_affinity(role_type),
		"category": library.role_category(role_type),
		"matched_need_ids": RegionSemanticVocabularyScript.unique_strings(matched_need_ids),
		"role_definition_id": library.role_definition_id(role_type),
		"role_definition_hash": library.role_definition_hash(role_type),
		"role_library_id": library.library_id(),
		"role_library_path": library.library_path(),
		"role_library_content_hash": library.library_content_hash(),
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


func _need_coverage(selected_roles: Array, demand_contract: Dictionary) -> Array:
	var coverage: Array = []
	var required_needs: Array = demand_contract.get("required_needs", []) as Array
	var optional_needs: Array = demand_contract.get("optional_needs", []) as Array
	for need_id in required_needs + optional_needs:
		var role_ids: Array[String] = []
		for role_value in selected_roles:
			var role: Dictionary = role_value as Dictionary
			if (role.get("satisfies", []) as Array).has(need_id):
				role_ids.append(str(role.get("role_id", "")))
		coverage.append({
			"need_id": str(need_id),
			"required": required_needs.has(need_id),
			"role_ids": role_ids,
		})
	return coverage


func _need_is_covered(selected_roles: Array, need_id: String) -> bool:
	for role_value in selected_roles:
		var role: Dictionary = role_value as Dictionary
		if (role.get("satisfies", []) as Array).has(need_id):
			return true
	return false


func _uncovered_required_needs(selected_roles: Array, demand_contract: Dictionary) -> Array[String]:
	var uncovered: Array[String] = []
	for need_id in (demand_contract.get("required_needs", []) as Array):
		if not _need_is_covered(selected_roles, str(need_id)):
			uncovered.append(str(need_id))
	return uncovered


func _matched_needs_for_role(library: RefCounted, role_type: String, demand_contract: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var satisfies: Array[String] = library.role_satisfies(role_type)
	for need_id in (demand_contract.get("required_needs", []) as Array) + (demand_contract.get("optional_needs", []) as Array):
		if satisfies.has(str(need_id)):
			result.append(str(need_id))
	return result


func _matched_optional_needs(library: RefCounted, role_type: String, demand_contract: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var satisfies: Array[String] = library.role_satisfies(role_type)
	for need_id in (demand_contract.get("optional_needs", []) as Array):
		if satisfies.has(str(need_id)):
			result.append(str(need_id))
	return result


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
