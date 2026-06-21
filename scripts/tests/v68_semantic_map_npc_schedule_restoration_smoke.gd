extends RefCounted

const StoreScript := preload("res://scripts/systems/settlements/generated_settlement_store.gd")

const SETTLEMENT_ID := "v68_semantic_map_settlement"
const TEMPLATE_ID := "v68_semantic_map_template"
const WORLD_ID := "v68_semantic_map_world"
const SAVE_PATH := "user://saves/v68_semantic_map_slot.json"
const SOURCE_PATH := "res://data/locations/v68_semantic_map_template.json"


func run(root: Node) -> bool:
	if root != null and root.has_node("WorldRoot"):
		SceneLoader.configure(root.get_node("WorldRoot"))

	SaveManager.configure_active_save_context(SAVE_PATH, WORLD_ID)
	StoreScript.clear_generated_data_for_active_context()
	GameState.start_new_session("v68_semantic_map_session")
	TimeManager.reset()
	NpcScheduleSystem.reset_schedule_state()
	DefinitionLoader.clear_cache()
	DefinitionLoader.clear_generated_runtime_cache()

	var first := DefinitionLoader.materialize_location(_source(), SOURCE_PATH, {
		"settlement_instance_id": SETTLEMENT_ID,
	})
	if first.is_empty():
		return _fail("v68 could not materialize generated settlement")

	var store: RefCounted = StoreScript.new()
	var snapshot: Dictionary = store.load_snapshot(SETTLEMENT_ID)
	if snapshot.is_empty():
		return _fail("v68 snapshot file was not written")
	if not _semantic_snapshot_is_valid(snapshot, first):
		return false

	print("v68 semantic map npc schedule restoration smoke test passed")
	return true


func _source() -> Dictionary:
	return {
		"id": SETTLEMENT_ID,
		"settlement_template_id": TEMPLATE_ID,
		"display_name": "V68 Semantic Map Template",
		"tile_size": 32,
		"generator": {
			"type": "settlement",
			"persistent_generated_settlement": true,
			"settlement_id": SETTLEMENT_ID,
			"settlement_template_id": TEMPLATE_ID,
			"settlement_policy_id": "roadside_trade_village",
			"seed": 6801,
			"size": { "width": 48, "height": 32 },
			"context": {
				"map_size": { "width": 48, "height": 32 },
				"entrances": [{ "x": 0, "y": 16 }],
				"existing_obstacles": [{ "x": 11, "y": 5 }, { "x": 12, "y": 5 }],
				"existing_water": [{ "x": 42, "y": 7 }, { "x": 43, "y": 7 }],
				"important_world_points": [{ "x": 36, "y": 20 }],
				"world_seed": 6801,
			},
		},
	}


func _semantic_snapshot_is_valid(snapshot: Dictionary, materialized_location: Dictionary) -> bool:
	if str(snapshot.get("generator_version", "")) != "v68":
		return _fail("v68 snapshot generator_version must be v68")
	var semantic_map: Dictionary = snapshot.get("semantic_map", {}) as Dictionary
	if semantic_map.is_empty():
		return _fail("v68 snapshot must expose semantic_map")
	if str(semantic_map.get("source", "")) != "v68_generated_settlement_semantic_map":
		return _fail("v68 semantic_map source mismatch")
	if int(semantic_map.get("schema_version", 0)) <= 0:
		return _fail("v68 semantic_map schema_version missing")
	var validation: Dictionary = semantic_map.get("validation", {}) as Dictionary
	if int(validation.get("error_count", 0)) != 0:
		return _fail("v68 semantic_map validation errors: %s" % str(validation.get("errors", [])))
	if (semantic_map.get("locations", []) as Array).is_empty():
		return _fail("v68 semantic_map must include locations")
	if (semantic_map.get("buildings", []) as Array).is_empty():
		return _fail("v68 semantic_map must include buildings")
	if (semantic_map.get("targets", []) as Array).is_empty():
		return _fail("v68 semantic_map must include targets")

	var exterior_semantic_map: Dictionary = materialized_location.get("semantic_map", {}) as Dictionary
	if exterior_semantic_map.is_empty():
		return _fail("v68 materialized exterior must carry semantic_map")
	if int(((materialized_location.get("generation_summary", {}) as Dictionary).get("semantic_validation_error_count", 0))) != 0:
		return _fail("v68 materialized generation summary reports semantic validation errors")

	var population_summary: Dictionary = snapshot.get("population_summary", {}) as Dictionary
	if str(population_summary.get("target_source", "")) != "semantic_map":
		return _fail("v68 population planner must read targets from semantic_map")
	if str(population_summary.get("building_source", "")) != "semantic_map":
		return _fail("v68 population planner must read buildings from semantic_map")

	var anchors_by_location := _anchors_by_location(snapshot)
	if not _semantic_targets_are_resolvable(semantic_map, anchors_by_location):
		return false
	if not _generated_assignments_use_semantic_targets(snapshot):
		return false
	if not _generated_schedules_use_semantic_targets(snapshot):
		return false
	if not _cross_scene_transition_anchors_are_valid(snapshot, anchors_by_location):
		return false
	return true


