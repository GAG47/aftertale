extends SceneTree

const SETTLEMENT_ID := "smoke_settlement"
const WILD_A_ID := "smoke_wild_a"
const WILD_B_ID := "smoke_wild_b"
const SETTLEMENT_SOURCE_PATH := "res://data/locations/smoke_generated_settlement.json"
const SETTLEMENT_SCENE_PATH := "res://scenes/locations/generated_settlement_location.tscn"
const WILD_SCENE_PATH := "res://scenes/locations/generated_wild_location.tscn"
const EDGE_SETTLEMENT_TO_WILD := "edge_settlement_to_wild_a"
const EDGE_WILD_TO_SETTLEMENT := "edge_wild_a_to_settlement"
const EDGE_WILD_A_TO_B := "edge_wild_a_to_wild_b"
const EDGE_WILD_B_TO_A := "edge_wild_b_to_wild_a"
const SPAWN_SETTLEMENT_START := "settlement_start"
const SPAWN_SETTLEMENT_RETURN := "settlement_return"
const SPAWN_WILD_A_ENTRY := "wild_a_entry"
const SPAWN_WILD_A_FROM_B := "wild_a_from_b"
const SPAWN_WILD_B_ENTRY := "wild_b_entry"


func _initialize() -> void:
	_run()


func _run() -> void:
	var world_service: Variant = _world_service()
	if world_service == null:
		_fail("v64 WorldTransitionService autoload is missing")
		return
	world_service.reset_world()
	var load_result: Dictionary = world_service.load_world_from_data(_smoke_world_data())
	if not bool(load_result.get("success", false)):
		_fail("v64 could not load generated smoke world: %s" % str(load_result.get("error", "")))
		return
	if int(load_result.get("location_count", 0)) < 3:
		_fail("v64 world has too few location specs")
		return

	var settlement_spec: Dictionary = world_service.get_location_spec(SETTLEMENT_ID)
	var wild_spec: Dictionary = world_service.get_location_spec(WILD_A_ID)
	if settlement_spec.is_empty() or wild_spec.is_empty():
		_fail("v64 world missing smoke location specs")
		return
	if str(wild_spec.get("location_kind", "")) != "generated_wild":
		_fail("v64 smoke wild node is not registered as generated_wild")
		return

	var exit_spec: Dictionary = world_service.get_exit_spec(SETTLEMENT_ID, EDGE_SETTLEMENT_TO_WILD)
	if exit_spec.is_empty():
		_fail("v64 could not resolve settlement to wild edge")
		return
	if str(exit_spec.get("target_location_id", "")) != WILD_A_ID:
		_fail("v64 settlement edge target location mismatch")
		return
	var target_spawn_id := str(exit_spec.get("target_spawn_id", ""))
	var target_spawn: Dictionary = world_service.get_spawn_spec(WILD_A_ID, target_spawn_id)
	if target_spawn.is_empty():
		_fail("v64 settlement edge target spawn could not be resolved")
		return
	if str(target_spawn.get("entrance_id", "")) != SPAWN_WILD_A_ENTRY:
		_fail("v64 wild entry spawn did not map to the generated entrance")
		return

	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v64 world start failed: %s" % str(start_result.get("error", "")))
		return
	if world_service.get_current_location_id() != SETTLEMENT_ID:
		_fail("v64 start did not set current_location_id to smoke settlement")
		return

	var first_wild: Dictionary = world_service.transition_by_exit_id(EDGE_SETTLEMENT_TO_WILD, false)
	if not bool(first_wild.get("success", false)):
		_fail("v64 first wild transition failed: %s" % str(first_wild.get("error", "")))
		return
	if world_service.get_current_location_id() != WILD_A_ID:
		_fail("v64 first wild transition did not update current_location_id")
		return
	if str(first_wild.get("generated_or_loaded", "")) != "generated":
		_fail("v64 first generated_wild transition should generate, got %s" % str(first_wild.get("generated_or_loaded", "")))
		return
	if int(first_wild.get("seed", 0)) != 6201:
		_fail("v64 generated_wild seed mismatch: %s" % str(first_wild.get("seed", "")))
		return
	if world_service.get_generation_count(WILD_A_ID) != 1:
		_fail("v64 generated_wild generation count should be 1 after first entry")
		return
	var first_location_data: Dictionary = world_service.get_registered_location_data(WILD_A_ID)
	if first_location_data.is_empty():
		_fail("v64 generated_wild was not registered in runtime state")
		return
	if not _exit_is_near_side(first_location_data, EDGE_WILD_TO_SETTLEMENT, "west"):
		_fail("v64 return edge should be generated near the west side")
		return
	var first_fingerprint := _location_fingerprint(first_location_data)

	var return_result: Dictionary = world_service.transition_by_exit_id(EDGE_WILD_TO_SETTLEMENT, false)
	if not bool(return_result.get("success", false)):
		_fail("v64 return transition failed: %s" % str(return_result.get("error", "")))
		return
	if world_service.get_current_location_id() != SETTLEMENT_ID:
		_fail("v64 return transition did not update current_location_id")
		return

	var second_wild: Dictionary = world_service.transition_by_exit_id(EDGE_SETTLEMENT_TO_WILD, false)
	if not bool(second_wild.get("success", false)):
		_fail("v64 second wild transition failed: %s" % str(second_wild.get("error", "")))
		return
	if str(second_wild.get("generated_or_loaded", "")) != "runtime":
		_fail("v64 second generated_wild transition should reuse runtime data, got %s" % str(second_wild.get("generated_or_loaded", "")))
		return
	if world_service.get_generation_count(WILD_A_ID) != 1:
		_fail("v64 generated_wild regenerated on second entry")
		return
	var second_fingerprint := _location_fingerprint(world_service.get_registered_location_data(WILD_A_ID))
	if first_fingerprint != second_fingerprint:
		_fail("v64 generated_wild fingerprint changed between entries")
		return
	var current_after_second := str(world_service.get_current_location_id())

	var invalid_exit: Dictionary = world_service.transition_by_exit_id("missing_exit", false)
	if bool(invalid_exit.get("success", false)) or str(invalid_exit.get("error", "")).is_empty():
		_fail("v64 invalid exit_id did not return a clear error")
		return

	var invalid_exit_with_legacy_target: Dictionary = world_service.transition_by_exit_data({
		"id": "missing_exit_with_legacy_target",
		"world_exit_id": "missing_exit_with_legacy_target",
		"target_scene_path": SETTLEMENT_SCENE_PATH,
		"target_entrance_id": "legacy_target",
	}, false)
	if bool(invalid_exit_with_legacy_target.get("success", false)):
		_fail("v64 active world transition used target_scene_path as a fallback")
		return

	var invalid_spawn_load: Dictionary = world_service.load_world_from_data(_world_with_invalid_spawn())
	if bool(invalid_spawn_load.get("success", false)) or str(invalid_spawn_load.get("error", "")).find("target spawn") < 0:
		_fail("v64 invalid target_spawn_id did not return a clear error")
		return

	print("v64 world location network smoke test passed (first=%s second=%s seed=%d current=%s fingerprint=%s)" % [
		str(first_wild.get("generated_or_loaded", "")),
		str(second_wild.get("generated_or_loaded", "")),
		int(first_wild.get("seed", 0)),
		current_after_second,
		first_fingerprint.substr(0, 16),
	])
	quit(0)


