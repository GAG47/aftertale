class_name EdgeContractResultValidator
extends RefCounted

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")

const SCHEMA_VERSION := 1
const RESULT_KEYS := {
	"schema_version": true,
	"compiler_version": true,
	"stage": true,
	"profile_id": true,
	"profile_path": true,
	"location_node_set_hash": true,
	"source_location_node_hashes": true,
	"edge_contracts": true,
	"result_hash": true,
}
const SOURCE_HASH_KEYS := {
	"region_id": true,
	"location_node_result_hash": true,
}
const EDGE_KEYS := {
	"edge_id": true,
	"from_location_id": true,
	"to_location_id": true,
	"edge_type": true,
	"bidirectional": true,
	"access_rule": true,
	"traversal_tags": true,
	"source_rule_id": true,
	"endpoint_region_relation": true,
	"validation_flags": true,
}


func validate(result: Dictionary, location_node_results: Array, profile: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	if result.is_empty():
		errors.append("EdgeContractResult is empty")
		return errors
	_validate_known_keys(result, RESULT_KEYS, "EdgeContractResult", errors)
	if int(result.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("EdgeContractResult.schema_version is unsupported: %s" % str(result.get("schema_version", "")))
	if str(result.get("stage", "")) != "edge_contracts":
		errors.append("EdgeContractResult.stage must be edge_contracts")
	for key in ["compiler_version", "profile_id", "profile_path", "location_node_set_hash", "result_hash"]:
		if str(result.get(key, "")).is_empty():
			errors.append("EdgeContractResult.%s is missing" % key)
	var declared_result_hash := str(result.get("result_hash", ""))
	var calculated_result_hash: String = CanonicalDataSerializerScript.edge_contract_result_hash(result)
	if declared_result_hash.is_empty() or calculated_result_hash.is_empty() or declared_result_hash != calculated_result_hash:
		errors.append("EdgeContractResult.result_hash does not match canonical content")
	if profile == null:
		errors.append("EdgeContractProfile is required")
	elif str(result.get("profile_id", "")) != profile.profile_id():
		errors.append("EdgeContractResult.profile_id does not match EdgeContractProfile")
	var source_result := _collect_source_nodes(location_node_results, errors)
	var node_records: Array = source_result.get("node_records", []) as Array
	var nodes_by_id: Dictionary = source_result.get("nodes_by_id", {}) as Dictionary
	_validate_source_hashes(result, location_node_results, errors)
	if str(result.get("location_node_set_hash", "")) != CanonicalDataSerializerScript.location_node_result_set_hash(location_node_results):
		errors.append("EdgeContractResult.location_node_set_hash does not match LocationNodeResult inputs")
	if not (result.get("edge_contracts", null) is Array):
		errors.append("EdgeContractResult.edge_contracts must be an array")
		return errors
	if profile == null:
		return errors
	var expected_result := _expected_edges(profile, node_records)
	errors.append_array(expected_result.get("errors", []) as Array[String])
	var expected_edges: Dictionary = expected_result.get("expected_edges", {}) as Dictionary
	_validate_edges(result.get("edge_contracts", []) as Array, nodes_by_id, expected_edges, profile, errors)
	return errors


func _collect_source_nodes(location_node_results: Array, errors: Array[String]) -> Dictionary:
	var node_records: Array[Dictionary] = []
	var nodes_by_id: Dictionary = {}
	var seen_region_ids: Dictionary = {}
	if location_node_results.is_empty():
		errors.append("At least one LocationNodeResult is required")
	for result_index in range(location_node_results.size()):
		if not (location_node_results[result_index] is Dictionary):
			errors.append("LocationNodeResult[%d] must be an object" % result_index)
			continue
		var source: Dictionary = location_node_results[result_index] as Dictionary
		var path := "LocationNodeResult[%d]" % result_index
		if str(source.get("stage", "")) != "location_nodes":
			errors.append("%s.stage must be location_nodes" % path)
		var region_id := str(source.get("region_id", ""))
		if region_id.is_empty():
			errors.append("%s.region_id is missing" % path)
		elif seen_region_ids.has(region_id):
			errors.append("LocationNodeResult collection contains duplicate region_id: %s" % region_id)
		seen_region_ids[region_id] = true
		if not (source.get("location_nodes", null) is Array):
			errors.append("%s.location_nodes must be an array" % path)
			continue
		for node_index in range((source.get("location_nodes", []) as Array).size()):
			var value: Variant = (source.get("location_nodes", []) as Array)[node_index]
			if not (value is Dictionary):
				errors.append("%s.location_nodes[%d] must be an object" % [path, node_index])
				continue
			var node: Dictionary = value as Dictionary
			var location_id := str(node.get("location_id", ""))
			if location_id.is_empty():
				errors.append("%s.location_nodes[%d].location_id is missing" % [path, node_index])
				continue
			if nodes_by_id.has(location_id):
				errors.append("LocationNodeResult collection contains duplicate location_id: %s" % location_id)
			var record := {
				"location_id": location_id,
				"region_id": region_id,
				"node": node,
			}
			nodes_by_id[location_id] = record
			node_records.append(record)
	node_records.sort_custom(_sort_node_records)
	return {
		"node_records": node_records,
		"nodes_by_id": nodes_by_id,
	}


func _validate_source_hashes(result: Dictionary, location_node_results: Array, errors: Array[String]) -> void:
	if not (result.get("source_location_node_hashes", null) is Array):
		errors.append("EdgeContractResult.source_location_node_hashes must be an array")
		return
	var expected: Array[Dictionary] = []
	for value in location_node_results:
		if not (value is Dictionary):
			continue
		var source: Dictionary = value as Dictionary
		expected.append({
			"region_id": str(source.get("region_id", "")),
			"location_node_result_hash": str(source.get("result_hash", "")),
		})
	expected.sort_custom(_sort_source_hashes)
	var actual: Array = result.get("source_location_node_hashes", []) as Array
	for index in range(actual.size()):
		if not (actual[index] is Dictionary):
			errors.append("EdgeContractResult.source_location_node_hashes[%d] must be an object" % index)
			continue
		_validate_known_keys(actual[index] as Dictionary, SOURCE_HASH_KEYS, "EdgeContractResult.source_location_node_hashes[%d]" % index, errors)
	if CanonicalDataSerializerScript.serialize(actual) != CanonicalDataSerializerScript.serialize(expected):
		errors.append("EdgeContractResult.source_location_node_hashes do not match LocationNodeResult inputs")


func _expected_edges(profile: RefCounted, node_records: Array) -> Dictionary:
	var errors: Array[String] = []
	var expected_edges: Dictionary = {}
	var seen_pairs: Dictionary = {}
	for rule in profile.rules():
		var rule_id := str(rule.get("rule_id", ""))
		var from_nodes := _matching_nodes(node_records, rule.get("from_selector", {}) as Dictionary)
		var to_nodes := _matching_nodes(node_records, rule.get("to_selector", {}) as Dictionary)
		if from_nodes.is_empty() and to_nodes.is_empty():
			continue
		if from_nodes.is_empty() or to_nodes.is_empty():
			if str(rule.get("activation", "")) == "required":
				errors.append("required edge rule has no matching endpoint: %s (from=%d, to=%d)" % [
					rule_id,
					from_nodes.size(),
					to_nodes.size(),
				])
			continue
		var pairs := _pairs_for_rule(rule, from_nodes, to_nodes, errors)
		var edge_spec: Dictionary = rule.get("edge", {}) as Dictionary
		for pair_value in pairs:
			var pair: Array = pair_value as Array
			var from_record: Dictionary = pair[0] as Dictionary
			var to_record: Dictionary = pair[1] as Dictionary
			var from_id := str(from_record.get("location_id", ""))
			var to_id := str(to_record.get("location_id", ""))
			if from_id == to_id:
				errors.append("edge rule matched the same node at both endpoints: %s -> %s" % [rule_id, from_id])
				continue
			var pair_key := _unordered_pair_key(from_id, to_id)
			if seen_pairs.has(pair_key):
				errors.append("multiple edge rules generated the same endpoint pair: %s and %s" % [
					str(seen_pairs.get(pair_key, "")),
					rule_id,
				])
				continue
			seen_pairs[pair_key] = rule_id
			var expected_key := _expected_edge_key(rule_id, from_id, to_id)
			expected_edges[expected_key] = {
				"edge_id": _edge_id(rule_id, from_id, to_id, bool(edge_spec.get("bidirectional", false))),
				"from_location_id": from_id,
				"to_location_id": to_id,
				"edge_type": str(edge_spec.get("edge_type", "")),
				"bidirectional": bool(edge_spec.get("bidirectional", false)),
				"access_rule": str(edge_spec.get("access_rule", "")),
				"traversal_tags": (edge_spec.get("traversal_tags", []) as Array).duplicate(),
				"source_rule_id": rule_id,
				"endpoint_region_relation": "same_region" if str(from_record.get("region_id", "")) == str(to_record.get("region_id", "")) else "cross_region",
				"validation_flags": (edge_spec.get("validation_flags", []) as Array).duplicate(),
			}
	return {
		"errors": errors,
		"expected_edges": expected_edges,
	}


func _pairs_for_rule(rule: Dictionary, from_nodes: Array[Dictionary], to_nodes: Array[Dictionary], errors: Array[String]) -> Array[Array]:
	var pairs: Array[Array] = []
	var rule_id := str(rule.get("rule_id", ""))
	match str(rule.get("match_mode", "")):
		"unique_pair":
			if from_nodes.size() != 1 or to_nodes.size() != 1:
				errors.append("unique_pair edge rule is ambiguous: %s (from=%d, to=%d)" % [
					rule_id,
					from_nodes.size(),
					to_nodes.size(),
				])
			else:
				pairs.append([from_nodes[0], to_nodes[0]])
		"one_to_each":
			if from_nodes.size() != 1:
				errors.append("one_to_each edge rule requires exactly one from endpoint: %s (from=%d)" % [rule_id, from_nodes.size()])
			else:
				for to_record in to_nodes:
					pairs.append([from_nodes[0], to_record])
		"each_to_one":
			if to_nodes.size() != 1:
				errors.append("each_to_one edge rule requires exactly one to endpoint: %s (to=%d)" % [rule_id, to_nodes.size()])
			else:
				for from_record in from_nodes:
					pairs.append([from_record, to_nodes[0]])
	return pairs


func _validate_edges(edges: Array, nodes_by_id: Dictionary, expected_edges: Dictionary, profile: RefCounted, errors: Array[String]) -> void:
	var edge_ids: Dictionary = {}
	var pair_keys: Dictionary = {}
	var actual_expected_keys: Dictionary = {}
	for index in range(edges.size()):
		if not (edges[index] is Dictionary):
			errors.append("EdgeContractResult.edge_contracts[%d] must be an object" % index)
			continue
		var edge: Dictionary = edges[index] as Dictionary
		var path := "EdgeContractResult.edge_contracts[%d]" % index
		_validate_known_keys(edge, EDGE_KEYS, path, errors)
		var edge_id := str(edge.get("edge_id", ""))
		var from_id := str(edge.get("from_location_id", ""))
		var to_id := str(edge.get("to_location_id", ""))
		var rule_id := str(edge.get("source_rule_id", ""))
		if edge_id.is_empty():
			errors.append("%s.edge_id is missing" % path)
		elif edge_ids.has(edge_id):
			errors.append("EdgeContractResult contains duplicate edge_id: %s" % edge_id)
		edge_ids[edge_id] = true
		if from_id == to_id:
			errors.append("%s must not connect a node to itself" % path)
		if not nodes_by_id.has(from_id):
			errors.append("%s.from_location_id references an unknown node: %s" % [path, from_id])
		if not nodes_by_id.has(to_id):
			errors.append("%s.to_location_id references an unknown node: %s" % [path, to_id])
		var pair_key := _unordered_pair_key(from_id, to_id)
		if pair_keys.has(pair_key):
			errors.append("EdgeContractResult contains duplicate endpoint pair: %s" % pair_key)
		pair_keys[pair_key] = true
		if not profile.supports_edge_type(str(edge.get("edge_type", ""))):
			errors.append("%s.edge_type is unsupported: %s" % [path, str(edge.get("edge_type", ""))])
		if not (edge.get("bidirectional", null) is bool):
			errors.append("%s.bidirectional must be a boolean" % path)
		if not profile.supports_access_rule(str(edge.get("access_rule", ""))):
			errors.append("%s.access_rule is unsupported: %s" % [path, str(edge.get("access_rule", ""))])
		_validate_string_array(edge.get("traversal_tags"), "%s.traversal_tags" % path, errors)
		for tag_value in (edge.get("traversal_tags", []) as Array):
			if not profile.supports_traversal_tag(str(tag_value)):
				errors.append("%s.traversal_tags contains an unsupported tag: %s" % [path, str(tag_value)])
		_validate_string_array(edge.get("validation_flags"), "%s.validation_flags" % path, errors)
		for flag_value in (edge.get("validation_flags", []) as Array):
			if not profile.supports_validation_flag(str(flag_value)):
				errors.append("%s.validation_flags contains an unsupported flag: %s" % [path, str(flag_value)])
		if profile.rule(rule_id).is_empty():
			errors.append("%s.source_rule_id references an unknown rule: %s" % [path, rule_id])
		var expected_key := _expected_edge_key(rule_id, from_id, to_id)
		actual_expected_keys[expected_key] = true
		if not expected_edges.has(expected_key):
			errors.append("%s does not match an edge required by its source rule" % path)
			continue
		var expected: Dictionary = expected_edges.get(expected_key, {}) as Dictionary
		if _canonical_edge_text(edge) != _canonical_edge_text(expected):
			errors.append("%s does not match its source rule output" % path)
	for expected_key_value in expected_edges.keys():
		var expected_key := str(expected_key_value)
		if not actual_expected_keys.has(expected_key):
			errors.append("EdgeContractResult is missing profile-generated edge: %s" % expected_key)


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


static func _validate_known_keys(data: Dictionary, allowed: Dictionary, path: String, errors: Array[String]) -> void:
	for key_value in data.keys():
		var key := str(key_value)
		if not allowed.has(key):
			errors.append("%s contains unsupported field: %s" % [path, key])


static func _validate_string_array(value: Variant, path: String, errors: Array[String]) -> void:
	if not (value is Array):
		errors.append("%s must be an array" % path)
		return
	var seen: Dictionary = {}
	for item in (value as Array):
		var text := str(item)
		if not _is_system_token(text) or seen.has(text):
			errors.append("%s must contain unique lowercase system tokens" % path)
			return
		seen[text] = true


static func _sort_node_records(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("location_id", "")) < str(b.get("location_id", ""))


static func _sort_source_hashes(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("region_id", "")) < str(b.get("region_id", ""))


static func _expected_edge_key(rule_id: String, from_id: String, to_id: String) -> String:
	return "%s::%s::%s" % [rule_id, from_id, to_id]


static func _unordered_pair_key(first: String, second: String) -> String:
	var endpoints := [first, second]
	endpoints.sort()
	return "%s::%s" % [endpoints[0], endpoints[1]]


static func _edge_id(rule_id: String, from_id: String, to_id: String, bidirectional: bool) -> String:
	var endpoints := [from_id, to_id]
	if bidirectional:
		endpoints.sort()
	var identity := "%s:%s:%s:%s" % [rule_id, endpoints[0], endpoints[1], str(bidirectional)]
	return "edge.%s.ec_%010d" % [rule_id, _stable_text_hash(identity)]


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


static func _stable_text_hash(text: String) -> int:
	var value := 2166136261
	for index in range(text.length()):
		value = int((value ^ text.unicode_at(index)) * 16777619) % 2147483647
	return abs(value)
static func _canonical_edge_text(edge: Dictionary) -> String:
	var wrapper := {
		"edge_contracts": [edge],
	}
	var normalized: Dictionary = CanonicalDataSerializerScript.normalize_edge_contract_result(wrapper)
	var edges: Array = normalized.get("edge_contracts", []) as Array
	if edges.is_empty():
		return ""
	return CanonicalDataSerializerScript.serialize(edges[0])


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
