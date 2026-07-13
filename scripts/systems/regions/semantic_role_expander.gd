class_name SemanticRoleExpander
extends RefCounted

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const RegionSemanticVocabularyScript := preload("res://scripts/systems/regions/region_semantic_vocabulary.gd")
const RegionTypeProfileScript := preload("res://scripts/systems/regions/region_type_profile.gd")
const SemanticRoleLibraryScript := preload("res://scripts/systems/regions/semantic_role_library.gd")
const SemanticRoleResultValidatorScript := preload("res://scripts/systems/regions/semantic_role_result_validator.gd")

const SCHEMA_VERSION := 3
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
	for excluded_form_id in profile.excluded_form_ids():
		if library.form_definition(excluded_form_id).is_empty():
			errors.append("RegionTypeProfile.excluded_form_ids references an unknown library form: %s" % excluded_form_id)
	var demand_contract := _demand_contract(region_data, profile)
	for need_id in (demand_contract.get("required_needs", []) as Array):
		if _form_ids_for_need(str(need_id), "required", region_data, profile, library).is_empty():
			errors.append("RegionInput.required_needs has no required concrete form candidate for %s: %s" % [profile.region_type(), str(need_id)])
	for need_id in (demand_contract.get("optional_needs", []) as Array):
		if _form_ids_for_need(str(need_id), "optional", region_data, profile, library).is_empty():
			errors.append("RegionInput.optional_needs has no optional concrete form candidate for %s: %s" % [profile.region_type(), str(need_id)])
	for forced_value in (region_data.get("forced_role_specs", []) as Array):
		var forced: Dictionary = forced_value as Dictionary
		var archetype_id := str(forced.get("archetype_id", ""))
		var requested_form_id := str(forced.get("form_id", ""))
		if library.archetype_definition(archetype_id).is_empty():
			errors.append("RegionInput.forced_role_specs contains unsupported archetype_id in SemanticRoleLibrary: %s" % archetype_id)
			continue
		if not requested_form_id.is_empty():
			if library.form_definition(requested_form_id).is_empty():
				errors.append("RegionInput.forced_role_specs contains unsupported form_id in SemanticRoleLibrary: %s" % requested_form_id)
			elif library.form_archetype_id(requested_form_id) != archetype_id:
				errors.append("RegionInput.forced_role_specs form_id does not belong to archetype_id: %s / %s" % [archetype_id, requested_form_id])
			elif not _form_is_candidate(requested_form_id, "forced", region_data, profile, library):
				errors.append("RegionInput.forced_role_specs form is outside profile scope or does not satisfy region conditions: %s" % requested_form_id)
		elif _form_ids_for_archetype(archetype_id, "forced", region_data, profile, library).is_empty():
			errors.append("RegionInput.forced_role_specs archetype has no valid concrete form in this region: %s" % archetype_id)
	var scale := str((region_data.get("coarse_context", {}) as Dictionary).get("scale", ""))
	if profile.optional_count_range(scale).is_empty():
		errors.append("RegionTypeProfile has no optional role count range for scale: %s" % scale)
	return errors


