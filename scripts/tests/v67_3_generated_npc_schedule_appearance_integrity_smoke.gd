extends RefCounted

const StoreScript := preload("res://scripts/systems/settlements/generated_settlement_store.gd")
const BASIC_INTERIOR_SCENE := "res://scenes/locations/generated_basic_interior.tscn"

const SETTLEMENT_ID := "v67_3_integrity_settlement"
const TEMPLATE_ID := "v67_3_integrity_template"
const WORLD_ID := "v67_3_integrity_world"
const SAVE_PATH := "user://saves/v67_3_slot.json"
const SOURCE_PATH := "res://data/locations/v67_3_integrity_template.json"
const OVERLAP_LOCATION_PATH := "user://v67_3_overlap_location.json"
const OVERLAP_CHARACTER_A_PATH := "user://v67_3_overlap_a.json"
const OVERLAP_CHARACTER_B_PATH := "user://v67_3_overlap_b.json"


func run(root: Node) -> bool:
	if root != null and root.has_node("WorldRoot"):
		SceneLoader.configure(root.get_node("WorldRoot"))

	SaveManager.configure_active_save_context(SAVE_PATH, WORLD_ID)
	SaveManager.clear_generated_settlement_index()
	GameState.start_new_session("v67_3_integrity_session")
	TimeManager.reset()
	NpcScheduleSystem.reset_schedule_state()
	DefinitionLoader.clear_cache()
	DefinitionLoader.clear_generated_runtime_cache()

	var store: RefCounted = StoreScript.new()
	store.delete_snapshot(SETTLEMENT_ID)
	DefinitionLoader.clear_generated_runtime_cache()

	var first := DefinitionLoader.materialize_location(_source(), SOURCE_PATH, {
		"settlement_instance_id": SETTLEMENT_ID,
	})
	if first.is_empty():
		return _fail("v67.3 could not materialize generated settlement")
	var snapshot: Dictionary = store.load_snapshot(SETTLEMENT_ID)
	if snapshot.is_empty():
		return _fail("v67.3 snapshot file was not written")

	if not _generated_npcs_have_map_sprite(snapshot):
		return false
	if not _assignments_are_valid(snapshot):
		return false
	if not _schedule_integrity_is_valid(snapshot):
		return false
	if not _entrance_and_exit_targets_are_exposed(snapshot):
		return false
	if not _location_root_spawn_avoids_blocking_overlap(root, snapshot):
		return false

	DefinitionLoader.clear_cache()
	DefinitionLoader.clear_generated_runtime_cache()
	var second := DefinitionLoader.materialize_location(_source(), SOURCE_PATH, {
		"settlement_instance_id": SETTLEMENT_ID,
	})
	if second.is_empty():
		return _fail("v67.3 second materialization failed")
	var second_snapshot: Dictionary = store.load_snapshot(SETTLEMENT_ID)
	if not _second_load_preserves_integrity(snapshot, second_snapshot):
		return false

	print("v67.3 generated npc schedule appearance integrity smoke test passed")
	return true


