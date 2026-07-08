class_name EdgeContractGenerator
extends RefCounted

const EdgeContractProfileScript := preload("res://scripts/systems/regions/edge_contract_profile.gd")
const EdgeContractResultValidatorScript := preload("res://scripts/systems/regions/edge_contract_result_validator.gd")

const SCHEMA_VERSION := 1
const COMPILER_VERSION := "v67.4"


func generate_edges_result(location_node_results: Array, profile_path: String) -> Dictionary:
	if location_node_results.is_empty():
		return _failure("validate_location_node_results", ["At least one LocationNodeResult is required"], {})
	var source_result := _collect_source_nodes(location_node_results)
	if not bool(source_result.get("success", false)):
		return _failure("validate_location_node_results", source_result.get("errors", []) as Array[String], {
			"location_node_results": location_node_results,
		})
	var profile_loader: RefCounted = EdgeContractProfileScript.new()
	var profile_result: Dictionary = profile_loader.load_profile_result(profile_path)
	if not bool(profile_result.get("success", false)):
		return _failure("load_edge_contract_profile", profile_result.get("errors", []) as Array[String], {
			"location_node_results": location_node_results,
			"profile_path": profile_path,
		})
	var profile: RefCounted = profile_result.get("profile") as RefCounted
	var generation_result := _generate_edge_contracts(
		source_result.get("node_records", []) as Array,
		profile
	)
	if not bool(generation_result.get("success", false)):
		return _failure("generate_edge_contracts", generation_result.get("errors", []) as Array[String], {
			"location_node_results": location_node_results,
			"profile_path": profile_path,
		})
	var edge_contract_result := {
		"schema_version": SCHEMA_VERSION,
		"compiler_version": COMPILER_VERSION,
		"stage": "edge_contracts",
		"profile_id": profile.profile_id(),
		"profile_path": profile_path,
		"location_node_set_hash": _source_hash(location_node_results),
		"source_location_node_hashes": source_result.get("source_hashes", []),
		"edge_contracts": generation_result.get("edge_contracts", []),
	}
	var validator: RefCounted = EdgeContractResultValidatorScript.new()
	var validation_errors: Array[String] = validator.validate(edge_contract_result, location_node_results, profile)
	if not validation_errors.is_empty():
		return _failure("validate_edge_contract_result", validation_errors, {
			"location_node_results": location_node_results,
			"edge_contract_result": edge_contract_result,
			"profile_path": profile_path,
		})
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"edge_contract_result": edge_contract_result,
		"location_node_results": location_node_results.duplicate(true),
		"profile": profile,
	}


func _collect_source_nodes(location_node_results: Array) -> Dictionary:
	var errors: Array[String] = []
	var node_records: Array[Dictionary] = []
	var source_hashes: Array[Dictionary] = []
	var seen_location_ids: Dictionary = {}
	var seen_region_ids: Dictionary = {}
	for result_index in range(location_node_results.size()):
		if not (location_node_results[result_index] is Dictionary):
			errors.append("LocationNodeResult[%d] must be an object" % result_index)
			continue
		var result: Dictionary = location_node_results[result_index] as Dictionary
		var result_path := "LocationNodeResult[%d]" % result_index
		if str(result.get("stage", "")) != "location_nodes":
			errors.append("%s.stage must be location_nodes" % result_path)
		var region_id := str(result.get("region_id", ""))
		if region_id.is_empty():
			errors.append("%s.region_id is missing" % result_path)
		elif seen_region_ids.has(region_id):
			errors.append("LocationNodeResult collection contains duplicate region_id: %s" % region_id)
		seen_region_ids[region_id] = true
		if not (result.get("location_nodes", null) is Array):
			errors.append("%s.location_nodes must be an array" % result_path)
			continue
		var nodes: Array = result.get("location_nodes", []) as Array
		if nodes.is_empty():
			errors.append("%s.location_nodes must not be empty" % result_path)
		for node_index in range(nodes.size()):
			if not (nodes[node_index] is Dictionary):
				errors.append("%s.location_nodes[%d] must be an object" % [result_path, node_index])
				continue
			var node: Dictionary = nodes[node_index] as Dictionary
			var location_id := str(node.get("location_id", ""))
			if location_id.is_empty():
				errors.append("%s.location_nodes[%d].location_id is missing" % [result_path, node_index])
				continue
			if seen_location_ids.has(location_id):
				errors.append("LocationNodeResult collection contains duplicate location_id: %s" % location_id)
			seen_location_ids[location_id] = true
			for key in ["location_type", "source_role_id", "source_role_type"]:
				if str(node.get(key, "")).is_empty():
					errors.append("%s.location_nodes[%d].%s is missing" % [result_path, node_index, key])
			if not (node.get("node_tags", null) is Array):
				errors.append("%s.location_nodes[%d].node_tags must be an array" % [result_path, node_index])
			node_records.append({
				"location_id": location_id,
				"region_id": region_id,
				"node": node.duplicate(true),
			})
		source_hashes.append({
			"region_id": region_id,
			"location_node_result_hash": _source_hash(result),
		})
	node_records.sort_custom(_sort_node_records)
	source_hashes.sort_custom(_sort_source_hashes)
	if not errors.is_empty():
		return {
			"success": false,
			"errors": errors,
		}
	return {
		"success": true,
		"errors": [],
		"node_records": node_records,
		"source_hashes": source_hashes,
	}


