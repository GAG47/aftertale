extends RefCounted

const TileSceneCompilerScript := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")
const GENERATED_INTERIOR_SCENE := "res://scenes/locations/generated_basic_interior.tscn"
const BASIC_INTERIOR_ID := "generated_basic_interior"


func run(_root: Node) -> bool:
	DefinitionLoader.clear_cache()
	var source := _source_for_policy("roadside_trade_village")
	var compiler: RefCounted = TileSceneCompilerScript.new()
	var compiled: Dictionary = compiler.generate_location(source)
	if compiled.is_empty():
		return _fail("v64 contract smoke could not compile generated settlement")
	if not _exterior_contract_is_valid(compiled):
		return false
	if not _interior_manifests_are_valid(compiled):
		return false
	if not _schedule_targets_are_resolvable(compiled):
		return false
	if not _definition_loader_resolves_generated_interiors(source):
		return false
	if not _contract_ids_are_deterministic(source):
		return false
	print("v64 generated interiors contract smoke test passed")
	return true


func _source_for_policy(policy_id: String) -> Dictionary:
	return {
		"id": "v64_contract_%s_sample" % policy_id,
		"display_name": "V64 Contract %s Sample" % policy_id,
		"tile_size": 32,
		"generator": {
			"type": "settlement",
			"settlement_policy_id": policy_id,
			"size": { "width": 48, "height": 32 },
			"context": {
				"map_size": { "width": 48, "height": 32 },
				"entrances": [{ "x": 0, "y": 16 }],
				"existing_obstacles": [{ "x": 11, "y": 5 }, { "x": 12, "y": 5 }, { "x": 38, "y": 24 }],
				"existing_water": [{ "x": 42, "y": 7 }, { "x": 43, "y": 7 }, { "x": 43, "y": 8 }],
				"important_world_points": [{ "x": 36, "y": 20 }]
			}
		}
	}


func _exterior_contract_is_valid(compiled: Dictionary) -> bool:
	if str(compiled.get("id", "")) == BASIC_INTERIOR_ID:
		return _fail("generated exterior must not reuse generated_basic_interior as identity")
	if not (compiled.get("characters", []) as Array).is_empty():
		return _fail("generated exterior must not output generated character records")
	if not (compiled.get("shops", []) as Array).is_empty():
		return _fail("generated exterior must not output exterior shop records")

	var manifest_ids := _manifest_ids(compiled)
	var transition_count := 0
	for object_value in (compiled.get("objects", []) as Array):
		var object: Dictionary = object_value as Dictionary
		if str(object.get("facility_type", "")) != "scene_transition":
			if str(object.get("facility_type", "")) == "shop" or not str(object.get("shop_id", "")).is_empty():
				return _fail("generated exterior must not output shop counters or shop objects")
			continue
		transition_count += 1
		var target_location_id := str(object.get("target_location_id", ""))
		if target_location_id.is_empty():
			return _fail("exterior scene transition must use target_location_id")
		if target_location_id == BASIC_INTERIOR_ID:
			return _fail("exterior scene transition must not target generated_basic_interior id")
		if not manifest_ids.has(target_location_id):
			return _fail("exterior scene transition target has no generated interior manifest: %s" % target_location_id)
		if str(object.get("target_scene_path", "")) != GENERATED_INTERIOR_SCENE:
			return _fail("exterior scene transition should reuse the generated interior scene shell")
		var context: Dictionary = object.get("transition_context", {}) as Dictionary
		if str(context.get("target_location_id", "")) != target_location_id:
			return _fail("exterior transition context must carry the concrete interior id")
		if not ((context.get("interior_manifest", {}) as Dictionary).has("interior_location_id")):
			return _fail("exterior transition context must carry the interior manifest")
	if transition_count <= 0:
		return _fail("generated settlement must expose at least one enterable exterior door")
	return true


func _interior_manifests_are_valid(compiled: Dictionary) -> bool:
	var exterior_id := str(compiled.get("id", ""))
	var manifests: Array = compiled.get("generated_interiors", []) as Array
	var contracts: Array = compiled.get("building_contracts", []) as Array
	if manifests.is_empty():
		return _fail("generated settlement must output concrete interior manifests")
	if manifests.size() != contracts.size():
		return _fail("generated interiors and building contracts must stay one-to-one")
	var seen: Dictionary = {}
	for manifest_value in manifests:
		var manifest: Dictionary = manifest_value as Dictionary
		var interior_id := str(manifest.get("interior_location_id", ""))
		if interior_id.is_empty() or interior_id == BASIC_INTERIOR_ID:
			return _fail("interior manifest must have a concrete non-basic location id")
		if seen.has(interior_id):
			return _fail("interior location ids must be unique: %s" % interior_id)
		seen[interior_id] = true
		if str(manifest.get("scene_path", "")) != GENERATED_INTERIOR_SCENE:
			return _fail("interior manifest should use the reusable scene shell")
		if str(manifest.get("exterior_location_id", "")) != exterior_id:
			return _fail("interior manifest must point back to the generated exterior")
		if not (manifest.get("characters", []) as Array).is_empty():
			return _fail("generated interior manifests must not output character records")
		var contract: Dictionary = manifest.get("placement_contract", {}) as Dictionary
		if str(contract.get("interior_location_id", "")) != interior_id:
			return _fail("placement contract must reference its concrete interior id")
		if (contract.get("exterior_slots", []) as Array).is_empty():
			return _fail("placement contract must expose exterior prefab/parcel slots")
		if (contract.get("facility_slots", []) as Array).is_empty():
			return _fail("placement contract must expose facility slots")
		if not _manifest_has_return_door(manifest, exterior_id):
			return _fail("interior manifest must contain a return door to the exterior")
		if not _manifest_facilities_have_anchors(manifest):
			return _fail("interior facilities must be backed by anchors")
	return true


