extends SceneTree

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const LocationGraphSnapshotBuilderScript := preload("res://scripts/systems/regions/location_graph_snapshot_builder.gd")
const LocationGraphSnapshotStoreScript := preload("res://scripts/systems/regions/location_graph_snapshot_store.gd")
const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")

const TOWN_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const FOREST_REGION_INPUT_PATH := "res://data/regions/frontier_forest_region.json"
const EDGE_PROFILE_PATH := "res://data/location_graph/edge_contract_profiles/default.json"
const GRAPH_ID := "graph.frontier.snapshot_test.lg_0001"
const TEST_DIRECTORY := "user://v67_5_snapshot_tests"
const SNAPSHOT_PATH := TEST_DIRECTORY + "/snapshot.json"
const TAMPERED_PATH := TEST_DIRECTORY + "/tampered.json"
const PROFILE_PATH := TEST_DIRECTORY + "/edge_profile.json"


func _initialize() -> void:
	if not _assert_snapshot_builds_without_runtime_fields():
		return
	if not _assert_same_input_is_stable():
		return
	if not _assert_input_result_order_is_irrelevant():
		return
	if not _assert_upstream_result_hashes_are_rechecked():
		return
	if not _assert_content_hash_excludes_identity_fields():
		return
	if not _assert_tampering_fails_on_load():
		return
	if not _assert_noncanonical_raw_json_fails_on_load():
		return
	if not _assert_rule_content_changes_manifest_hash():
		return
	if not _assert_explicit_save_load_round_trip():
		return
	_cleanup()
	print("v67.5 location graph snapshot test passed")
	quit(0)


func _assert_snapshot_builds_without_runtime_fields() -> bool:
	var result := _compile_snapshot()
	if not bool(result.get("success", false)):
		return _fail("v67.5 snapshot compilation failed: %s" % str(result.get("errors", [])))
	var snapshot: Dictionary = result.get("location_graph_snapshot", {}) as Dictionary
	if str(snapshot.get("stage", "")) != "location_graph_snapshot":
		return _fail("v67.5 snapshot has wrong stage")
	if str(snapshot.get("compiler_version", "")) != "v67.8":
		return _fail("v67.8 LocationGraphSnapshot has stale compiler_version: %s" % str(snapshot.get("compiler_version", "")))
	if not CanonicalDataSerializerScript.is_sha256_hash(str(snapshot.get("content_hash", ""))):
		return _fail("v67.5 snapshot has no valid content_hash")
	if str(snapshot.get("snapshot_id", "")) != CanonicalDataSerializerScript.snapshot_id(
		GRAPH_ID,
		str(snapshot.get("content_hash", ""))
	):
		return _fail("v67.5 snapshot_id is not derived from graph_id and content_hash")
	var text := CanonicalDataSerializerScript.snapshot_json(snapshot)
	for forbidden in ["start_location_id", "current_location_id", "scene_path", "spawn_id", "exit_id", "direction_hint", "exit_style", "tilemap"]:
		if text.contains("\"%s\"" % forbidden):
			return _fail("v67.5 snapshot contains a forbidden Runtime or Scene field: %s" % forbidden)
	return true


func _assert_same_input_is_stable() -> bool:
	var first := _compile_snapshot()
	var second := _compile_snapshot()
	if not bool(first.get("success", false)) or not bool(second.get("success", false)):
		return _fail("v67.5 stability setup failed")
	var first_snapshot: Dictionary = first.get("location_graph_snapshot", {}) as Dictionary
	var second_snapshot: Dictionary = second.get("location_graph_snapshot", {}) as Dictionary
	if str(first_snapshot.get("content_hash", "")) != str(second_snapshot.get("content_hash", "")):
		return _fail("v67.5 same inputs produced different content_hash values")
	if CanonicalDataSerializerScript.snapshot_json(first_snapshot) != CanonicalDataSerializerScript.snapshot_json(second_snapshot):
		return _fail("v67.5 same inputs produced different snapshots")
	return true