func _generate_edge_contracts(node_records: Array, profile: RefCounted) -> Dictionary:
	var edge_contracts: Array[Dictionary] = []
	var pair_sources: Dictionary = {}
	for rule in profile.rules():
		var rule_id := str(rule.get("rule_id", ""))
		var from_nodes := _matching_nodes(node_records, rule.get("from_selector", {}) as Dictionary)
		var to_nodes := _matching_nodes(node_records, rule.get("to_selector", {}) as Dictionary)
		var activation := str(rule.get("activation", ""))
		if from_nodes.is_empty() and to_nodes.is_empty():
			continue
		if from_nodes.is_empty() or to_nodes.is_empty():
			if activation == "required":
				return _generation_failure(
					"required edge rule has no matching endpoint: %s (from=%d, to=%d)" % [
						rule_id,
						from_nodes.size(),
						to_nodes.size(),
					]
				)
			continue
		var pair_result := _pairs_for_rule(rule, from_nodes, to_nodes)
		if not bool(pair_result.get("success", false)):
			return pair_result
		for pair_value in (pair_result.get("pairs", []) as Array):
			var pair: Array = pair_value as Array
			var from_record: Dictionary = pair[0] as Dictionary
			var to_record: Dictionary = pair[1] as Dictionary
			var from_location_id := str(from_record.get("location_id", ""))
			var to_location_id := str(to_record.get("location_id", ""))
			if from_location_id == to_location_id:
				return _generation_failure("edge rule matched the same node at both endpoints: %s -> %s" % [rule_id, from_location_id])
			var pair_key := _unordered_pair_key(from_location_id, to_location_id)
			if pair_sources.has(pair_key):
				return _generation_failure("multiple edge rules generated the same endpoint pair: %s and %s" % [
					str(pair_sources.get(pair_key, "")),
					rule_id,
				])
			pair_sources[pair_key] = rule_id
			edge_contracts.append(_edge_from_pair(rule, from_record, to_record))
	return {
		"success": true,
		"errors": [],
		"edge_contracts": edge_contracts,
	}


func _pairs_for_rule(rule: Dictionary, from_nodes: Array[Dictionary], to_nodes: Array[Dictionary]) -> Dictionary:
	var rule_id := str(rule.get("rule_id", ""))
	var match_mode := str(rule.get("match_mode", ""))
	var pairs: Array[Array] = []
	match match_mode:
		"unique_pair":
			if from_nodes.size() != 1 or to_nodes.size() != 1:
				return _generation_failure("unique_pair edge rule is ambiguous: %s (from=%d, to=%d)" % [
					rule_id,
					from_nodes.size(),
					to_nodes.size(),
				])
			pairs.append([from_nodes[0], to_nodes[0]])
		"one_to_each":
			if from_nodes.size() != 1:
				return _generation_failure("one_to_each edge rule requires exactly one from endpoint: %s (from=%d)" % [
					rule_id,
					from_nodes.size(),
				])
			for to_record in to_nodes:
				pairs.append([from_nodes[0], to_record])
		"each_to_one":
			if to_nodes.size() != 1:
				return _generation_failure("each_to_one edge rule requires exactly one to endpoint: %s (to=%d)" % [
					rule_id,
					to_nodes.size(),
				])
			for from_record in from_nodes:
				pairs.append([from_record, to_nodes[0]])
		_:
			return _generation_failure("unsupported edge rule match_mode: %s" % match_mode)
	return {
		"success": true,
		"errors": [],
		"pairs": pairs,
	}