func _semantic_targets_are_resolvable(semantic_map: Dictionary, anchors_by_location: Dictionary) -> bool:
	var has_public_standing_cells := false
	for target_value in (semantic_map.get("targets", []) as Array):
		var target: Dictionary = target_value as Dictionary
		var target_id := str(target.get("semantic_target_id", target.get("id", "")))
		var location_id := str(target.get("location_id", ""))
		var anchor_id := str(target.get("anchor_id", ""))
		if target_id.is_empty() or location_id.is_empty() or anchor_id.is_empty():
			return _fail("v68 semantic target is missing id/location/anchor")
		var target_key := str(target.get("target_key", ""))
		if target_key != "%s:%s" % [location_id, anchor_id]:
			return _fail("v68 semantic target_key mismatch: %s" % target_id)
		if not (anchors_by_location.get(location_id, {}) as Dictionary).has(anchor_id):
			return _fail("v68 semantic target anchor is not resolvable: %s/%s" % [location_id, anchor_id])
		if str(target.get("standing_mode", "")) == "activity_cells" and (target.get("activity_cells", []) as Array).is_empty():
			return _fail("v68 semantic activity target has no activity cells: %s" % target_id)
		if str(target.get("role", "")) == "public":
			if str(target.get("object_id", "")).is_empty() or (target.get("object_grid_position", {}) as Dictionary).is_empty():
				return _fail("v68 public target must keep object body metadata")
			if (target.get("activity_cells", []) as Array).is_empty():
				return _fail("v68 public target must expose standing cells")
			if _cell_key(target.get("grid_position", {})) == _cell_key(target.get("object_grid_position", {})):
				return _fail("v68 public target grid_position must not be the notice board body")
			has_public_standing_cells = true
	if not has_public_standing_cells:
		return _fail("v68 smoke did not cover public standing cells")
	return true


func _generated_assignments_use_semantic_targets(snapshot: Dictionary) -> bool:
	for assignment_value in (snapshot.get("npc_role_assignments", []) as Array):
		var assignment: Dictionary = assignment_value as Dictionary
		for key in ["home_target", "work_target", "social_target", "rest_target"]:
			var target: Dictionary = assignment.get(key, {}) as Dictionary
			if target.is_empty():
				continue
			if str(target.get("semantic_target_id", "")).is_empty():
				return _fail("v68 assignment target missing semantic_target_id: %s" % key)
			if str(target.get("standing_mode", "")).is_empty():
				return _fail("v68 assignment target missing standing_mode: %s" % key)
	return true


func _generated_schedules_use_semantic_targets(snapshot: Dictionary) -> bool:
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		for entry_value in (definition.get("schedule", []) as Array):
			var entry: Dictionary = entry_value as Dictionary
			if str(entry.get("semantic_target_id", "")).is_empty():
				return _fail("v68 schedule entry missing semantic_target_id: %s" % str(entry.get("id", "")))
			if str(entry.get("standing_mode", "")).is_empty():
				return _fail("v68 schedule entry missing standing_mode: %s" % str(entry.get("id", "")))
			if str(entry.get("standing_mode", "")) == "activity_cells" and (entry.get("activity_cells", []) as Array).is_empty():
				return _fail("v68 schedule activity entry has no activity cells: %s" % str(entry.get("id", "")))
	return true