func _smoke_world_data() -> Dictionary:
	return {
		"world_id": "smoke_world_network",
		"world_seed": 6401,
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
			{
				"location_id": WILD_A_ID,
				"display_name": "Smoke Wild A",
				"location_kind": "generated_wild",
				"source_type": "generated",
				"scene_path": WILD_SCENE_PATH,
				"generator_id": "wild_terrain",
				"generator_profile_id": "plain",
				"seed": 6201,
				"size": { "width": 64, "height": 64 },
			},
			{
				"location_id": WILD_B_ID,
				"display_name": "Smoke Wild B",
				"location_kind": "generated_wild",
				"source_type": "generated",
				"scene_path": WILD_SCENE_PATH,
				"generator_id": "wild_terrain",
				"generator_profile_id": "riverbank",
				"seed": 6209,
				"size": { "width": 64, "height": 64 },
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
			{
				"location_id": SETTLEMENT_ID,
				"spawn_id": SPAWN_SETTLEMENT_RETURN,
				"entrance_id": "from_wild",
				"facing": "left",
				"tags": ["return_from_wild"],
			},
			{
				"location_id": WILD_A_ID,
				"spawn_id": SPAWN_WILD_A_ENTRY,
				"entrance_id": SPAWN_WILD_A_ENTRY,
				"facing": "right",
				"tags": ["from_settlement"],
			},
			{
				"location_id": WILD_A_ID,
				"spawn_id": SPAWN_WILD_A_FROM_B,
				"entrance_id": SPAWN_WILD_A_FROM_B,
				"facing": "left",
				"tags": ["from_wild_b"],
			},
			{
				"location_id": WILD_B_ID,
				"spawn_id": SPAWN_WILD_B_ENTRY,
				"entrance_id": SPAWN_WILD_B_ENTRY,
				"facing": "right",
				"tags": ["from_wild_a"],
			},
		],
		"exits": [
			{
				"exit_id": EDGE_SETTLEMENT_TO_WILD,
				"from_location_id": SETTLEMENT_ID,
				"from_anchor_id": "settlement_exit_east",
				"target_location_id": WILD_A_ID,
				"target_spawn_id": SPAWN_WILD_A_ENTRY,
				"transition_type": "walk",
				"enabled": true,
				"paired_exit_id": EDGE_WILD_TO_SETTLEMENT,
				"metadata": { "side": "east", "facing": "right" },
			},
			{
				"exit_id": EDGE_WILD_TO_SETTLEMENT,
				"from_location_id": WILD_A_ID,
				"target_location_id": SETTLEMENT_ID,
				"target_spawn_id": SPAWN_SETTLEMENT_RETURN,
				"transition_type": "walk",
				"enabled": true,
				"paired_exit_id": EDGE_SETTLEMENT_TO_WILD,
				"metadata": { "side": "west", "facing": "left" },
			},
			{
				"exit_id": EDGE_WILD_A_TO_B,
				"from_location_id": WILD_A_ID,
				"target_location_id": WILD_B_ID,
				"target_spawn_id": SPAWN_WILD_B_ENTRY,
				"transition_type": "walk",
				"enabled": true,
				"paired_exit_id": EDGE_WILD_B_TO_A,
				"metadata": { "side": "east", "facing": "right" },
			},
			{
				"exit_id": EDGE_WILD_B_TO_A,
				"from_location_id": WILD_B_ID,
				"target_location_id": WILD_A_ID,
				"target_spawn_id": SPAWN_WILD_A_FROM_B,
				"transition_type": "walk",
				"enabled": true,
				"paired_exit_id": EDGE_WILD_A_TO_B,
				"metadata": { "side": "west", "facing": "left" },
			},
		],
	}


