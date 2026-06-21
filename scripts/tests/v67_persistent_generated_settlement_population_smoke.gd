extends RefCounted

const StoreScript := preload("res://scripts/systems/settlements/generated_settlement_store.gd")
const BASIC_INTERIOR_SCENE := "res://scenes/locations/generated_basic_interior.tscn"

const SETTLEMENT_ID := "v67_smoke_settlement"


func run(root: Node) -> bool:
	GameState.start_new_session("v67_smoke_session")
	TimeManager.reset()
	DefinitionLoader.clear_cache()
	var store: RefCounted = StoreScript.new()
	store.delete_snapshot(SETTLEMENT_ID)
	DefinitionLoader.clear_cache()

	var source := _source()
	var first: Dictionary = DefinitionLoader.materialize_location(source, "res://data/locations/v67_smoke_generated_settlement.json")
	if first.is_empty():
		return _fail("v67 could not materialize persistent generated settlement")
	var snapshot: Dictionary = store.load_snapshot(SETTLEMENT_ID)
	if snapshot.is_empty():
		return _fail("v67 snapshot file was not written")
	if not _snapshot_shape_is_valid(snapshot):
		return false
	if not _schedule_targets_are_resolvable(snapshot):
		return false
	if not _npc_schedules_are_resolvable(snapshot):
		return false
	if not _generated_character_sources_are_readable(snapshot):
		return false
	if not _spawn_rows_are_injected(snapshot):
		return false
	if not _definition_loader_resolves_snapshot_interiors(snapshot):
		return false
	if not _location_root_can_spawn_generated_npc(root, snapshot):
		return false

	DefinitionLoader.clear_cache()
	var second: Dictionary = DefinitionLoader.materialize_location(source, "res://data/locations/v67_smoke_generated_settlement.json")
	if second.is_empty():
		return _fail("v67 second materialization failed")
	var second_snapshot: Dictionary = store.load_snapshot(SETTLEMENT_ID)
	if not _same_snapshot_identity(snapshot, second_snapshot):
		return _fail("v67 second load did not preserve snapshot identity")
	if JSON.stringify(_npc_ids(snapshot)) != JSON.stringify(_npc_ids(second_snapshot)):
		return _fail("v67 generated npc ids changed between loads")
	if not SaveManager.get_generated_settlement_index().has(SETTLEMENT_ID):
		return _fail("v67 SaveManager did not record generated settlement index")

	print("v67 persistent generated settlement population smoke test passed")
	return true


func _source() -> Dictionary:
	return {
		"id": SETTLEMENT_ID,
		"display_name": "V67 Smoke Settlement",
		"tile_size": 32,
		"generator": {
			"type": "settlement",
			"persistent_generated_settlement": true,
			"settlement_id": SETTLEMENT_ID,
			"settlement_policy_id": "roadside_trade_village",
			"seed": 6701,
			"size": { "width": 48, "height": 32 },
			"context": {
				"map_size": { "width": 48, "height": 32 },
				"entrances": [{ "x": 0, "y": 16 }],
				"existing_obstacles": [{ "x": 11, "y": 5 }, { "x": 12, "y": 5 }],
				"existing_water": [{ "x": 42, "y": 7 }, { "x": 43, "y": 7 }],
				"important_world_points": [{ "x": 36, "y": 20 }],
				"world_seed": 6701,
			},
		},
	}


func _snapshot_shape_is_valid(snapshot: Dictionary) -> bool:
	if int(snapshot.get("schema_version", 0)) != 1:
		return _fail("snapshot schema_version must be 1")
	if not (str(snapshot.get("generator_version", "")) in ["v67", "v68"]):
		return _fail("snapshot generator_version must be v67 or v68")
	if str(snapshot.get("settlement_id", "")) != SETTLEMENT_ID:
		return _fail("snapshot settlement_id mismatch")
	if str(snapshot.get("policy_id", "")) != "roadside_trade_village":
		return _fail("snapshot policy_id mismatch")
	if int(snapshot.get("seed", 0)) != 6701:
		return _fail("snapshot seed mismatch")
	if str(snapshot.get("exterior_location_id", "")) != "%s__exterior" % SETTLEMENT_ID:
		return _fail("snapshot exterior location id mismatch")
	if (snapshot.get("locations", []) as Array).is_empty():
		return _fail("snapshot must include exterior location data")
	if (snapshot.get("generated_interiors", []) as Array).is_empty():
		return _fail("snapshot must include generated interiors")
	if (snapshot.get("building_contracts", []) as Array).is_empty():
		return _fail("snapshot must include building contracts")
	if (snapshot.get("schedule_targets", []) as Array).is_empty():
		return _fail("snapshot must include schedule targets")
	if (snapshot.get("npc_definitions", []) as Array).is_empty():
		return _fail("snapshot must include generated npc definitions")
	if (snapshot.get("npc_role_assignments", []) as Array).is_empty():
		return _fail("snapshot must include role assignments")
	if (snapshot.get("npc_spawn_rows_by_location", {}) as Dictionary).is_empty():
		return _fail("snapshot must include spawn rows by location")
	for contract_value in (snapshot.get("building_contracts", []) as Array):
		var contract: Dictionary = contract_value as Dictionary
		if not str(contract.get("building_id", "")).begins_with("%s__" % SETTLEMENT_ID):
			return _fail("building contract id must be settlement namespaced")
	return true