func _schedule_targets_are_resolvable(compiled: Dictionary) -> bool:
	var exterior_id := str(compiled.get("id", ""))
	var manifests_by_id := _manifests_by_id(compiled)
	var exterior_anchor_ids := _anchor_ids(compiled.get("anchors", []) as Array)
	var targets: Array = compiled.get("schedule_targets", []) as Array
	if targets.is_empty():
		return _fail("generated settlement must output schedule targets")
	for target_value in targets:
		var target: Dictionary = target_value as Dictionary
		var location_id := str(target.get("location_id", ""))
		var anchor_id := str(target.get("anchor_id", ""))
		if location_id.is_empty() or anchor_id.is_empty():
			return _fail("schedule target must include location_id and anchor_id")
		if location_id == BASIC_INTERIOR_ID:
			return _fail("schedule target must not use generated_basic_interior as a world location")
		if location_id == exterior_id:
			if not exterior_anchor_ids.has(anchor_id):
				return _fail("exterior schedule target anchor is missing: %s" % anchor_id)
			continue
		if not manifests_by_id.has(location_id):
			return _fail("interior schedule target location has no manifest: %s" % location_id)
		var manifest: Dictionary = manifests_by_id[location_id] as Dictionary
		if not _anchor_ids(manifest.get("anchors", []) as Array).has(anchor_id):
			return _fail("interior schedule target anchor is missing: %s/%s" % [location_id, anchor_id])
	return true


func _definition_loader_resolves_generated_interiors(source: Dictionary) -> bool:
	DefinitionLoader.clear_cache()
	var compiled: Dictionary = DefinitionLoader.materialize_location(source, "res://data/locations/v64_contract_generated_settlement.json")
	var manifests: Array = compiled.get("generated_interiors", []) as Array
	if manifests.is_empty():
		return _fail("DefinitionLoader materialization must keep generated interiors")
	var manifest: Dictionary = manifests[0] as Dictionary
	var interior_id := str(manifest.get("interior_location_id", ""))
	var resolved: Dictionary = DefinitionLoader.resolve_location_by_id(interior_id)
	if resolved.is_empty():
		return _fail("DefinitionLoader must resolve concrete generated interior id: %s" % interior_id)
	if str(resolved.get("id", "")) != interior_id:
		return _fail("resolved generated interior id mismatch")
	if str(DefinitionLoader.get_location_scene_path(interior_id)) != GENERATED_INTERIOR_SCENE:
		return _fail("DefinitionLoader must register generated interior scene shell")
	if (resolved.get("anchors", []) as Array).is_empty() or (resolved.get("objects", []) as Array).is_empty():
		return _fail("resolved generated interior must contain anchors and objects")
	if not ((resolved.get("generated_interior_manifest", {}) as Dictionary).has("placement_contract")):
		return _fail("resolved generated interior must retain its placement contract")
	return true


func _contract_ids_are_deterministic(source: Dictionary) -> bool:
	var compiler_a: RefCounted = TileSceneCompilerScript.new()
	var compiler_b: RefCounted = TileSceneCompilerScript.new()
	var first: Dictionary = compiler_a.generate_location(source)
	var second: Dictionary = compiler_b.generate_location(source)
	if JSON.stringify(_contract_signature(first)) != JSON.stringify(_contract_signature(second)):
		return _fail("generated interior contracts must be deterministic for a fixed seed")
	return true


func _contract_signature(compiled: Dictionary) -> Dictionary:
	var manifest_ids: Array[String] = []
	for manifest_value in (compiled.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		manifest_ids.append(str(manifest.get("interior_location_id", "")))
	manifest_ids.sort()
	var schedule_ids: Array[String] = []
	for target_value in (compiled.get("schedule_targets", []) as Array):
		var target: Dictionary = target_value as Dictionary
		schedule_ids.append("%s@%s#%s" % [str(target.get("id", "")), str(target.get("location_id", "")), str(target.get("anchor_id", ""))])
	schedule_ids.sort()
	return {
		"manifest_ids": manifest_ids,
		"schedule_ids": schedule_ids,
	}


func _manifest_has_return_door(manifest: Dictionary, exterior_id: String) -> bool:
	for object_value in (manifest.get("objects", []) as Array):
		var object: Dictionary = object_value as Dictionary
		if str(object.get("facility_type", "")) != "scene_transition":
			continue
		if str(object.get("target_scene_path", "")) != "__return__":
			continue
		return str(object.get("target_location_id", "")) == exterior_id
	return false


func _manifest_facilities_have_anchors(manifest: Dictionary) -> bool:
	var anchor_ids := _anchor_ids(manifest.get("anchors", []) as Array)
	for facility_value in (manifest.get("facilities", []) as Array):
		var facility: Dictionary = facility_value as Dictionary
		var anchor_id := str(facility.get("anchor_id", ""))
		if anchor_id.is_empty() or not anchor_ids.has(anchor_id):
			return false
	return true


func _manifest_ids(compiled: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for manifest_value in (compiled.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		result[str(manifest.get("interior_location_id", ""))] = true
	return result


func _manifests_by_id(compiled: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for manifest_value in (compiled.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		result[str(manifest.get("interior_location_id", ""))] = manifest
	return result


func _anchor_ids(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		result[str(row.get("id", ""))] = true
	return result


func _fail(message: String) -> bool:
	push_error(message)
	return false