func _generate_roles(region_data: Dictionary, profile: RefCounted, library: RefCounted) -> Dictionary:
	var demand_contract := _demand_contract(region_data, profile)
	var selected_roles: Array = []
	var selected_by_archetype: Dictionary = {}
	for forced_value in (region_data.get("forced_role_specs", []) as Array):
		var forced: Dictionary = forced_value as Dictionary
		var archetype_id := str(forced.get("archetype_id", ""))
		var form_id := str(forced.get("form_id", ""))
		if form_id.is_empty():
			form_id = _best_form_for_archetype(archetype_id, "forced", region_data, profile, library)
		var role_slug := str(forced.get("role_slug", ""))
		var tags := _string_array(forced.get("role_tags", []) as Array)
		if selected_by_archetype.has(archetype_id) and not library.allows_multiple(form_id):
			return _failure("expand_semantic_roles", ["forced archetype duplicates a non-multiple archetype: %s" % archetype_id], {})
		_add_role(
			selected_roles,
			selected_by_archetype,
			library,
			form_id,
			role_slug,
			"forced",
			tags,
			_matched_needs_for_form(library, form_id, demand_contract)
		)
	for need_id in (demand_contract.get("required_needs", []) as Array):
		if _need_is_covered(selected_roles, str(need_id)):
			continue
		var required_form := _best_form_for_need(str(need_id), "required", region_data, profile, library, selected_by_archetype)
		if required_form.is_empty():
			return _failure("expand_semantic_roles", ["No concrete semantic form can satisfy required need: %s" % str(need_id)], {})
		_add_role(
			selected_roles,
			selected_by_archetype,
			library,
			str(required_form.get("form_id", "")),
			str(required_form.get("form_id", "")),
			"required",
			[],
			[str(need_id)]
		)

	var uncovered := _uncovered_required_needs(selected_roles, demand_contract)
	if not uncovered.is_empty():
		return _failure("expand_semantic_roles", ["Required semantic needs are not covered: %s" % ",".join(uncovered)], {})

	var optional_result := _select_optional_roles(region_data, profile, library, selected_by_archetype, demand_contract)
	if not bool(optional_result.get("success", false)):
		return optional_result
	for optional_value in (optional_result.get("roles", []) as Array):
		var optional: Dictionary = optional_value as Dictionary
		var form_id := str(optional.get("form_id", ""))
		_add_role(
			selected_roles,
			selected_by_archetype,
			library,
			form_id,
			form_id,
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


func _candidate_form_ids(source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted) -> Array[String]:
	var result: Array[String] = []
	for form_id in library.form_ids():
		if _form_is_candidate(form_id, source, region_data, profile, library):
			result.append(form_id)
	return result


func _form_is_candidate(form_id: String, source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted) -> bool:
	if not library.allows_source(form_id, source):
		return false
	if not profile.allows_form_definition(form_id, library.composed_definition(form_id)):
		return false
	return library.conditions_match(form_id, region_data)


func _form_ids_for_need(need_id: String, source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted) -> Array[String]:
	var result: Array[String] = []
	for form_id in _candidate_form_ids(source, region_data, profile, library):
		if library.form_satisfies(form_id).has(need_id):
			result.append(form_id)
	return result


func _form_ids_for_archetype(archetype_id: String, source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted) -> Array[String]:
	var result: Array[String] = []
	for form_id in library.forms_for_archetype(archetype_id):
		if _form_is_candidate(form_id, source, region_data, profile, library):
			result.append(form_id)
	return result


func _best_form_for_need(need_id: String, source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted, selected_by_archetype: Dictionary) -> Dictionary:
	var candidates := _form_ids_for_need(need_id, source, region_data, profile, library)
	candidates.sort()
	var best_form_id := ""
	var best_score := -1.0
	for form_id in candidates:
		var archetype_id := str(library.form_archetype_id(form_id))
		if selected_by_archetype.has(archetype_id) and not library.allows_multiple(form_id):
			continue
		var score := _form_score(region_data, profile, library, form_id)
		if score > best_score:
			best_score = score
			best_form_id = form_id
	if best_form_id.is_empty():
		return {}
	return {"form_id": best_form_id, "score": best_score}


func _best_form_for_archetype(archetype_id: String, source: String, region_data: Dictionary, profile: RefCounted, library: RefCounted) -> String:
	var candidates := _form_ids_for_archetype(archetype_id, source, region_data, profile, library)
	candidates.sort()
	var best_form_id := ""
	var best_score := -1.0
	for form_id in candidates:
		var score := _form_score(region_data, profile, library, form_id)
		if score > best_score:
			best_score = score
			best_form_id = form_id
	return best_form_id


func _select_optional_roles(region_data: Dictionary, profile: RefCounted, library: RefCounted, selected_by_archetype: Dictionary, demand_contract: Dictionary) -> Dictionary:
	var coarse_context: Dictionary = region_data.get("coarse_context", {}) as Dictionary
	var scale := str(coarse_context.get("scale", ""))
	var count_range: Array[int] = profile.optional_count_range(scale)
	if count_range.is_empty():
		return _failure("select_optional_roles", ["RegionTypeProfile has no optional role count range for scale: %s" % scale], {})
	var desired_count := _rng.randi_range(count_range[0], count_range[1])
	var candidates: Array[Dictionary] = []
	for form_id in _candidate_form_ids("optional", region_data, profile, library):
		var archetype_id := str(library.form_archetype_id(form_id))
		if selected_by_archetype.has(archetype_id) and not library.allows_multiple(form_id):
			continue
		var matched_need_ids: Array[String] = _matched_optional_needs(library, form_id, demand_contract)
		if matched_need_ids.is_empty():
			continue
		var weight := _form_score(region_data, profile, library, form_id)
		if weight <= 0.0:
			continue
		candidates.append({
			"form_id": form_id,
			"archetype_id": archetype_id,
			"weight": weight,
			"matched_need_ids": matched_need_ids,
		})
	if desired_count > candidates.size():
		return _failure("select_optional_roles", [
			"not enough optional concrete form candidates for %s scale %s: requested %d, available %d" % [
				str(region_data.get("region_type", "")), scale, desired_count, candidates.size(),
			],
		], {})
	var selected: Array[Dictionary] = []
	var selected_optional_archetypes: Dictionary = {}
	while selected.size() < desired_count:
		var available: Array[Dictionary] = []
		for candidate in candidates:
			var archetype_id := str(candidate.get("archetype_id", ""))
			if selected_optional_archetypes.has(archetype_id):
				continue
			available.append(candidate)
		var index := _pick_weighted_candidate_index(available)
		if index < 0:
			return _failure("select_optional_roles", ["optional concrete form weighted selection failed"], {})
		var chosen: Dictionary = available[index]
		selected.append(chosen.duplicate(true))
		selected_optional_archetypes[str(chosen.get("archetype_id", ""))] = true
	return {"success": true, "errors": [], "roles": selected}


func _form_score(region_data: Dictionary, profile: RefCounted, library: RefCounted, form_id: String) -> float:
	var coarse_context: Dictionary = region_data.get("coarse_context", {}) as Dictionary
	return profile.context_weight_multiplier(coarse_context, library.composed_definition(form_id))


func _pick_weighted_candidate_index(candidates: Array[Dictionary]) -> int:
	var total := 0.0
	for candidate in candidates:
		total += maxf(0.0, float(candidate.get("weight", 0.0)))
	if total <= 0.0:
		return -1
	var roll := _rng.randf() * total
	var cursor := 0.0
	for index in range(candidates.size()):
		cursor += maxf(0.0, float(candidates[index].get("weight", 0.0)))
		if roll <= cursor:
			return index
	return candidates.size() - 1


func _add_role(selected_roles: Array, selected_by_archetype: Dictionary, library: RefCounted, form_id: String, role_slug: String, role_source: String, extra_tags: Array[String], matched_need_ids: Array) -> void:
	selected_roles.append(_role_template(library, form_id, role_slug, role_source, extra_tags, matched_need_ids))
	var archetype_id := str(library.form_archetype_id(form_id))
	selected_by_archetype[archetype_id] = int(selected_by_archetype.get(archetype_id, 0)) + 1


func _role_template(library: RefCounted, form_id: String, role_slug: String, role_source: String, extra_tags: Array[String], matched_need_ids: Array) -> Dictionary:
	var archetype_id := str(library.form_archetype_id(form_id))
	return {
		"role_id": "",
		"role_type": form_id,
		"archetype_id": archetype_id,
		"form_id": form_id,
		"role_slug": role_slug,
		"role_source": role_source,
		"role_tags": _unique_tags([], extra_tags),
		"satisfies": library.form_satisfies(form_id),
		"properties": library.form_properties(form_id),
		"affinity": library.form_affinity(form_id),
		"gameplay_affordances": library.form_gameplay_affordances(form_id),
		"narrative_affordances": library.form_narrative_affordances(form_id),
		"category": library.form_category(form_id),
		"matched_need_ids": RegionSemanticVocabularyScript.unique_strings(matched_need_ids),
		"archetype_definition_id": library.archetype_definition_id(archetype_id),
		"archetype_definition_hash": library.archetype_definition_hash(archetype_id),
		"form_definition_id": library.form_definition_id(form_id),
		"form_definition_hash": library.form_definition_hash(form_id),
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
			scope, region_type, region_slug, str(role.get("role_slug", "")), index + 1,
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
		coverage.append({"need_id": str(need_id), "required": required_needs.has(need_id), "role_ids": role_ids})
	return coverage


func _need_is_covered(selected_roles: Array, need_id: String) -> bool:
	for role_value in selected_roles:
		if ((role_value as Dictionary).get("satisfies", []) as Array).has(need_id):
			return true
	return false


func _uncovered_required_needs(selected_roles: Array, demand_contract: Dictionary) -> Array[String]:
	var uncovered: Array[String] = []
	for need_id in (demand_contract.get("required_needs", []) as Array):
		if not _need_is_covered(selected_roles, str(need_id)):
			uncovered.append(str(need_id))
	return uncovered


func _matched_needs_for_form(library: RefCounted, form_id: String, demand_contract: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var satisfies: Array[String] = library.form_satisfies(form_id)
	for need_id in (demand_contract.get("required_needs", []) as Array) + (demand_contract.get("optional_needs", []) as Array):
		if satisfies.has(str(need_id)):
			result.append(str(need_id))
	return result


func _matched_optional_needs(library: RefCounted, form_id: String, demand_contract: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var satisfies: Array[String] = library.form_satisfies(form_id)
	for need_id in (demand_contract.get("optional_needs", []) as Array):
		if satisfies.has(str(need_id)):
			result.append(str(need_id))
	return result


func _debug_summary(selected_roles: Array) -> Dictionary:
	var source_counts: Dictionary = {}
	var archetype_ids: Array[String] = []
	var form_ids: Array[String] = []
	for role_value in selected_roles:
		var role: Dictionary = role_value as Dictionary
		var source := str(role.get("role_source", ""))
		source_counts[source] = int(source_counts.get(source, 0)) + 1
		archetype_ids.append(str(role.get("archetype_id", "")))
		form_ids.append(str(role.get("form_id", "")))
	archetype_ids.sort()
	form_ids.sort()
	return {
		"role_count": selected_roles.size(),
		"source_counts": source_counts,
		"archetype_ids": archetype_ids,
		"form_ids": form_ids,
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