func _schedule_targets_are_resolvable(snapshot: Dictionary) -> bool:
	var anchors_by_location := _anchors_by_location(snapshot)
	for target_value in (snapshot.get("schedule_targets", []) as Array):
		var target: Dictionary = target_value as Dictionary
		var location_id := str(target.get("location_id", ""))
		var anchor_id := str(target.get("anchor_id", ""))
		if location_id.is_empty() or anchor_id.is_empty():
			return _fail("schedule target missing location_id or anchor_id")
		if not (anchors_by_location.get(location_id, {}) as Dictionary).has(anchor_id):
			return _fail("schedule target anchor is not resolvable: %s/%s" % [location_id, anchor_id])
	return true


func _npc_schedules_are_resolvable(snapshot: Dictionary) -> bool:
	var anchors_by_location := _anchors_by_location(snapshot)
	var has_home := false
	var has_work := false
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		if not str(definition.get("home_location_id", "")).is_empty() and not str(definition.get("home_anchor_id", "")).is_empty():
			has_home = true
		if not str(definition.get("work_location_id", "")).is_empty() and not str(definition.get("work_anchor_id", "")).is_empty():
			has_work = true
		for entry_value in (definition.get("schedule", []) as Array):
			var entry: Dictionary = entry_value as Dictionary
			var location_id := str(entry.get("location_id", ""))
			var anchor_id := str(entry.get("anchor_id", ""))
			if location_id.is_empty() or anchor_id.is_empty():
				return _fail("npc schedule entry missing location_id or anchor_id")
			if not (anchors_by_location.get(location_id, {}) as Dictionary).has(anchor_id):
				return _fail("npc schedule entry anchor is not resolvable: %s/%s" % [location_id, anchor_id])
	if not has_home:
		return _fail("at least one generated NPC must have a home target")
	if not has_work:
		return _fail("at least one generated NPC must have a work/service target")
	return true


func _generated_character_sources_are_readable(snapshot: Dictionary) -> bool:
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		var source := str(definition.get("source", ""))
		if source.is_empty() or not FileAccess.file_exists(source):
			return _fail("generated character source file is missing: %s" % source)
		var loaded := DefinitionLoader.load_json_resource(source, "generated character definition")
		if str(loaded.get("id", "")) != str(definition.get("id", "")):
			return _fail("generated character source did not load the expected npc id")
	return true


func _spawn_rows_are_injected(snapshot: Dictionary) -> bool:
	var locations_with_rows: Dictionary = snapshot.get("npc_spawn_rows_by_location", {}) as Dictionary
	var found_in_location := false
	var found_exterior_or_interior := false
	for location_id in locations_with_rows.keys():
		var rows: Array = locations_with_rows.get(location_id, []) as Array
		if not rows.is_empty():
			found_exterior_or_interior = true
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if not (location.get("characters", []) as Array).is_empty():
			found_in_location = true
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		if not (manifest.get("characters", []) as Array).is_empty():
			found_in_location = true
	if not found_exterior_or_interior:
		return _fail("snapshot must have at least one spawn row location")
	if not found_in_location:
		return _fail("spawn rows must be injected into exterior or interior locations")
	return true


