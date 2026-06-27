extends SceneTree

const WORLD_PATH := "res://data/worlds/test_world.json"


func _initialize() -> void:
	_run()


func _run() -> void:
	var world_service: Variant = _world_service()
	if world_service == null:
		_fail("v64 WorldTransitionService autoload is missing")
		return
	world_service.reset_world()
	var load_result: Dictionary = world_service.load_world(WORLD_PATH)
	if not bool(load_result.get("success", false)):
		_fail("v64 could not load test_world: %s" % str(load_result.get("error", "")))
		return
	if int(load_result.get("location_count", 0)) < 2:
		_fail("v64 world has too few location specs")
		return

	var village_spec: Dictionary = world_service.get_location_spec("test_village")
	var wild_spec: Dictionary = world_service.get_location_spec("test_wild_plain")
	if village_spec.is_empty() or wild_spec.is_empty():
		_fail("v64 world missing test location specs")
		return
	if str(wild_spec.get("location_kind", "")) != "generated_wild":
		_fail("v64 test_wild_plain is not registered as generated_wild")
		return

	var exit_spec: Dictionary = world_service.get_exit_spec("test_village", "wild_gate")
	if exit_spec.is_empty():
		_fail("v64 could not resolve village wild_gate exit")
		return
	if str(exit_spec.get("target_location_id", "")) != "test_wild_plain":
		_fail("v64 wild_gate target location mismatch")
		return
	var target_spawn_id := str(exit_spec.get("target_spawn_id", ""))
	var target_spawn: Dictionary = world_service.get_spawn_spec("test_wild_plain", target_spawn_id)
	if target_spawn.is_empty():
		_fail("v64 wild_gate target spawn could not be resolved")
		return
	if str(target_spawn.get("entrance_id", "")) != "wild_spawn":
		_fail("v64 west_entry spawn did not map to wild_spawn entrance")
		return

	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v64 world start failed: %s" % str(start_result.get("error", "")))
		return
	if world_service.get_current_location_id() != "test_village":
		_fail("v64 start did not set current_location_id to test_village")
		return

	var first_wild: Dictionary = world_service.transition_by_exit_id("wild_gate", false)
	if not bool(first_wild.get("success", false)):
		_fail("v64 first wild transition failed: %s" % str(first_wild.get("error", "")))
		return
	if world_service.get_current_location_id() != "test_wild_plain":
		_fail("v64 first wild transition did not update current_location_id")
		return
	if str(first_wild.get("generated_or_loaded", "")) != "generated":
		_fail("v64 first generated_wild transition should generate, got %s" % str(first_wild.get("generated_or_loaded", "")))
		return
	if int(first_wild.get("seed", 0)) != 6201:
		_fail("v64 generated_wild seed mismatch: %s" % str(first_wild.get("seed", "")))
		return
	if world_service.get_generation_count("test_wild_plain") != 1:
		_fail("v64 generated_wild generation count should be 1 after first entry")
		return
	var first_location_data: Dictionary = world_service.get_registered_location_data("test_wild_plain")
	if first_location_data.is_empty():
		_fail("v64 generated_wild was not registered in runtime state")
		return
	if not _exit_is_near_side(first_location_data, "return_to_village", "west"):
		_fail("v64 return_to_village exit should be generated near the west side")
		return
	var first_fingerprint := _location_fingerprint(first_location_data)

	var return_result: Dictionary = world_service.transition_by_exit_id("return_to_village", false)
	if not bool(return_result.get("success", false)):
		_fail("v64 return transition failed: %s" % str(return_result.get("error", "")))
		return
	if world_service.get_current_location_id() != "test_village":
		_fail("v64 return transition did not update current_location_id")
		return

	var second_wild: Dictionary = world_service.transition_by_exit_id("wild_gate", false)
	if not bool(second_wild.get("success", false)):
		_fail("v64 second wild transition failed: %s" % str(second_wild.get("error", "")))
		return
	if str(second_wild.get("generated_or_loaded", "")) != "runtime":
		_fail("v64 second generated_wild transition should reuse runtime data, got %s" % str(second_wild.get("generated_or_loaded", "")))
		return
	if world_service.get_generation_count("test_wild_plain") != 1:
		_fail("v64 generated_wild regenerated on second entry")
		return
	var second_fingerprint := _location_fingerprint(world_service.get_registered_location_data("test_wild_plain"))
	if first_fingerprint != second_fingerprint:
		_fail("v64 generated_wild fingerprint changed between entries")
		return
	var current_after_second := str(world_service.get_current_location_id())

	var invalid_exit: Dictionary = world_service.transition_by_exit_id("missing_exit", false)
	if bool(invalid_exit.get("success", false)) or str(invalid_exit.get("error", "")).is_empty():
		_fail("v64 invalid exit_id did not return a clear error")
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


func _world_with_invalid_spawn() -> Dictionary:
	var data: Dictionary = _load_json_resource(WORLD_PATH)
	var exits: Array = (data.get("exits", []) as Array).duplicate(true)
	exits.append({
		"exit_id": "bad_spawn_exit",
		"from_location_id": "test_village",
		"target_location_id": "test_wild_plain",
		"target_spawn_id": "missing_spawn",
		"transition_type": "walk",
	})
	data["exits"] = exits
	return data


func _load_json_resource(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


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