func _world_with_invalid_spawn() -> Dictionary:
	var data: Dictionary = _smoke_world_data()
	var exits: Array = (data.get("exits", []) as Array).duplicate(true)
	exits.append({
		"exit_id": "bad_spawn_exit",
		"from_location_id": SETTLEMENT_ID,
		"target_location_id": WILD_A_ID,
		"target_spawn_id": "missing_spawn",
		"transition_type": "walk",
	})
	data["exits"] = exits
	return data


func _location_fingerprint(location_data: Dictionary) -> String:
	var parts: Array[String] = [
		str(location_data.get("id", "")),
		str((location_data.get("generation_summary", {}) as Dictionary).get("seed", "")),
	]
	for row_value in (location_data.get("tiles", []) as Array):
		parts.append(str(row_value))
	for exit_value in (location_data.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		parts.append("%s:%s" % [
			str(exit_data.get("id", "")),
			str(exit_data.get("target_entrance_id", "")),
		])
	return "|".join(parts)


func _exit_is_near_side(location_data: Dictionary, exit_id: String, side: String) -> bool:
	for exit_value in (location_data.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		if str(exit_data.get("id", "")) != exit_id:
			continue
		var cell: Dictionary = exit_data.get("grid_position", {}) as Dictionary
		var size: Dictionary = location_data.get("size", {}) as Dictionary
		var x := int(cell.get("x", 0))
		var y := int(cell.get("y", 0))
		var width := int(size.get("width", 1))
		var height := int(size.get("height", 1))
		var edge_band := maxi(3, int(ceil(float(maxi(width, height)) * 0.20)))
		match side:
			"west", "left":
				return x <= edge_band
			"east", "right":
				return x >= width - 1 - edge_band
			"north", "up":
				return y <= edge_band
			"south", "down":
				return y >= height - 1 - edge_band
			_:
				return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _world_service() -> Variant:
	return root.get_node_or_null("WorldTransitionService")
