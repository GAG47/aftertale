extends SceneTree

const SETTLEMENT_ID := "smoke_settlement"
const SETTLEMENT_SOURCE_PATH := "res://data/locations/smoke_generated_settlement.json"
const SETTLEMENT_SCENE_PATH := "res://scenes/locations/generated_settlement_location.tscn"
const SPAWN_SETTLEMENT_START := "settlement_start"
const INVALID_INTERIOR_ID := "invalid_spawn_target"


func _initialize() -> void:
	_run()


func _run() -> void:
	var world_service: Variant = _world_service()
	if world_service == null:
		_fail("v64.1 WorldTransitionService autoload is missing")
		return

	world_service.reset_world()
	var load_result: Dictionary = world_service.load_world_from_data(_smoke_world_data())
	if not bool(load_result.get("success", false)):
		_fail("v64.1 could not load smoke world: %s" % str(load_result.get("error", "")))
		return
	if not world_service.get_child_locations(SETTLEMENT_ID).is_empty():
		_fail("v64.1 smoke world should not preload generated building interiors")
		return

	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v64.1 world start failed: %s" % str(start_result.get("error", "")))
		return
	if str(world_service.get_current_location_id()) != SETTLEMENT_ID:
		_fail("v64.1 start did not enter the generated settlement")
		return

	var village_data: Dictionary = world_service.get_registered_location_data(SETTLEMENT_ID)
	if village_data.is_empty():
		_fail("v64.1 smoke settlement was not registered in runtime state")
		return
	var building_rows: Array = village_data.get("buildings", []) as Array
	if building_rows.is_empty():
		_fail("v64.1 generated village has no building rows to close the interior loop")
		return

	var first_building: Dictionary = _first_generated_building_with_world_edges(building_rows)
	if first_building.is_empty():
		_fail("v64.1 generated buildings did not expose world enter/leave ids")
		return
	var first_interior_id := str(first_building.get("interior_location_id", ""))
	var first_enter_exit_id := str(first_building.get("world_enter_exit_id", ""))
	var first_leave_exit_id := str(first_building.get("world_leave_exit_id", ""))

	var dynamic_children: Array = world_service.get_child_locations(SETTLEMENT_ID)
	if dynamic_children.size() < building_rows.size():
		_fail("v64.1 world graph did not import all generated building interiors")
		return
	if not _location_rows_have(dynamic_children, first_interior_id):
		_fail("v64.1 generated child location list did not include the first building interior")
		return

	if not _all_generated_doors_are_world_edges(world_service, village_data):
		return
	if not _all_generated_interiors_round_trip(world_service, village_data):
		return
	if not _offscreen_schedule_states_have_positions():
		return

	var debug_summary: Dictionary = world_service.get_world_debug_summary()
	var child_counts: Dictionary = debug_summary.get("child_counts", {}) as Dictionary
	if int(child_counts.get(SETTLEMENT_ID, 0)) < building_rows.size():
		_fail("v64.1 debug summary did not report all generated child interiors")
		return

	var enter_result: Dictionary = world_service.transition_by_exit_id(first_enter_exit_id, false)
	if not bool(enter_result.get("success", false)):
		_fail("v64.1 dynamic enter transition failed: %s" % str(enter_result.get("error", "")))
		return
	if str(world_service.get_current_location_id()) != first_interior_id:
		_fail("v64.1 dynamic enter transition did not update current_location_id")
		return
	if str(enter_result.get("target_location_kind", "")) != "interior":
		_fail("v64.1 enter transition summary missing interior kind")
		return
	if str(enter_result.get("parent_location_id", "")) != SETTLEMENT_ID:
		_fail("v64.1 enter transition summary missing parent_location_id")
		return
	if str(enter_result.get("transition_type", "")) != "door":
		_fail("v64.1 enter transition summary missing door transition type")
		return

	var interior_data: Dictionary = world_service.get_registered_location_data(first_interior_id)
	if interior_data.is_empty():
		_fail("v64.1 dynamic interior location was not registered in runtime state")
		return
	if not _interior_has_world_return_door(interior_data, first_leave_exit_id):
		_fail("v64.1 generated interior return door is missing world_exit_id")
		return

	var leave_result: Dictionary = world_service.transition_by_exit_id(first_leave_exit_id, false)
	if not bool(leave_result.get("success", false)):
		_fail("v64.1 dynamic leave transition failed: %s" % str(leave_result.get("error", "")))
		return
	if str(world_service.get_current_location_id()) != SETTLEMENT_ID:
		_fail("v64.1 dynamic leave transition did not return to the smoke settlement")
		return
	if str(leave_result.get("target_spawn_id", "")) != str(first_building.get("exterior_return_spawn_id", "")):
		_fail("v64.1 leave transition did not target the generated exterior return spawn")
		return

	var save_state: Dictionary = world_service.get_save_state()
	world_service.apply_save_state(save_state)
	if world_service.get_exit_spec(SETTLEMENT_ID, first_enter_exit_id).is_empty():
		_fail("v64.1 restored save state lost generated interior world edges")
		return

	var invalid_spawn_load: Dictionary = world_service.load_world_from_data(_world_with_invalid_interior_spawn())
	if bool(invalid_spawn_load.get("success", false)) or str(invalid_spawn_load.get("error", "")).find("target spawn") < 0:
		_fail("v64.1 invalid interior spawn did not return a clear error")
		return

	print("v64.1 interior world transition smoke test passed (buildings=%d first_interior=%s enter=%s leave=%s)" % [
		building_rows.size(),
		first_interior_id,
		first_enter_exit_id,
		first_leave_exit_id,
	])
	quit(0)