func _assert_input_result_order_is_irrelevant() -> bool:
	var edge_result := _compile_edges(EDGE_PROFILE_PATH)
	if not bool(edge_result.get("success", false)):
		return _fail("v67.5 input order setup failed")
	var node_results: Array = edge_result.get("location_node_results", []) as Array
	var reversed_results: Array = node_results.duplicate(true)
	reversed_results.reverse()
	var builder: RefCounted = LocationGraphSnapshotBuilderScript.new()
	var first: Dictionary = builder.build_snapshot_result(
		GRAPH_ID,
		node_results,
		edge_result.get("edge_contract_result", {}) as Dictionary
	)
	var second: Dictionary = builder.build_snapshot_result(
		GRAPH_ID,
		reversed_results,
		edge_result.get("edge_contract_result", {}) as Dictionary
	)
	if not bool(first.get("success", false)) or not bool(second.get("success", false)):
		return _fail("v67.5 reordered inputs did not build: %s / %s" % [str(first.get("errors", [])), str(second.get("errors", []))])
	var first_snapshot: Dictionary = first.get("location_graph_snapshot", {}) as Dictionary
	var second_snapshot: Dictionary = second.get("location_graph_snapshot", {}) as Dictionary
	if str(first_snapshot.get("content_hash", "")) != str(second_snapshot.get("content_hash", "")):
		return _fail("v67.5 LocationNodeResult input order changed content_hash")
	return true


func _assert_upstream_result_hashes_are_rechecked() -> bool:
	var edge_result := _compile_edges(EDGE_PROFILE_PATH)
	if not bool(edge_result.get("success", false)):
		return _fail("v67.5 upstream hash setup failed")
	var node_results: Array = (edge_result.get("location_node_results", []) as Array).duplicate(true)
	var first_source: Dictionary = node_results[0] as Dictionary
	var nodes: Array = first_source.get("location_nodes", []) as Array
	var first_node: Dictionary = nodes[0] as Dictionary
	first_node["location_type"] = "tampered_location"
	nodes[0] = first_node
	first_source["location_nodes"] = nodes
	node_results[0] = first_source
	var builder: RefCounted = LocationGraphSnapshotBuilderScript.new()
	var node_tamper: Dictionary = builder.build_snapshot_result(
		GRAPH_ID,
		node_results,
		edge_result.get("edge_contract_result", {}) as Dictionary
	)
	if bool(node_tamper.get("success", false)) or not str(node_tamper.get("errors", [])).contains("result_hash"):
		return _fail("v67.5 accepted a modified LocationNodeResult without a matching result_hash")
	var tampered_edge_result: Dictionary = (edge_result.get("edge_contract_result", {}) as Dictionary).duplicate(true)
	var edges: Array = tampered_edge_result.get("edge_contracts", []) as Array
	var first_edge: Dictionary = edges[0] as Dictionary
	first_edge["edge_type"] = "tampered_edge"
	edges[0] = first_edge
	tampered_edge_result["edge_contracts"] = edges
	var edge_tamper: Dictionary = builder.build_snapshot_result(
		GRAPH_ID,
		edge_result.get("location_node_results", []) as Array,
		tampered_edge_result
	)
	if bool(edge_tamper.get("success", false)) or not str(edge_tamper.get("errors", [])).contains("result_hash"):
		return _fail("v67.5 accepted a modified EdgeContractResult without a matching result_hash")
	return true


func _assert_content_hash_excludes_identity_fields() -> bool:
	var result := _compile_snapshot()
	if not bool(result.get("success", false)):
		return _fail("v67.5 content hash exclusion setup failed")
	var snapshot: Dictionary = result.get("location_graph_snapshot", {}) as Dictionary
	var original_hash: String = CanonicalDataSerializerScript.snapshot_content_hash(snapshot)
	snapshot["content_hash"] = "sha256_ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
	snapshot["snapshot_id"] = "snapshot.lgs_fake"
	if CanonicalDataSerializerScript.snapshot_content_hash(snapshot) != original_hash:
		return _fail("v67.5 content_hash includes content_hash or snapshot_id")
	return true


func _assert_tampering_fails_on_load() -> bool:
	var result := _compile_snapshot()
	if not bool(result.get("success", false)):
		return _fail("v67.5 tamper setup failed")
	var snapshot: Dictionary = result.get("location_graph_snapshot", {}) as Dictionary
	var node_tamper := snapshot.duplicate(true)
	var nodes: Array = node_tamper.get("location_nodes", []) as Array
	var node: Dictionary = nodes[0] as Dictionary
	node["location_type"] = "tampered_location"
	nodes[0] = node
	node_tamper["location_nodes"] = nodes
	if not _assert_load_rejects(node_tamper, "content_hash"):
		return false
	var edge_tamper := snapshot.duplicate(true)
	var edges: Array = edge_tamper.get("edge_contracts", []) as Array
	var edge: Dictionary = edges[0] as Dictionary
	edge["to_location_id"] = "loc.frontier.unknown_region.unknown.unknown.ln_9999"
	edges[0] = edge
	edge_tamper["edge_contracts"] = edges
	if not _assert_load_rejects(edge_tamper, "unknown node"):
		return false
	var hash_tamper := snapshot.duplicate(true)
	hash_tamper["content_hash"] = "sha256_0000000000000000000000000000000000000000000000000000000000000000"
	if not _assert_load_rejects(hash_tamper, "content_hash"):
		return false
	var unknown_field := snapshot.duplicate(true)
	unknown_field["legacy_locations"] = []
	if not _assert_load_rejects(unknown_field, "unsupported field"):
		return false
	var incompatible_schema := snapshot.duplicate(true)
	incompatible_schema["schema_version"] = 999
	if not _assert_load_rejects(incompatible_schema, "unsupported"):
		return false
	var stale_compiler := snapshot.duplicate(true)
	stale_compiler["compiler_version"] = "v67.5"
	if not _assert_load_rejects(stale_compiler, "compiler_version is incompatible"):
		return false
	return true