func _cross_scene_transition_anchors_are_valid(snapshot: Dictionary, anchors_by_location: Dictionary) -> bool:
	var interior_locations := _generated_interior_location_set(snapshot)
	var exterior_id := str(snapshot.get("exterior_location_id", ""))
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		for entry_value in (definition.get("schedule", []) as Array):
			var entry: Dictionary = entry_value as Dictionary
			if str(entry.get("transition_kind", "")) != "cross_location":
				continue
			var entry_id := str(entry.get("id", ""))
			var source_location_id := str(entry.get("source_location_id", ""))
			var target_location_id := str(entry.get("location_id", ""))
			var anchors: Dictionary = entry.get("transition_anchor_by_location", {}) as Dictionary
			if not anchors.has(source_location_id) or not anchors.has(target_location_id):
				return _fail("v68 cross-location entry missing source/target transition anchors: %s" % entry_id)
			if interior_locations.has(source_location_id):
				if str(entry.get("departure_anchor_id", "")) != "interior_exit":
					return _fail("v68 interior departure must use interior_exit: %s" % entry_id)
				if str(anchors.get(source_location_id, "")) != "interior_exit":
					return _fail("v68 interior transition map must use interior_exit: %s" % entry_id)
			if interior_locations.has(target_location_id):
				if str(entry.get("arrival_anchor_id", "")) != "interior_entry":
					return _fail("v68 interior arrival must use interior_entry: %s" % entry_id)
				if str(anchors.get(target_location_id, "")) != "interior_entry":
					return _fail("v68 target interior transition map must use interior_entry: %s" % entry_id)
			if interior_locations.has(source_location_id) and target_location_id == exterior_id:
				var exterior_anchor := str(anchors.get(target_location_id, ""))
				if exterior_anchor.is_empty():
					return _fail("v68 exterior arrival must use the source building door: %s" % entry_id)
				if not exterior_anchor.begins_with("building_entrance_"):
					return _fail("v68 exterior arrival must use a building entrance anchor: %s" % entry_id)
				if str(entry.get("target_type", "")) == "public" and exterior_anchor == str(entry.get("anchor_id", "")):
					return _fail("v68 public exterior arrival must not use the final activity anchor: %s" % entry_id)
			if source_location_id == exterior_id and interior_locations.has(target_location_id):
				var exterior_departure := str(anchors.get(source_location_id, ""))
				if exterior_departure.is_empty() or not exterior_departure.begins_with("building_entrance_"):
					return _fail("v68 exterior departure into an interior must use a building entrance anchor: %s" % entry_id)
	return true


func _generated_interior_location_set(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var location_id := str(manifest.get("interior_location_id", ""))
		if not location_id.is_empty():
			result[location_id] = true
	return result


func _anchors_by_location(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("id", ""))
		if location_id.is_empty():
			continue
		result[location_id] = _anchor_set(location.get("anchors", []) as Array, location.get("entrances", []) as Array)
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var location_id := str(manifest.get("interior_location_id", ""))
		if location_id.is_empty():
			continue
		result[location_id] = _anchor_set(manifest.get("anchors", []) as Array, manifest.get("entrances", []) as Array)
	return result


func _anchor_set(anchor_rows: Array, entrance_rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for anchor_value in anchor_rows:
		var anchor: Dictionary = anchor_value as Dictionary
		var anchor_id := str(anchor.get("id", ""))
		if not anchor_id.is_empty():
			result[anchor_id] = true
	for entrance_value in entrance_rows:
		var entrance: Dictionary = entrance_value as Dictionary
		var entrance_id := str(entrance.get("id", ""))
		if not entrance_id.is_empty():
			result[entrance_id] = true
	return result


func _cell_key(value: Variant) -> String:
	var cell: Dictionary = value as Dictionary
	if cell.is_empty():
		return ""
	return "%d,%d" % [int(cell.get("x", 0)), int(cell.get("y", 0))]


func _fail(message: String) -> bool:
	push_error(message)
	return false