func _first_generated_building_with_world_edges(building_rows: Array) -> Dictionary:
	for building_value in building_rows:
		var building: Dictionary = building_value as Dictionary
		if not str(building.get("interior_location_id", "")).is_empty() \
				and not str(building.get("world_enter_exit_id", "")).is_empty() \
				and not str(building.get("world_leave_exit_id", "")).is_empty():
			return building.duplicate(true)
	return {}


func _location_rows_have(rows: Array, location_id: String) -> bool:
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		if str(row.get("location_id", "")) == location_id:
			return true
	return false


func _all_generated_doors_are_world_edges(world_service: Variant, village_data: Dictionary) -> bool:
	for object_value in (village_data.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		var world_exit_id := str(object_data.get("world_exit_id", ""))
		if world_exit_id.is_empty():
			continue
		if world_service.get_exit_spec(SETTLEMENT_ID, world_exit_id).is_empty():
			_fail("v64.1 generated door has world_exit_id but no graph edge: %s" % world_exit_id)
			return false
	return true


func _all_generated_interiors_round_trip(world_service: Variant, village_data: Dictionary) -> bool:
	for building_value in (village_data.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var interior_id := str(building.get("interior_location_id", ""))
		var enter_exit_id := str(building.get("world_enter_exit_id", ""))
		var leave_exit_id := str(building.get("world_leave_exit_id", ""))
		var entry_spawn_id := str(building.get("interior_entry_spawn_id", ""))
		var entry_entrance_id := str(building.get("interior_entry_entrance_id", ""))
		var return_spawn_id := str(building.get("exterior_return_spawn_id", ""))
		var return_entrance_id := str(building.get("return_entrance_id", ""))
		if interior_id.is_empty() or enter_exit_id.is_empty() or leave_exit_id.is_empty():
			_fail("v64.1 generated building is missing world interior ids: %s" % str(building.get("id", "")))
			return false
		if entry_spawn_id.is_empty() or entry_entrance_id.is_empty() or return_spawn_id.is_empty() or return_entrance_id.is_empty():
			_fail("v64.1 generated building is missing explicit door spawn semantics: %s" % str(building.get("id", "")))
			return false

		var interior_spec: Dictionary = world_service.get_location_spec(interior_id)
		if interior_spec.is_empty():
			_fail("v64.1 generated interior spec missing from graph: %s" % interior_id)
			return false
		var context: Dictionary = interior_spec.get("generation_context", {}) as Dictionary
		var context_building: Dictionary = context.get("building_instance", {}) as Dictionary
		if str(context_building.get("archetype_id", "")) != str(building.get("archetype_id", "")):
			_fail("v64.1 generated interior context archetype drifted: %s" % interior_id)
			return false
		if str(context.get("entry_spawn_id", "")) != entry_spawn_id or str(context.get("entry_entrance_id", "")) != entry_entrance_id:
			_fail("v64.1 generated interior entry semantics drifted: %s" % interior_id)
			return false

		var enter_edge: Dictionary = world_service.get_exit_spec(SETTLEMENT_ID, enter_exit_id)
		if enter_edge.is_empty():
			_fail("v64.1 generated interior enter edge missing: %s" % enter_exit_id)
			return false
		if str(enter_edge.get("target_location_id", "")) != interior_id or str(enter_edge.get("target_spawn_id", "")) != entry_spawn_id:
			_fail("v64.1 generated interior enter edge target mismatch: %s" % enter_exit_id)
			return false
		var entry_spawn: Dictionary = world_service.get_spawn_spec(interior_id, entry_spawn_id)
		if entry_spawn.is_empty() or str(entry_spawn.get("entrance_id", "")) != entry_entrance_id:
			_fail("v64.1 generated interior entry spawn mismatch: %s" % entry_spawn_id)
			return false

		var leave_edge: Dictionary = world_service.get_exit_spec(interior_id, leave_exit_id)
		if leave_edge.is_empty():
			_fail("v64.1 generated interior leave edge missing: %s" % leave_exit_id)
			return false
		if str(leave_edge.get("target_location_id", "")) != SETTLEMENT_ID or str(leave_edge.get("target_spawn_id", "")) != return_spawn_id:
			_fail("v64.1 generated interior leave edge target mismatch: %s" % leave_exit_id)
			return false
		var return_spawn: Dictionary = world_service.get_spawn_spec(SETTLEMENT_ID, return_spawn_id)
		if return_spawn.is_empty() or str(return_spawn.get("entrance_id", "")) != return_entrance_id:
			_fail("v64.1 generated exterior return spawn mismatch: %s" % return_spawn_id)
			return false

		var enter_result: Dictionary = world_service.transition_by_exit_id(enter_exit_id, false)
		if not bool(enter_result.get("success", false)):
			_fail("v64.1 generated building enter transition failed: %s" % str(enter_result.get("error", "")))
			return false
		var interior_data: Dictionary = world_service.get_registered_location_data(interior_id)
		if str((interior_data.get("state", {}) as Dictionary).get("archetype_id", "")) != str(building.get("archetype_id", "")):
			_fail("v64.1 generated interior data archetype drifted: %s" % interior_id)
			return false
		if str(interior_data.get("default_entrance", "")) != entry_entrance_id:
			_fail("v64.1 generated interior default entrance does not match manifest: %s" % interior_id)
			return false
		if _anchor(interior_data, entry_entrance_id).is_empty():
			_fail("v64.1 generated interior missing declared entry anchor: %s" % entry_entrance_id)
			return false
		if not _interior_has_world_return_door(interior_data, leave_exit_id):
			_fail("v64.1 generated interior return door missing leave edge id: %s" % leave_exit_id)
			return false
		if not _schedule_targets_resolve_inside_location(interior_data):
			return false
		if str(building.get("archetype_id", "")) == "shop" and not _any_character_schedule_targets_anchor(interior_data, "primary"):
			_fail("v64.1 shop interior has no character schedule targeting its primary anchor")
			return false

		var leave_result: Dictionary = world_service.transition_by_exit_id(leave_exit_id, false)
		if not bool(leave_result.get("success", false)):
			_fail("v64.1 generated building leave transition failed: %s" % str(leave_result.get("error", "")))
			return false
		if str(world_service.get_current_location_id()) != SETTLEMENT_ID:
			_fail("v64.1 generated building leave did not return to the smoke settlement")
			return false
	return true


func _interior_has_world_return_door(location_data: Dictionary, leave_exit_id: String) -> bool:
	for object_value in (location_data.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		if str(object_data.get("id", "")) == "interior_return_door" and str(object_data.get("world_exit_id", "")) == leave_exit_id:
			return true
	return false


func _schedule_targets_resolve_inside_location(location_data: Dictionary) -> bool:
	for character_value in (location_data.get("characters", []) as Array):
		var character_data: Dictionary = character_value as Dictionary
		for entry_value in (character_data.get("schedule", []) as Array):
			var entry: Dictionary = entry_value as Dictionary
			if str(entry.get("location_id", "")) != str(location_data.get("id", "")):
				continue
			var anchor_id := str(entry.get("anchor_id", ""))
			if _anchor(location_data, anchor_id).is_empty() and not entry.has("grid_position"):
				_fail("v64.1 schedule target has neither anchor nor grid_position: %s/%s" % [
					str(character_data.get("id", "")),
					str(entry.get("id", "")),
				])
				return false
	return true


func _any_character_schedule_targets_anchor(location_data: Dictionary, anchor_id: String) -> bool:
	for character_value in (location_data.get("characters", []) as Array):
		var character_data: Dictionary = character_value as Dictionary
		for entry_value in (character_data.get("schedule", []) as Array):
			var entry: Dictionary = entry_value as Dictionary
			if str(entry.get("location_id", "")) == str(location_data.get("id", "")) and str(entry.get("anchor_id", "")) == anchor_id:
				return true
	return false


func _offscreen_schedule_states_have_positions() -> bool:
	var schedule_system: Variant = root.get_node_or_null("NpcScheduleSystem")
	if schedule_system == null:
		_fail("v64.1 NpcScheduleSystem autoload is missing")
		return false
	schedule_system.settle_offscreen_location(SETTLEMENT_SOURCE_PATH, 0, 8 * 60, SETTLEMENT_ID)
	var summaries: Dictionary = schedule_system.get_offscreen_summary()
	for summary_value in summaries.values():
		var summary: Dictionary = summary_value as Dictionary
		for character_value in (summary.get("characters", []) as Array):
			var character_state: Dictionary = character_value as Dictionary
			var position: Dictionary = character_state.get("grid_position", {}) as Dictionary
			if position.is_empty():
				_fail("v64.1 offscreen schedule produced empty grid_position: %s/%s" % [
					str(character_state.get("character_id", "")),
					str(character_state.get("location_id", "")),
				])
				return false
	return true


func _anchor(location_data: Dictionary, anchor_id: String) -> Dictionary:
	for anchor_value in (location_data.get("anchors", []) as Array):
		var anchor: Dictionary = anchor_value as Dictionary
		if str(anchor.get("id", "")) == anchor_id:
			return anchor
	return {}


func _world_with_invalid_interior_spawn() -> Dictionary:
	var data: Dictionary = _smoke_world_data()
	var locations: Array = (data.get("locations", []) as Array).duplicate(true)
	locations.append({
		"location_id": INVALID_INTERIOR_ID,
		"display_name": "Invalid Spawn Interior",
		"location_kind": "interior",
		"source_type": "generated",
		"scene_path": "res://scenes/locations/generated_building_interior.tscn",
		"data_path": "res://data/locations/generated_building_interior.json",
		"generator_id": "building_interior",
		"generator_profile_id": "residential",
		"parent_location_id": SETTLEMENT_ID,
	})
	data["locations"] = locations
	var exits: Array = (data.get("exits", []) as Array).duplicate(true)
	exits.append({
		"exit_id": "bad_interior_spawn_exit",
		"from_location_id": SETTLEMENT_ID,
		"target_location_id": INVALID_INTERIOR_ID,
		"target_spawn_id": "missing_interior_spawn",
		"transition_type": "door",
	})
	data["exits"] = exits
	return data


func _smoke_world_data() -> Dictionary:
	return {
		"world_id": "smoke_interior_world",
		"world_seed": 6411,
		"start_location_id": SETTLEMENT_ID,
		"start_spawn_id": SPAWN_SETTLEMENT_START,
		"locations": [
			{
				"location_id": SETTLEMENT_ID,
				"display_name": "Smoke Settlement",
				"location_kind": "static",
				"source_type": "static_scene",
				"scene_path": SETTLEMENT_SCENE_PATH,
				"data_path": SETTLEMENT_SOURCE_PATH,
			},
		],
		"spawns": [
			{
				"location_id": SETTLEMENT_ID,
				"spawn_id": SPAWN_SETTLEMENT_START,
				"entrance_id": "plaza",
				"facing": "down",
				"tags": ["start"],
			},
		],
		"exits": [],
	}


func _world_service() -> Variant:
	return root.get_node_or_null("WorldTransitionService")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
