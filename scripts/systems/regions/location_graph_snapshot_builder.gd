class_name LocationGraphSnapshotBuilder
extends RefCounted

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const EdgeContractProfileScript := preload("res://scripts/systems/regions/edge_contract_profile.gd")
const EdgeContractResultValidatorScript := preload("res://scripts/systems/regions/edge_contract_result_validator.gd")
const LocationNodeProfileScript := preload("res://scripts/systems/regions/location_node_profile.gd")
const LocationGraphSnapshotValidatorScript := preload("res://scripts/systems/regions/location_graph_snapshot_validator.gd")
const RegionTypeProfileScript := preload("res://scripts/systems/regions/region_type_profile.gd")
const SemanticRoleLibraryScript := preload("res://scripts/systems/regions/semantic_role_library.gd")

const SCHEMA_VERSION := 3
const COMPILER_VERSION := "v67.8"


func build_snapshot_result(graph_id: String, location_node_results: Array, edge_contract_result: Dictionary) -> Dictionary:
	var input_errors := _validate_inputs(graph_id, location_node_results, edge_contract_result)
	if not input_errors.is_empty():
		return _failure("validate_snapshot_inputs", input_errors, {})
	var edge_profile_path := str(edge_contract_result.get("profile_path", ""))
	var profile_load: Dictionary = EdgeContractProfileScript.new().load_profile_result(edge_profile_path)
	if not bool(profile_load.get("success", false)):
		return _failure("load_edge_contract_profile", profile_load.get("errors", []) as Array[String], {
			"profile_path": edge_profile_path,
		})
	var edge_validator: RefCounted = EdgeContractResultValidatorScript.new()
	var edge_errors: Array[String] = edge_validator.validate(
		edge_contract_result,
		location_node_results,
		profile_load.get("profile") as RefCounted
	)
	if not edge_errors.is_empty():
		return _failure("revalidate_edge_contract_result", edge_errors, {})
	var rule_manifest_result := _build_rule_manifest(location_node_results, edge_contract_result)
	if not bool(rule_manifest_result.get("success", false)):
		return _failure("build_rule_manifest", rule_manifest_result.get("errors", []) as Array[String], {})
	var flattened := _flatten_nodes(location_node_results)
	if not bool(flattened.get("success", false)):
		return _failure("flatten_location_nodes", flattened.get("errors", []) as Array[String], {})
	var normalized_edge_result: Dictionary = CanonicalDataSerializerScript.normalize_edge_contract_result(edge_contract_result)
	var snapshot := {
		"schema_version": SCHEMA_VERSION,
		"compiler_version": COMPILER_VERSION,
		"stage": "location_graph_snapshot",
		"graph_id": graph_id,
		"snapshot_id": "",
		"content_hash": "",
		"location_nodes": flattened.get("location_nodes", []),
		"edge_contracts": normalized_edge_result.get("edge_contracts", []),
		"node_sources": flattened.get("node_sources", []),
		"source_manifest": _build_source_manifest(location_node_results, edge_contract_result),
		"rule_manifest": rule_manifest_result.get("rule_manifest", []),
	}
	snapshot = CanonicalDataSerializerScript.normalize_snapshot(snapshot)
	snapshot["content_hash"] = CanonicalDataSerializerScript.snapshot_content_hash(snapshot)
	snapshot["snapshot_id"] = CanonicalDataSerializerScript.snapshot_id(graph_id, str(snapshot.get("content_hash", "")))
	if str(snapshot.get("content_hash", "")).is_empty() or str(snapshot.get("snapshot_id", "")).is_empty():
		return _failure("hash_location_graph_snapshot", ["LocationGraphSnapshot could not be canonically hashed"], {
			"location_graph_snapshot": snapshot,
		})
	var validator: RefCounted = LocationGraphSnapshotValidatorScript.new()
	var snapshot_errors: Array[String] = validator.validate(snapshot)
	if not snapshot_errors.is_empty():
		return _failure("validate_location_graph_snapshot", snapshot_errors, {
			"location_graph_snapshot": snapshot,
		})
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"location_graph_snapshot": snapshot,
	}