func _source() -> Dictionary:
	return {
		"id": SETTLEMENT_ID,
		"settlement_template_id": TEMPLATE_ID,
		"display_name": "V67.3 Integrity Template",
		"tile_size": 32,
		"generator": {
			"type": "settlement",
			"persistent_generated_settlement": true,
			"settlement_id": SETTLEMENT_ID,
			"settlement_template_id": TEMPLATE_ID,
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


func _generated_npcs_have_map_sprite(snapshot: Dictionary) -> bool:
	var definitions: Array = snapshot.get("npc_definitions", []) as Array
	if definitions.is_empty():
		return _fail("v67.3 snapshot must include generated npc definitions")
	for definition_value in definitions:
		var definition: Dictionary = definition_value as Dictionary
		var appearance: Dictionary = definition.get("appearance", {}) as Dictionary
		if str(appearance.get("display_mode", "")) != "map_sprite":
			return _fail("v67.3 generated npc must use map_sprite display mode: %s" % str(definition.get("id", "")))
		var map_sprite: Dictionary = appearance.get("map_sprite", {}) as Dictionary
		var source := str(map_sprite.get("source", ""))
		if source.is_empty() or not ResourceLoader.exists(source):
			return _fail("v67.3 map_sprite source must exist: %s" % source)
		var character_source := str(definition.get("source", ""))
		if character_source.is_empty() or not FileAccess.file_exists(character_source):
			return _fail("v67.3 generated character source file is missing: %s" % character_source)
	return true


func _assignments_are_valid(snapshot: Dictionary) -> bool:
	var single_capacity_claims: Dictionary = {}
	for assignment_value in (snapshot.get("npc_role_assignments", []) as Array):
		var assignment: Dictionary = assignment_value as Dictionary
		var npc_id := str(assignment.get("npc_id", ""))
		for target_key in ["home_target", "work_target", "social_target", "rest_target"]:
			var target: Dictionary = assignment.get(target_key, {}) as Dictionary
			if str(target.get("location_id", "")).is_empty() or str(target.get("anchor_id", "")).is_empty():
				if (assignment.get("fallbacks", []) as Array).is_empty():
					return _fail("v67.3 assignment target missing without fallback: %s/%s" % [npc_id, target_key])
		for claim_value in (assignment.get("assigned_target_slots", []) as Array):
			var claim: Dictionary = claim_value as Dictionary
			var key := str(claim.get("target_key", ""))
			var capacity := int(claim.get("capacity", 1))
			if key.is_empty():
				return _fail("v67.3 assignment claim missing target_key: %s" % npc_id)
			if capacity <= 1:
				if single_capacity_claims.has(key) and str(single_capacity_claims.get(key, "")) != npc_id:
					return _fail("v67.3 single-capacity target claimed by multiple NPCs: %s" % key)
				single_capacity_claims[key] = npc_id
	return true


func _schedule_integrity_is_valid(snapshot: Dictionary) -> bool:
	var anchors_by_location := _anchors_by_location(snapshot)
	var occupancy_rows: Array[Dictionary] = []
	var has_cross_location := false
	var has_multi_capacity_slot := false
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		var npc_id := str(definition.get("id", ""))
		for entry_value in (definition.get("schedule", []) as Array):
			var entry: Dictionary = entry_value as Dictionary
			var location_id := str(entry.get("location_id", ""))
			var anchor_id := str(entry.get("anchor_id", ""))
			if location_id.is_empty() or anchor_id.is_empty():
				return _fail("v67.3 schedule entry missing location_id or anchor_id")
			if not (anchors_by_location.get(location_id, {}) as Dictionary).has(anchor_id):
				return _fail("v67.3 schedule entry anchor is not resolvable: %s/%s" % [location_id, anchor_id])
			if str(entry.get("target_location_id", "")).is_empty() or str(entry.get("target_anchor_id", "")).is_empty():
				return _fail("v67.3 schedule entry missing target metadata: %s" % str(entry.get("id", "")))
			if str(entry.get("source_location_id", "")).is_empty() or str(entry.get("source_anchor_id", "")).is_empty():
				return _fail("v67.3 schedule entry missing source metadata: %s" % str(entry.get("id", "")))
			if str(entry.get("transition_kind", "")) == "cross_location":
				has_cross_location = true
				if (entry.get("transition_anchor_by_location", {}) as Dictionary).is_empty():
					return _fail("v67.3 cross-location entry missing transition_anchor_by_location")
				if not _transition_anchors_are_resolvable(entry, anchors_by_location):
					return false
			if int(entry.get("target_capacity", 1)) > 1:
				if not bool(entry.get("uses_capacity_slot", false)):
					return _fail("v67.3 multi-capacity schedule entry must resolve to a concrete slot cell")
				has_multi_capacity_slot = true

			var cell_key := _entry_cell_key(entry, anchors_by_location)
			if cell_key.is_empty():
				return _fail("v67.3 schedule entry did not resolve to a tile: %s" % str(entry.get("id", "")))
			for interval in _entry_intervals(entry):
				var row := {
					"npc_id": npc_id,
					"entry_id": str(entry.get("id", "")),
					"location_id": location_id,
					"cell_key": cell_key,
					"start": int(interval.get("start", 0)),
					"end": int(interval.get("end", 0)),
				}
				for existing_value in occupancy_rows:
					var existing: Dictionary = existing_value as Dictionary
					if str(existing.get("location_id", "")) != location_id or str(existing.get("cell_key", "")) != cell_key:
						continue
					if _intervals_overlap(row, existing):
						return _fail("v67.3 schedule occupancy conflict: %s and %s at %s/%s" % [
							str(existing.get("entry_id", "")),
							str(row.get("entry_id", "")),
							location_id,
							cell_key,
						])
				occupancy_rows.append(row)
	if not has_cross_location:
		return _fail("v67.3 generated schedules must include cross-location transition metadata")
	if not has_multi_capacity_slot:
		return _fail("v67.3 smoke must cover at least one multi-capacity public/social slot")
	return true


func _transition_anchors_are_resolvable(entry: Dictionary, anchors_by_location: Dictionary) -> bool:
	var anchors: Dictionary = entry.get("transition_anchor_by_location", {}) as Dictionary
	for location_id_value in anchors.keys():
		var location_id := str(location_id_value)
		var anchor_id := str(anchors.get(location_id_value, ""))
		if location_id.is_empty() or anchor_id.is_empty():
			return _fail("v67.3 transition anchor metadata contains empty location or anchor")
		if not (anchors_by_location.get(location_id, {}) as Dictionary).has(anchor_id):
			return _fail("v67.3 transition anchor is not resolvable: %s/%s" % [location_id, anchor_id])
	return true


func _entrance_and_exit_targets_are_exposed(snapshot: Dictionary) -> bool:
	var exterior_id := str(snapshot.get("exterior_location_id", ""))
	var exterior_has_building_entrance := false
	for target_value in (snapshot.get("schedule_targets", []) as Array):
		var target: Dictionary = target_value as Dictionary
		var role := str(target.get("role", ""))
		if str(target.get("location_id", "")) == exterior_id and role in ["building_entrance", "exterior_transition"]:
			exterior_has_building_entrance = true
	if not exterior_has_building_entrance:
		return _fail("v67.3 exterior must expose building entrance schedule target")

	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var roles: Dictionary = {}
		for target_value in (manifest.get("schedule_targets", []) as Array):
			var target: Dictionary = target_value as Dictionary
			roles[str(target.get("role", ""))] = true
		if not roles.has("interior_entry") or not roles.has("interior_exit"):
			return _fail("v67.3 generated interior must expose entry and exit schedule targets")
	return true


func _location_root_spawn_avoids_blocking_overlap(root: Node, snapshot: Dictionary) -> bool:
	if root == null:
		return _fail("v67.3 LocationRoot spawn test needs root")
	var definitions: Array = snapshot.get("npc_definitions", []) as Array
	if definitions.size() < 2:
		return _fail("v67.3 overlap test needs at least two generated NPC definitions")
	var base_location := _first_generated_interior_location(snapshot)
	if base_location.is_empty():
		return _fail("v67.3 overlap test could not resolve a generated interior")

	var definition_a: Dictionary = (definitions[0] as Dictionary).duplicate(true)
	var definition_b: Dictionary = (definitions[1] as Dictionary).duplicate(true)
	definition_a["id"] = "v67_3_overlap_a"
	definition_b["id"] = "v67_3_overlap_b"
	definition_a["schedule"] = []
	definition_b["schedule"] = []
	if not _write_json(OVERLAP_CHARACTER_A_PATH, definition_a):
		return false
	if not _write_json(OVERLAP_CHARACTER_B_PATH, definition_b):
		return false

	var location_data := base_location.duplicate(true)
	location_data["id"] = "v67_3_overlap_location"
	location_data["display_name"] = "V67.3 Overlap Location"
	location_data["characters"] = [
		{
			"id": "v67_3_overlap_a",
			"source": OVERLAP_CHARACTER_A_PATH,
			"grid_position": { "x": 3, "y": 3 },
			"facing": "down",
		},
		{
			"id": "v67_3_overlap_b",
			"source": OVERLAP_CHARACTER_B_PATH,
			"grid_position": { "x": 3, "y": 3 },
			"facing": "down",
		},
	]
	if not _write_json(OVERLAP_LOCATION_PATH, location_data):
		return false

	var scene := load(BASIC_INTERIOR_SCENE) as PackedScene
	if scene == null:
		return _fail("v67.3 could not load basic location shell")
	SceneLoader.set_pending_location_context({
		"target_location_id": "v67_3_overlap_location",
	})
	var instance := scene.instantiate()
	instance.location_data_path = OVERLAP_LOCATION_PATH
	root.add_child(instance)
	var grid: LocationGrid = instance.get_location_grid() if instance.has_method("get_location_grid") else null
	if grid == null:
		_cleanup_instance(instance)
		return _fail("v67.3 LocationRoot did not expose grid")
	var character_a: CharacterEntity = grid.get_character_by_id("v67_3_overlap_a")
	var character_b: CharacterEntity = grid.get_character_by_id("v67_3_overlap_b")
	if character_a == null or character_b == null:
		_cleanup_instance(instance)
		return _fail("v67.3 overlap test characters did not spawn")
	var cell_a := _cell_key_from_vector(character_a.grid_position)
	var cell_b := _cell_key_from_vector(character_b.grid_position)
	_cleanup_instance(instance)
	if cell_a == cell_b:
		return _fail("v67.3 LocationRoot left two blocking NPCs on the same tile")
	return true


func _second_load_preserves_integrity(first: Dictionary, second: Dictionary) -> bool:
	if second.is_empty():
		return _fail("v67.3 second snapshot is empty")
	if JSON.stringify(_npc_signature(first)) != JSON.stringify(_npc_signature(second)):
		return _fail("v67.3 second load changed generated NPC IDs or appearance")
	if JSON.stringify(_assignment_signature(first)) != JSON.stringify(_assignment_signature(second)):
		return _fail("v67.3 second load changed generated role assignments")
	if not _schedule_integrity_is_valid(second):
		return false
	return true


func _anchors_by_location(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		result[str(location.get("id", ""))] = _anchor_map(location.get("anchors", []) as Array)
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		result[str(manifest.get("interior_location_id", ""))] = _anchor_map(manifest.get("anchors", []) as Array)
	return result


func _anchor_map(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		result[str(row.get("id", ""))] = row.duplicate(true)
	return result


func _entry_cell_key(entry: Dictionary, anchors_by_location: Dictionary) -> String:
	var grid_position: Dictionary = entry.get("grid_position", {}) as Dictionary
	if not grid_position.is_empty():
		return _cell_key_from_dict(grid_position)
	var location_id := str(entry.get("location_id", ""))
	var anchor_id := str(entry.get("anchor_id", ""))
	var anchor: Dictionary = (anchors_by_location.get(location_id, {}) as Dictionary).get(anchor_id, {}) as Dictionary
	var anchor_position: Dictionary = anchor.get("grid_position", {}) as Dictionary
	if anchor_position.is_empty():
		return ""
	return _cell_key_from_dict(anchor_position)


func _entry_intervals(entry: Dictionary) -> Array[Dictionary]:
	var start_minutes := _time_to_minutes(str(entry.get("start", "00:00")))
	var end_minutes := _time_to_minutes(str(entry.get("end", "00:00")))
	if end_minutes < start_minutes:
		return [
			{ "start": start_minutes, "end": 1440 },
			{ "start": 0, "end": end_minutes },
		]
	return [{ "start": start_minutes, "end": end_minutes }]


func _intervals_overlap(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("start", 0)) <= int(b.get("end", 0)) and int(b.get("start", 0)) <= int(a.get("end", 0))


func _time_to_minutes(value: String) -> int:
	var parts := value.split(":")
	if parts.size() < 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])


func _first_generated_interior_location(snapshot: Dictionary) -> Dictionary:
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var location_id := str(manifest.get("interior_location_id", ""))
		if location_id.is_empty():
			continue
		var resolved := DefinitionLoader.resolve_location_by_id(location_id)
		if not resolved.is_empty():
			return resolved
	return {}


func _npc_signature(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		result.append({
			"id": str(definition.get("id", "")),
			"appearance": (definition.get("appearance", {}) as Dictionary).duplicate(true),
			"schedule": (definition.get("schedule", []) as Array).duplicate(true),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


func _assignment_signature(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for assignment_value in (snapshot.get("npc_role_assignments", []) as Array):
		var assignment: Dictionary = assignment_value as Dictionary
		result.append({
			"id": str(assignment.get("id", "")),
			"npc_id": str(assignment.get("npc_id", "")),
			"home_target": (assignment.get("home_target", {}) as Dictionary).duplicate(true),
			"work_target": (assignment.get("work_target", {}) as Dictionary).duplicate(true),
			"social_target": (assignment.get("social_target", {}) as Dictionary).duplicate(true),
			"rest_target": (assignment.get("rest_target", {}) as Dictionary).duplicate(true),
			"assigned_target_slots": (assignment.get("assigned_target_slots", []) as Array).duplicate(true),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


func _write_json(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("v67.3 could not write JSON file: %s" % path)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	DefinitionLoader.clear_cache(path)
	return true


func _cell_key_from_dict(value: Dictionary) -> String:
	return "%d,%d" % [int(value.get("x", 0)), int(value.get("y", 0))]


func _cell_key_from_vector(value: Vector2i) -> String:
	return "%d,%d" % [value.x, value.y]


func _cleanup_instance(instance: Node) -> void:
	if instance == null:
		return
	if instance.get_parent() != null:
		instance.get_parent().remove_child(instance)
	instance.queue_free()


func _fail(message: String) -> bool:
	push_error(message)
	return false