func _assert_noncanonical_raw_json_fails_on_load() -> bool:
	var result := _compile_snapshot()
	if not bool(result.get("success", false)):
		return _fail("v67.5 non-canonical load setup failed")
	var snapshot: Dictionary = result.get("location_graph_snapshot", {}) as Dictionary
	var reordered_nodes := snapshot.duplicate(true)
	var nodes: Array = reordered_nodes.get("location_nodes", []) as Array
	if nodes.size() < 2:
		return _fail("v67.5 non-canonical node order test requires at least two nodes")
	nodes.reverse()
	reordered_nodes["location_nodes"] = nodes
	if not _assert_load_rejects(reordered_nodes, "canonical collection order"):
		return false
	var duplicate_tags := snapshot.duplicate(true)
	var tagged_nodes: Array = duplicate_tags.get("location_nodes", []) as Array
	var duplicated_node_tag := false
	for index in range(tagged_nodes.size()):
		var node: Dictionary = tagged_nodes[index] as Dictionary
		var tags: Array = node.get("node_tags", []) as Array
		if tags.is_empty():
			continue
		tags.append(tags[0])
		node["node_tags"] = tags
		tagged_nodes[index] = node
		duplicated_node_tag = true
		break
	if not duplicated_node_tag:
		return _fail("v67.5 non-canonical tag test could not find a tagged node")
	duplicate_tags["location_nodes"] = tagged_nodes
	if not _assert_load_rejects(duplicate_tags, "canonical collection order"):
		return false
	var duplicate_traversal_tags := snapshot.duplicate(true)
	var tagged_edges: Array = duplicate_traversal_tags.get("edge_contracts", []) as Array
	var duplicated_edge_tag := false
	for index in range(tagged_edges.size()):
		var edge: Dictionary = tagged_edges[index] as Dictionary
		var traversal_tags: Array = edge.get("traversal_tags", []) as Array
		if traversal_tags.is_empty():
			continue
		traversal_tags.append(traversal_tags[0])
		edge["traversal_tags"] = traversal_tags
		tagged_edges[index] = edge
		duplicated_edge_tag = true
		break
	if not duplicated_edge_tag:
		return _fail("v67.5 non-canonical traversal tag test could not find a tagged edge")
	duplicate_traversal_tags["edge_contracts"] = tagged_edges
	if not _assert_load_rejects(duplicate_traversal_tags, "canonical collection order"):
		return false
	return true


func _assert_rule_content_changes_manifest_hash() -> bool:
	_ensure_test_directory()
	var profile_a := _load_json(EDGE_PROFILE_PATH)
	if not _write_json(PROFILE_PATH, profile_a):
		return _fail("v67.5 could not write rule profile A")
	var edge_result := _compile_edges(PROFILE_PATH)
	if not bool(edge_result.get("success", false)):
		return _fail("v67.5 rule manifest setup failed: %s" % str(edge_result.get("errors", [])))
	var builder: RefCounted = LocationGraphSnapshotBuilderScript.new()
	var snapshot_a_result: Dictionary = builder.build_snapshot_result(
		GRAPH_ID,
		edge_result.get("location_node_results", []) as Array,
		edge_result.get("edge_contract_result", {}) as Dictionary
	)
	if not bool(snapshot_a_result.get("success", false)):
		return _fail("v67.5 could not build snapshot with rule profile A: %s" % str(snapshot_a_result.get("errors", [])))
	var profile_b := profile_a.duplicate(true)
	var allowed_types: Array = profile_b.get("allowed_edge_types", []) as Array
	allowed_types.append("trail")
	profile_b["allowed_edge_types"] = allowed_types
	if not _write_json(PROFILE_PATH, profile_b):
		return _fail("v67.5 could not write rule profile B")
	var snapshot_b_result: Dictionary = builder.build_snapshot_result(
		GRAPH_ID,
		edge_result.get("location_node_results", []) as Array,
		edge_result.get("edge_contract_result", {}) as Dictionary
	)
	if not bool(snapshot_b_result.get("success", false)):
		return _fail("v67.5 could not build snapshot with rule profile B: %s" % str(snapshot_b_result.get("errors", [])))
	var snapshot_a: Dictionary = snapshot_a_result.get("location_graph_snapshot", {}) as Dictionary
	var snapshot_b: Dictionary = snapshot_b_result.get("location_graph_snapshot", {}) as Dictionary
	if _edge_profile_hash(snapshot_a) == _edge_profile_hash(snapshot_b):
		return _fail("v67.5 rule_manifest hash did not change after profile content changed")
	if str(snapshot_a.get("content_hash", "")) == str(snapshot_b.get("content_hash", "")):
		return _fail("v67.5 content_hash did not change after rule content changed")
	return true