func _edge_from_pair(rule: Dictionary, from_record: Dictionary, to_record: Dictionary) -> Dictionary:
	var edge_spec: Dictionary = rule.get("edge", {}) as Dictionary
	var from_location_id := str(from_record.get("location_id", ""))
	var to_location_id := str(to_record.get("location_id", ""))
	var rule_id := str(rule.get("rule_id", ""))
	return {
		"edge_id": _edge_id(rule_id, from_location_id, to_location_id, bool(edge_spec.get("bidirectional", false))),
		"from_location_id": from_location_id,
		"to_location_id": to_location_id,
		"edge_type": str(edge_spec.get("edge_type", "")),
		"bidirectional": bool(edge_spec.get("bidirectional", false)),
		"access_rule": str(edge_spec.get("access_rule", "")),
		"traversal_tags": (edge_spec.get("traversal_tags", []) as Array).duplicate(),
		"source_rule_id": rule_id,
		"endpoint_region_relation": "same_region" if str(from_record.get("region_id", "")) == str(to_record.get("region_id", "")) else "cross_region",
		"validation_flags": (edge_spec.get("validation_flags", []) as Array).duplicate(),
	}


func _matching_nodes(node_records: Array, selector: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var location_types := _string_set(selector.get("location_types", []) as Array)
	var source_role_types := _string_set(selector.get("source_role_types", []) as Array)
	var required_tags := _string_set(selector.get("required_tags", []) as Array)
	var excluded_tags := _string_set(selector.get("excluded_tags", []) as Array)
	for record_value in node_records:
		var record: Dictionary = record_value as Dictionary
		var node: Dictionary = record.get("node", {}) as Dictionary
		if not location_types.is_empty() and not location_types.has(str(node.get("location_type", ""))):
			continue
		if not source_role_types.is_empty() and not source_role_types.has(str(node.get("source_role_type", ""))):
			continue
		var node_tags := _string_set(node.get("node_tags", []) as Array)
		if not _contains_all(node_tags, required_tags) or _contains_any(node_tags, excluded_tags):
			continue
		result.append(record)
	result.sort_custom(_sort_node_records)
	return result


func _edge_id(rule_id: String, from_location_id: String, to_location_id: String, bidirectional: bool) -> String:
	var endpoints := [from_location_id, to_location_id]
	if bidirectional:
		endpoints.sort()
	var identity := "%s:%s:%s:%s" % [rule_id, endpoints[0], endpoints[1], str(bidirectional)]
	return "edge.%s.ec_%010d" % [rule_id, _stable_text_hash(identity)]


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result


func _generation_failure(error: String) -> Dictionary:
	var errors: Array[String] = [error]
	return {
		"success": false,
		"errors": errors,
	}


static func _sort_node_records(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("location_id", "")) < str(b.get("location_id", ""))


static func _sort_source_hashes(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("region_id", "")) < str(b.get("region_id", ""))


static func _unordered_pair_key(first: String, second: String) -> String:
	var endpoints := [first, second]
	endpoints.sort()
	return "%s::%s" % [endpoints[0], endpoints[1]]


static func _string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[str(value)] = true
	return result


static func _contains_all(values: Dictionary, required: Dictionary) -> bool:
	for key in required.keys():
		if not values.has(key):
			return false
	return true


static func _contains_any(values: Dictionary, excluded: Dictionary) -> bool:
	for key in excluded.keys():
		if values.has(key):
			return true
	return false


static func _source_hash(data: Variant) -> String:
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