func _definition_loader_resolves_snapshot_interiors(snapshot: Dictionary) -> bool:
	var manifests: Array = snapshot.get("generated_interiors", []) as Array
	if manifests.is_empty():
		return _fail("no generated interiors to resolve")
	var manifest: Dictionary = manifests[0] as Dictionary
	var interior_id := str(manifest.get("interior_location_id", ""))
	DefinitionLoader.clear_cache()
	var resolved := DefinitionLoader.resolve_location_by_id(interior_id)
	if resolved.is_empty():
		return _fail("DefinitionLoader could not resolve snapshot interior: %s" % interior_id)
	if str(resolved.get("id", "")) != interior_id:
		return _fail("snapshot interior resolve id mismatch")
	if (resolved.get("characters", []) as Array).is_empty() and _location_has_spawn_rows(snapshot, interior_id):
		return _fail("snapshot interior characters were not materialized")
	return true


func _location_root_can_spawn_generated_npc(root: Node, snapshot: Dictionary) -> bool:
	var spawn_location_id := _first_active_spawn_location_id(snapshot)
	if spawn_location_id.is_empty():
		return _fail("no active spawn location id available")
	var location_data := _location_data(snapshot, spawn_location_id)
	if location_data.is_empty():
		return _fail("could not find location data for spawn location: %s" % spawn_location_id)

	var scene := load(BASIC_INTERIOR_SCENE) as PackedScene
	if scene == null:
		return _fail("could not load basic location shell")
	SceneLoader.set_pending_location_context({
		"target_location_id": spawn_location_id,
	})
	var instance := scene.instantiate()
	instance.location_data_path = "user://v67_snapshot_virtual_%s.json" % spawn_location_id
	root.add_child(instance)
	var grid: LocationGrid = instance.get_location_grid() if instance.has_method("get_location_grid") else null
	if grid == null:
		_cleanup_instance(instance)
		return _fail("LocationRoot did not expose grid for snapshot location")
	var spawned := false
	for npc_id in _npc_ids(snapshot):
		if grid.get_character_by_id(npc_id) != null:
			spawned = true
			break
	_cleanup_instance(instance)
	if not spawned:
		return _fail("LocationRoot did not spawn any generated NPC at current schedule location")
	return true


func _same_snapshot_identity(first: Dictionary, second: Dictionary) -> bool:
	return str(first.get("settlement_id", "")) == str(second.get("settlement_id", "")) \
		and str(first.get("policy_id", "")) == str(second.get("policy_id", "")) \
		and int(first.get("seed", 0)) == int(second.get("seed", -1)) \
		and str(first.get("exterior_location_id", "")) == str(second.get("exterior_location_id", ""))


func _anchors_by_location(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		result[str(location.get("id", ""))] = _anchor_ids(location.get("anchors", []) as Array)
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		result[str(manifest.get("interior_location_id", ""))] = _anchor_ids(manifest.get("anchors", []) as Array)
	return result


func _anchor_ids(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		result[str(row.get("id", ""))] = true
	return result


func _npc_ids(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		result.append(str(definition.get("id", "")))
	result.sort()
	return result


func _location_has_spawn_rows(snapshot: Dictionary, location_id: String) -> bool:
	return not ((snapshot.get("npc_spawn_rows_by_location", {}) as Dictionary).get(location_id, []) as Array).is_empty()


func _first_spawn_location_id(snapshot: Dictionary) -> String:
	for location_id in (snapshot.get("npc_spawn_rows_by_location", {}) as Dictionary).keys():
		if _location_has_spawn_rows(snapshot, str(location_id)):
			return str(location_id)
	return ""


func _first_active_spawn_location_id(snapshot: Dictionary) -> String:
	var active_minutes := TimeManager.get_absolute_minutes()
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		var entry: Dictionary = NpcScheduleSystem.get_active_entry(definition.get("schedule", []) as Array, active_minutes)
		var location_id := str(entry.get("location_id", ""))
		if location_id.is_empty():
			continue
		if _location_has_spawn_rows(snapshot, location_id):
			return location_id
	return _first_spawn_location_id(snapshot)


func _location_data(snapshot: Dictionary, location_id: String) -> Dictionary:
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if str(location.get("id", "")) == location_id:
			return location
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		if str(manifest.get("interior_location_id", "")) == location_id:
			return DefinitionLoader.resolve_location_by_id(location_id)
	return {}


func _cleanup_instance(instance: Node) -> void:
	if instance == null:
		return
	if instance.get_parent() != null:
		instance.get_parent().remove_child(instance)
	instance.queue_free()


func _fail(message: String) -> bool:
	push_error(message)
	return false
