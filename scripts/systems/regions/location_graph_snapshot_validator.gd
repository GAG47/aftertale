class_name LocationGraphSnapshotValidator
extends RefCounted

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")

const SCHEMA_VERSION := 2
const COMPILER_VERSION := "v67.8"
const SNAPSHOT_KEYS := {
	"schema_version": true,
	"compiler_version": true,
	"stage": true,
	"graph_id": true,
	"snapshot_id": true,
	"content_hash": true,
	"location_nodes": true,
	"edge_contracts": true,
	"node_sources": true,
	"source_manifest": true,
	"rule_manifest": true,
}
const NODE_KEYS := {
	"location_id": true,
	"location_type": true,
	"node_slug": true,
	"source_role_id": true,
	"source_role_type": true,
	"source_role_slug": true,
	"node_source": true,
	"node_tags": true,
	"is_boundary": true,
	"is_hidden": true,
	"is_required": true,
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
const NODE_SOURCE_KEYS := {
	"location_id": true,
	"source_region_id": true,
	"location_node_result_hash": true,
}
const SOURCE_MANIFEST_KEYS := {
	"source_kind": true,
	"source_id": true,
	"result_hash": true,
}
const RULE_MANIFEST_KEYS := {
	"profile_kind": true,
	"profile_path": true,
	"profile_content_hash": true,
}
const PROFILE_KINDS := [
	"semantic_role_library",
	"semantic_role_profile",
	"location_node_profile",
	"edge_contract_profile",
]


func validate(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if snapshot.is_empty():
		errors.append("LocationGraphSnapshot is empty")
		return errors
	errors.append_array(CanonicalDataSerializerScript.validate_value(snapshot))
	_validate_known_keys(snapshot, SNAPSHOT_KEYS, "LocationGraphSnapshot", errors)
	if not _is_integer_like(snapshot.get("schema_version")) or int(snapshot.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("LocationGraphSnapshot.schema_version is unsupported: %s" % str(snapshot.get("schema_version", "")))
	if str(snapshot.get("compiler_version", "")) != COMPILER_VERSION:
		errors.append("LocationGraphSnapshot.compiler_version is incompatible: %s" % str(snapshot.get("compiler_version", "")))
	if str(snapshot.get("stage", "")) != "location_graph_snapshot":
		errors.append("LocationGraphSnapshot.stage must be location_graph_snapshot")
	var graph_id := str(snapshot.get("graph_id", ""))
	if not _is_graph_id(graph_id):
		errors.append("LocationGraphSnapshot.graph_id is invalid: %s" % graph_id)
	for key in ["snapshot_id", "content_hash"]:
		if str(snapshot.get(key, "")).is_empty():
			errors.append("LocationGraphSnapshot.%s is missing" % key)
	for key in ["location_nodes", "edge_contracts", "node_sources", "source_manifest", "rule_manifest"]:
		if not (snapshot.get(key, null) is Array):
			errors.append("LocationGraphSnapshot.%s must be an array" % key)
	if not errors.is_empty():
		return errors
	if not CanonicalDataSerializerScript.snapshot_collections_are_canonical(snapshot):
		errors.append("LocationGraphSnapshot is not in canonical collection order")
	var calculated_content_hash: String = CanonicalDataSerializerScript.snapshot_content_hash(snapshot)
	if str(snapshot.get("content_hash", "")) != calculated_content_hash:
		errors.append("LocationGraphSnapshot.content_hash does not match canonical content")
	var calculated_snapshot_id: String = CanonicalDataSerializerScript.snapshot_id(graph_id, calculated_content_hash)
	if str(snapshot.get("snapshot_id", "")) != calculated_snapshot_id:
		errors.append("LocationGraphSnapshot.snapshot_id does not match graph_id and content_hash")
	var nodes_by_id := _validate_nodes(snapshot.get("location_nodes", []) as Array, errors)
	var sources_by_location := _validate_node_sources(
		snapshot.get("node_sources", []) as Array,
		nodes_by_id,
		errors
	)
	var source_manifest := _validate_source_manifest(snapshot.get("source_manifest", []) as Array, errors)
	_validate_node_source_manifest_links(sources_by_location, source_manifest, errors)
	_validate_rule_manifest(snapshot.get("rule_manifest", []) as Array, errors)
	_validate_edges(snapshot.get("edge_contracts", []) as Array, nodes_by_id, sources_by_location, errors)
	return errors


func _validate_nodes(nodes: Array, errors: Array[String]) -> Dictionary:
	var nodes_by_id: Dictionary = {}
	for index in range(nodes.size()):
		var path := "LocationGraphSnapshot.location_nodes[%d]" % index
		if not (nodes[index] is Dictionary):
			errors.append("%s must be an object" % path)
			continue
		var node: Dictionary = nodes[index] as Dictionary
		_validate_known_keys(node, NODE_KEYS, path, errors)
		for key in ["location_id", "location_type", "node_slug", "source_role_id", "source_role_type", "node_source"]:
			if str(node.get(key, "")).is_empty():
				errors.append("%s.%s is missing" % [path, key])
		var location_id := str(node.get("location_id", ""))
		if nodes_by_id.has(location_id):
			errors.append("LocationGraphSnapshot contains duplicate location_id: %s" % location_id)
		nodes_by_id[location_id] = node
		_validate_string_array(node.get("node_tags"), "%s.node_tags" % path, errors)
		for key in ["is_boundary", "is_hidden", "is_required"]:
			if not (node.get(key, null) is bool):
				errors.append("%s.%s must be a boolean" % [path, key])
	return nodes_by_id


func _validate_node_sources(node_sources: Array, nodes_by_id: Dictionary, errors: Array[String]) -> Dictionary:
	var sources_by_location: Dictionary = {}
	for index in range(node_sources.size()):
		var path := "LocationGraphSnapshot.node_sources[%d]" % index
		if not (node_sources[index] is Dictionary):
			errors.append("%s must be an object" % path)
			continue
		var source: Dictionary = node_sources[index] as Dictionary
		_validate_known_keys(source, NODE_SOURCE_KEYS, path, errors)
		var location_id := str(source.get("location_id", ""))
		var region_id := str(source.get("source_region_id", ""))
		var result_hash := str(source.get("location_node_result_hash", ""))
		if not nodes_by_id.has(location_id):
			errors.append("%s.location_id references an unknown node: %s" % [path, location_id])
		if sources_by_location.has(location_id):
			errors.append("LocationGraphSnapshot contains duplicate node source: %s" % location_id)
		if region_id.is_empty():
			errors.append("%s.source_region_id is missing" % path)
		if not CanonicalDataSerializerScript.is_sha256_hash(result_hash):
			errors.append("%s.location_node_result_hash is invalid" % path)
		sources_by_location[location_id] = source
	for location_id_value in nodes_by_id.keys():
		var location_id := str(location_id_value)
		if not sources_by_location.has(location_id):
			errors.append("LocationGraphSnapshot is missing node source for location_id: %s" % location_id)
	return sources_by_location


func _validate_source_manifest(values: Array, errors: Array[String]) -> Dictionary:
	var by_key: Dictionary = {}
	var edge_source_count := 0
	for index in range(values.size()):
		var path := "LocationGraphSnapshot.source_manifest[%d]" % index
		if not (values[index] is Dictionary):
			errors.append("%s must be an object" % path)
			continue
		var row: Dictionary = values[index] as Dictionary
		_validate_known_keys(row, SOURCE_MANIFEST_KEYS, path, errors)
		var source_kind := str(row.get("source_kind", ""))
		var source_id := str(row.get("source_id", ""))
		var result_hash := str(row.get("result_hash", ""))
		if source_kind != "location_node_result" and source_kind != "edge_contract_result":
			errors.append("%s.source_kind is unsupported: %s" % [path, source_kind])
		if source_id.is_empty():
			errors.append("%s.source_id is missing" % path)
		if not CanonicalDataSerializerScript.is_sha256_hash(result_hash):
			errors.append("%s.result_hash is invalid" % path)
		var key := "%s::%s" % [source_kind, source_id]
		if by_key.has(key):
			errors.append("LocationGraphSnapshot contains duplicate source manifest row: %s" % key)
		by_key[key] = row
		if source_kind == "edge_contract_result":
			edge_source_count += 1
	if edge_source_count != 1:
		errors.append("LocationGraphSnapshot.source_manifest must contain exactly one EdgeContractResult")
	return by_key


func _validate_node_source_manifest_links(node_sources: Dictionary, source_manifest: Dictionary, errors: Array[String]) -> void:
	for source_value in node_sources.values():
		var source: Dictionary = source_value as Dictionary
		var manifest_key := "location_node_result::%s" % str(source.get("source_region_id", ""))
		if not source_manifest.has(manifest_key):
			errors.append("LocationGraphSnapshot node source has no LocationNodeResult manifest: %s" % manifest_key)
			continue
		var manifest: Dictionary = source_manifest.get(manifest_key, {}) as Dictionary
		if str(source.get("location_node_result_hash", "")) != str(manifest.get("result_hash", "")):
			errors.append("LocationGraphSnapshot node source hash does not match source manifest: %s" % str(source.get("location_id", "")))


func _validate_rule_manifest(values: Array, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	var kinds_seen: Dictionary = {}
	var kind_counts: Dictionary = {}
	for index in range(values.size()):
		var path := "LocationGraphSnapshot.rule_manifest[%d]" % index
		if not (values[index] is Dictionary):
			errors.append("%s must be an object" % path)
			continue
		var row: Dictionary = values[index] as Dictionary
		_validate_known_keys(row, RULE_MANIFEST_KEYS, path, errors)
		var profile_kind := str(row.get("profile_kind", ""))
		var profile_path := str(row.get("profile_path", ""))
		var profile_hash := str(row.get("profile_content_hash", ""))
		if not PROFILE_KINDS.has(profile_kind):
			errors.append("%s.profile_kind is unsupported: %s" % [path, profile_kind])
		if profile_path.is_empty():
			errors.append("%s.profile_path is missing" % path)
		if not CanonicalDataSerializerScript.is_sha256_hash(profile_hash):
			errors.append("%s.profile_content_hash is invalid" % path)
		var key := "%s::%s" % [profile_kind, profile_path]
		if seen.has(key):
			errors.append("LocationGraphSnapshot contains duplicate rule manifest row: %s" % key)
		seen[key] = true
		kinds_seen[profile_kind] = true
		kind_counts[profile_kind] = int(kind_counts.get(profile_kind, 0)) + 1
	for required_kind in PROFILE_KINDS:
		if not kinds_seen.has(required_kind):
			errors.append("LocationGraphSnapshot.rule_manifest is missing profile kind: %s" % required_kind)
	if int(kind_counts.get("semantic_role_library", 0)) != 1:
		errors.append("LocationGraphSnapshot.rule_manifest must contain exactly one semantic_role_library")


func _validate_edges(edges: Array, nodes_by_id: Dictionary, sources_by_location: Dictionary, errors: Array[String]) -> void:
	var edge_ids: Dictionary = {}
	var endpoint_pairs: Dictionary = {}
	for index in range(edges.size()):
		var path := "LocationGraphSnapshot.edge_contracts[%d]" % index
		if not (edges[index] is Dictionary):
			errors.append("%s must be an object" % path)
			continue
		var edge: Dictionary = edges[index] as Dictionary
		_validate_known_keys(edge, EDGE_KEYS, path, errors)
		var edge_id := str(edge.get("edge_id", ""))
		var from_id := str(edge.get("from_location_id", ""))
		var to_id := str(edge.get("to_location_id", ""))
		if edge_id.is_empty():
			errors.append("%s.edge_id is missing" % path)
		elif edge_ids.has(edge_id):
			errors.append("LocationGraphSnapshot contains duplicate edge_id: %s" % edge_id)
		edge_ids[edge_id] = true
		if not nodes_by_id.has(from_id):
			errors.append("%s.from_location_id references an unknown node: %s" % [path, from_id])
		if not nodes_by_id.has(to_id):
			errors.append("%s.to_location_id references an unknown node: %s" % [path, to_id])
		if from_id == to_id:
			errors.append("%s must not connect a node to itself" % path)
		var pair_key := _unordered_pair_key(from_id, to_id)
		if endpoint_pairs.has(pair_key):
			errors.append("LocationGraphSnapshot contains duplicate endpoint pair: %s" % pair_key)
		endpoint_pairs[pair_key] = true
		for key in ["edge_type", "access_rule", "source_rule_id"]:
			if not _is_system_token(str(edge.get(key, ""))):
				errors.append("%s.%s must be a lowercase system token" % [path, key])
		if not (edge.get("bidirectional", null) is bool):
			errors.append("%s.bidirectional must be a boolean" % path)
		_validate_string_array(edge.get("traversal_tags"), "%s.traversal_tags" % path, errors)
		_validate_string_array(edge.get("validation_flags"), "%s.validation_flags" % path, errors)
		if sources_by_location.has(from_id) and sources_by_location.has(to_id):
			var from_source: Dictionary = sources_by_location.get(from_id, {}) as Dictionary
			var to_source: Dictionary = sources_by_location.get(to_id, {}) as Dictionary
			var expected_relation := "same_region" if str(from_source.get("source_region_id", "")) == str(to_source.get("source_region_id", "")) else "cross_region"
			if str(edge.get("endpoint_region_relation", "")) != expected_relation:
				errors.append("%s.endpoint_region_relation does not match node sources" % path)


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


static func _unordered_pair_key(first: String, second: String) -> String:
	var endpoints := [first, second]
	endpoints.sort()
	return "%s::%s" % [endpoints[0], endpoints[1]]


static func _is_graph_id(value: String) -> bool:
	var segments := value.split(".")
	if segments.size() < 4 or str(segments[0]) != "graph":
		return false
	for index in range(1, segments.size()):
		if not _is_system_token(str(segments[index])):
			return false
	return str(segments[segments.size() - 1]).begins_with("lg_")


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


static func _is_integer_like(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and is_equal_approx(float(value), float(int(value)))
	return false