func _assert_explicit_save_load_round_trip() -> bool:
	var result := _compile_snapshot()
	if not bool(result.get("success", false)):
		return _fail("v67.5 save/load setup failed")
	var snapshot: Dictionary = result.get("location_graph_snapshot", {}) as Dictionary
	var store: RefCounted = LocationGraphSnapshotStoreScript.new()
	var missing_path: Dictionary = store.save_snapshot_to_path(snapshot, "")
	if bool(missing_path.get("success", false)) or not str(missing_path.get("errors", [])).contains("required"):
		return _fail("v67.5 SnapshotStore accepted a missing explicit path")
	var save_result: Dictionary = store.save_snapshot_to_path(snapshot, SNAPSHOT_PATH)
	if not bool(save_result.get("success", false)):
		return _fail("v67.5 explicit snapshot save failed: %s" % str(save_result.get("errors", [])))
	var load_result: Dictionary = store.load_snapshot_from_path(SNAPSHOT_PATH)
	if not bool(load_result.get("success", false)):
		return _fail("v67.5 snapshot load failed: %s" % str(load_result.get("errors", [])))
	var loaded: Dictionary = load_result.get("location_graph_snapshot", {}) as Dictionary
	if CanonicalDataSerializerScript.snapshot_json(snapshot) != CanonicalDataSerializerScript.snapshot_json(loaded):
		return _fail("v67.5 save/load round trip changed the snapshot")
	return true


func _assert_load_rejects(snapshot: Dictionary, expected_error: String) -> bool:
	_ensure_test_directory()
	var text: String = CanonicalDataSerializerScript.serialize(snapshot)
	var file := FileAccess.open(TAMPERED_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("v67.5 could not write tampered snapshot fixture")
	file.store_string(text)
	file = null
	var store: RefCounted = LocationGraphSnapshotStoreScript.new()
	var load_result: Dictionary = store.load_snapshot_from_path(TAMPERED_PATH)
	if bool(load_result.get("success", false)):
		return _fail("v67.5 loaded a tampered snapshot")
	if not str(load_result.get("errors", [])).contains(expected_error):
		return _fail("v67.5 tampered snapshot failed for the wrong reason: %s" % str(load_result.get("errors", [])))
	return true


func _compile_snapshot() -> Dictionary:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	return compiler.compile_location_graph_snapshot_result([
		_load_json(TOWN_REGION_INPUT_PATH),
		_load_json(FOREST_REGION_INPUT_PATH),
	], EDGE_PROFILE_PATH, GRAPH_ID)


func _compile_edges(profile_path: String) -> Dictionary:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	return compiler.compile_edge_contracts_result([
		_load_json(TOWN_REGION_INPUT_PATH),
		_load_json(FOREST_REGION_INPUT_PATH),
	], profile_path)


func _edge_profile_hash(snapshot: Dictionary) -> String:
	for value in (snapshot.get("rule_manifest", []) as Array):
		var row: Dictionary = value as Dictionary
		if str(row.get("profile_kind", "")) == "edge_contract_profile":
			return str(row.get("profile_content_hash", ""))
	return ""


func _load_json(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> bool:
	_ensure_test_directory()
	var text: String = CanonicalDataSerializerScript.serialize(data)
	if text.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file = null
	return true


func _ensure_test_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))


func _cleanup() -> void:
	for path in [SNAPSHOT_PATH, TAMPERED_PATH, PROFILE_PATH]:
		var global_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(global_path):
			DirAccess.remove_absolute(global_path)


func _fail(message: String) -> bool:
	_cleanup()
	push_error(message)
	quit(1)
	return false