func _validate_inputs(graph_id: String, location_node_results: Array, edge_contract_result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var role_library_identity := ""
	if not _is_graph_id(graph_id):
		errors.append("graph_id is invalid: %s" % graph_id)
	if location_node_results.is_empty():
		errors.append("At least one LocationNodeResult is required")
	for index in range(location_node_results.size()):
		if not (location_node_results[index] is Dictionary):
			errors.append("LocationNodeResult[%d] must be an object" % index)
			continue
		var result: Dictionary = location_node_results[index] as Dictionary
		var declared_hash := str(result.get("result_hash", ""))
		var calculated_hash: String = CanonicalDataSerializerScript.location_node_result_hash(result)
		if declared_hash.is_empty() or calculated_hash.is_empty() or declared_hash != calculated_hash:
			errors.append("LocationNodeResult[%d].result_hash does not match canonical content" % index)
		for key in ["profile_path", "semantic_role_profile_path", "semantic_role_library_id", "semantic_role_library_path"]:
			if str(result.get(key, "")).is_empty():
				errors.append("LocationNodeResult[%d].%s is missing" % [index, key])
		var role_library_hash := str(result.get("semantic_role_library_content_hash", ""))
		if not CanonicalDataSerializerScript.is_sha256_hash(role_library_hash):
			errors.append("LocationNodeResult[%d].semantic_role_library_content_hash is invalid" % index)
		var current_library_identity := "%s::%s::%s" % [
			str(result.get("semantic_role_library_id", "")),
			str(result.get("semantic_role_library_path", "")),
			role_library_hash,
		]
		if role_library_identity.is_empty():
			role_library_identity = current_library_identity
		elif current_library_identity != role_library_identity:
			errors.append("LocationNodeResult inputs reference different SemanticRoleLibrary sources")
	if edge_contract_result.is_empty():
		errors.append("EdgeContractResult is required")
	else:
		var declared_edge_hash := str(edge_contract_result.get("result_hash", ""))
		var calculated_edge_hash: String = CanonicalDataSerializerScript.edge_contract_result_hash(edge_contract_result)
		if declared_edge_hash.is_empty() or calculated_edge_hash.is_empty() or declared_edge_hash != calculated_edge_hash:
			errors.append("EdgeContractResult.result_hash does not match canonical content")
		var expected_node_set_hash: String = CanonicalDataSerializerScript.location_node_result_set_hash(location_node_results)
		if str(edge_contract_result.get("location_node_set_hash", "")) != expected_node_set_hash:
			errors.append("EdgeContractResult.location_node_set_hash does not match LocationNodeResult inputs")
		if str(edge_contract_result.get("profile_path", "")).is_empty():
			errors.append("EdgeContractResult.profile_path is missing")
	return errors


func _flatten_nodes(location_node_results: Array) -> Dictionary:
	var errors: Array[String] = []
	var nodes: Array = []
	var node_sources: Array = []
	var seen_location_ids: Dictionary = {}
	for source_value in CanonicalDataSerializerScript.normalize_location_node_result_set(location_node_results):
		var source: Dictionary = source_value as Dictionary
		var region_id := str(source.get("region_id", ""))
		var result_hash := str(source.get("result_hash", ""))
		for node_value in (source.get("location_nodes", []) as Array):
			var node: Dictionary = node_value as Dictionary
			var location_id := str(node.get("location_id", ""))
			if location_id.is_empty():
				errors.append("LocationNodeResult contains a node without location_id")
				continue
			if seen_location_ids.has(location_id):
				errors.append("LocationNodeResult collection contains duplicate location_id: %s" % location_id)
				continue
			seen_location_ids[location_id] = true
			nodes.append(node.duplicate(true))
			node_sources.append({
				"location_id": location_id,
				"source_region_id": region_id,
				"location_node_result_hash": result_hash,
			})
	return {
		"success": errors.is_empty(),
		"errors": errors,
		"location_nodes": nodes,
		"node_sources": node_sources,
	}


func _build_source_manifest(location_node_results: Array, edge_contract_result: Dictionary) -> Array:
	var manifest: Array = []
	for source_value in location_node_results:
		var source: Dictionary = source_value as Dictionary
		manifest.append({
			"source_kind": "location_node_result",
			"source_id": str(source.get("region_id", "")),
			"result_hash": str(source.get("result_hash", "")),
		})
	manifest.append({
		"source_kind": "edge_contract_result",
		"source_id": str(edge_contract_result.get("profile_id", "")),
		"result_hash": str(edge_contract_result.get("result_hash", "")),
	})
	return manifest


func _build_rule_manifest(location_node_results: Array, edge_contract_result: Dictionary) -> Dictionary:
	var requests: Array[Dictionary] = []
	for source_value in location_node_results:
		var source: Dictionary = source_value as Dictionary
		requests.append({
			"profile_kind": "semantic_role_profile",
			"profile_path": str(source.get("semantic_role_profile_path", "")),
			"expected_id": str(source.get("region_type", "")),
		})
		requests.append({
			"profile_kind": "semantic_role_library",
			"profile_path": str(source.get("semantic_role_library_path", "")),
			"expected_id": str(source.get("semantic_role_library_id", "")),
			"expected_content_hash": str(source.get("semantic_role_library_content_hash", "")),
		})
		requests.append({
			"profile_kind": "location_node_profile",
			"profile_path": str(source.get("profile_path", "")),
			"expected_id": str(source.get("region_type", "")),
		})
	requests.append({
		"profile_kind": "edge_contract_profile",
		"profile_path": str(edge_contract_result.get("profile_path", "")),
		"expected_id": str(edge_contract_result.get("profile_id", "")),
	})
	var seen: Dictionary = {}
	var expected_ids: Dictionary = {}
	var expected_hashes: Dictionary = {}
	var manifest: Array = []
	var errors: Array[String] = []
	for request in requests:
		var profile_kind := str(request.get("profile_kind", ""))
		var profile_path := str(request.get("profile_path", ""))
		var expected_id := str(request.get("expected_id", ""))
		var expected_content_hash := str(request.get("expected_content_hash", ""))
		var key := "%s::%s" % [profile_kind, profile_path]
		if seen.has(key):
			if str(expected_ids.get(key, "")) != expected_id:
				errors.append("Rule profile is referenced with conflicting identities: %s" % profile_path)
			if str(expected_hashes.get(key, "")) != expected_content_hash:
				errors.append("Rule profile is referenced with conflicting content hashes: %s" % profile_path)
			continue
		seen[key] = true
		expected_ids[key] = expected_id
		expected_hashes[key] = expected_content_hash
		if profile_path.is_empty():
			errors.append("Rule profile path is missing for kind: %s" % profile_kind)
			continue
		var file := FileAccess.open(profile_path, FileAccess.READ)
		if file == null:
			errors.append("Rule profile resource is missing: %s" % profile_path)
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not (parsed is Dictionary):
			errors.append("Rule profile must contain a JSON object: %s" % profile_path)
			continue
		var profile_data: Dictionary = parsed as Dictionary
		var profile_errors := _validate_profile_data(profile_kind, profile_data, expected_id)
		if not profile_errors.is_empty():
			for error in profile_errors:
				errors.append("Rule profile is invalid at %s: %s" % [profile_path, error])
			continue
		var canonical_errors: Array[String] = CanonicalDataSerializerScript.validate_value(profile_data)
		if not canonical_errors.is_empty():
			for error in canonical_errors:
				errors.append("Rule profile cannot be canonicalized at %s: %s" % [profile_path, error])
			continue
		var profile_hash: String = CanonicalDataSerializerScript.profile_content_hash(profile_data)
		if profile_hash.is_empty():
			errors.append("Rule profile content hash could not be calculated: %s" % profile_path)
			continue
		if not expected_content_hash.is_empty() and profile_hash != expected_content_hash:
			errors.append("Rule profile content hash does not match upstream source at %s" % profile_path)
			continue
		manifest.append({
			"profile_kind": profile_kind,
			"profile_path": profile_path,
			"profile_content_hash": profile_hash,
		})
	return {
		"success": errors.is_empty(),
		"errors": errors,
		"rule_manifest": manifest,
	}


func _validate_profile_data(profile_kind: String, profile_data: Dictionary, expected_id: String) -> Array[String]:
	var errors: Array[String] = []
	match profile_kind:
		"semantic_role_library":
			var role_library: RefCounted = SemanticRoleLibraryScript.new()
			errors.append_array(role_library.configure(profile_data))
			if str(role_library.library_id()) != expected_id:
				errors.append("SemanticRoleLibrary.library_id does not match source result: %s != %s" % [str(role_library.library_id()), expected_id])
		"semantic_role_profile":
			var semantic_profile: RefCounted = RegionTypeProfileScript.new()
			errors.append_array(semantic_profile.configure(profile_data))
			if str(semantic_profile.region_type()) != expected_id:
				errors.append("RegionTypeProfile.region_type does not match source result: %s != %s" % [str(semantic_profile.region_type()), expected_id])
		"location_node_profile":
			var location_profile: RefCounted = LocationNodeProfileScript.new()
			errors.append_array(location_profile.configure(profile_data))
			if str(location_profile.region_type()) != expected_id:
				errors.append("LocationNodeProfile.region_type does not match source result: %s != %s" % [str(location_profile.region_type()), expected_id])
		"edge_contract_profile":
			var edge_profile: RefCounted = EdgeContractProfileScript.new()
			errors.append_array(edge_profile.configure(profile_data))
			if str(edge_profile.profile_id()) != expected_id:
				errors.append("EdgeContractProfile.profile_id does not match EdgeContractResult: %s != %s" % [str(edge_profile.profile_id()), expected_id])
		_:
			errors.append("Unsupported profile kind: %s" % profile_kind)
	return errors


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result


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
