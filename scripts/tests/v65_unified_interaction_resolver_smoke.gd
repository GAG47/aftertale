extends RefCounted

const BASIC_LOCATION_SCENE := "res://scenes/locations/generated_basic_interior.tscn"
const GENERATED_SETTLEMENT_SCENE := "res://scenes/locations/generated_settlement.tscn"
const TEST_FIELD_DATA := "res://data/locations/test_field.json"
const BASIC_INTERIOR_ID := "generated_basic_interior"
const TileSceneCompilerScript := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")


func run(root: Node) -> bool:
	GameState.start_new_session()
	TimeManager.reset()
	DefinitionLoader.clear_cache()
	if not _test_current_and_facing_bed(root):
		return false
	if not _test_current_and_facing_drop(root):
		return false
	if not _test_priority_and_stable_sort(root):
		return false
	if not _test_concrete_facility_candidates(root):
		return false
	if not _test_generated_wall_door_and_return(root):
		return false
	if not _run_previous_phase_smokes(root):
		return false
	print("v65 unified interaction resolver smoke test passed")
	return true


func _test_current_and_facing_bed(root: Node) -> bool:
	var manifest := _first_generated_bed_manifest()
	if manifest.is_empty():
		return _fail("v65 needs a generated concrete interior with a bed")
	var interior: Node = _instantiate_generated_interior(root, manifest)
	if interior == null:
		return _fail("v65 could not instantiate generated concrete interior")
	var interior_id := str(manifest.get("interior_location_id", ""))
	if interior_id == BASIC_INTERIOR_ID:
		_cleanup_instance(interior)
		return _fail("generated bed test must not use generated_basic_interior as location id")

	_set_player_cell(interior, Vector2i(2, 2), "down")
	var current_candidate: Dictionary = interior.get_resolved_interaction_candidate()
	if not _candidate_is(current_candidate, "rest", "current", "object"):
		_cleanup_instance(interior)
		return _fail("standing on generated bed must resolve a current rest candidate")
	if str(current_candidate.get("source_location_id", "")) != interior_id:
		_cleanup_instance(interior)
		return _fail("generated bed candidate must keep concrete interior location id")
	if _candidate_uses_basic_location(current_candidate):
		_cleanup_instance(interior)
		return _fail("generated bed candidate must not use generated_basic_interior as source or target id")
	var current_prompt := str(interior.get_interaction_prompt())
	if current_prompt.is_empty():
		_cleanup_instance(interior)
		return _fail("generated bed current candidate must produce a prompt")
	interior._on_primary_action_requested()
	if not _executed_matches(interior, current_candidate):
		_cleanup_instance(interior)
		return _fail("generated bed current prompt and execute candidate diverged")
	if ActionSystem.last_result == null or ActionSystem.last_result.action_type != "RestAction":
		_cleanup_instance(interior)
		return _fail("generated bed current candidate must execute RestAction")

	_set_player_cell(interior, Vector2i(2, 3), "up")
	var facing_candidate: Dictionary = interior.get_resolved_interaction_candidate()
	if not _candidate_is(facing_candidate, "rest", "facing", "object"):
		_cleanup_instance(interior)
		return _fail("facing generated bed must resolve a facing rest candidate")
	var facing_prompt := str(interior.get_interaction_prompt())
	if facing_prompt.is_empty():
		_cleanup_instance(interior)
		return _fail("generated bed facing candidate must produce a prompt")
	interior._on_primary_action_requested()
	if not _executed_matches(interior, facing_candidate):
		_cleanup_instance(interior)
		return _fail("generated bed facing prompt and execute candidate diverged")
	if ActionSystem.last_result == null or ActionSystem.last_result.action_type != "RestAction":
		_cleanup_instance(interior)
		return _fail("generated bed facing candidate must execute RestAction")
	_cleanup_instance(interior)
	return true


func _test_current_and_facing_drop(root: Node) -> bool:
	var location: Node = _instantiate_location(root, TEST_FIELD_DATA, "start")
	if location == null:
		return _fail("v65 could not instantiate test_field")

	_set_player_cell(location, Vector2i(5, 5), "up")
	var current_candidate: Dictionary = location.get_resolved_interaction_candidate()
	if not _candidate_is(current_candidate, "pickup", "current", "object") or str(current_candidate.get("target_id", "")) != "field_apple":
		_cleanup_instance(location)
		return _fail("standing on dropped item must resolve current pickup candidate")
	if str(location.get_interaction_prompt()).is_empty():
		_cleanup_instance(location)
		return _fail("current dropped item candidate must produce a prompt")
	location._on_primary_action_requested()
	if not _executed_matches(location, current_candidate):
		_cleanup_instance(location)
		return _fail("current dropped item prompt and execute candidate diverged")
	if location.get_location_grid().get_object_by_id("field_apple") != null:
		_cleanup_instance(location)
		return _fail("current pickup must remove the dropped item from the scene")

	_set_player_cell(location, Vector2i(4, 6), "left")
	var facing_candidate: Dictionary = location.get_resolved_interaction_candidate()
	if not _candidate_is(facing_candidate, "pickup", "facing", "object") or str(facing_candidate.get("target_id", "")) != "seed_pouch":
		_cleanup_instance(location)
		return _fail("facing dropped item must resolve facing pickup candidate")
	if str(location.get_interaction_prompt()).is_empty():
		_cleanup_instance(location)
		return _fail("facing dropped item candidate must produce a prompt")
	location._on_primary_action_requested()
	if not _executed_matches(location, facing_candidate):
		_cleanup_instance(location)
		return _fail("facing dropped item prompt and execute candidate diverged")
	if location.get_location_grid().get_object_by_id("seed_pouch") != null:
		_cleanup_instance(location)
		return _fail("facing pickup must remove the dropped item from the scene")
	_cleanup_instance(location)
	return true


func _test_priority_and_stable_sort(root: Node) -> bool:
	var location: Node = _instantiate_location(root, TEST_FIELD_DATA, "start")
	if location == null:
		return _fail("v65 could not instantiate priority test location")
	_set_player_cell(location, Vector2i(1, 1), "right")
	_add_test_object(location, "z_object", Vector2i(1, 1), false, "inspectable", true)
	_add_test_object(location, "a_object", Vector2i(1, 1), false, "inspectable", true)
	_add_test_object(location, "facing_object", Vector2i(2, 1), false, "inspectable", true)
	var all_candidates: Array[Dictionary] = location.get_interaction_candidates()
	if _count_candidates_for_targets(all_candidates, ["a_object", "z_object"], "current", "object") != 2:
		_cleanup_instance(location)
		return _fail("resolver must collect multiple interactable objects from the same current cell")
	if _count_candidates_for_targets(all_candidates, ["facing_object"], "facing", "object") != 1:
		_cleanup_instance(location)
		return _fail("resolver must collect interactable objects from the facing cell")
	var sorted_candidate: Dictionary = location.get_resolved_interaction_candidate()
	if str(sorted_candidate.get("target_id", "")) != "a_object" or str(sorted_candidate.get("relation", "")) != "current":
		_cleanup_instance(location)
		return _fail("same-cell objects must sort stably by object id, and current object must beat facing object")
	for repeat_index in range(3):
		var repeated_candidate: Dictionary = location.get_resolved_interaction_candidate()
		if str(repeated_candidate.get("target_id", "")) != "a_object":
			_cleanup_instance(location)
			return _fail("repeated resolve must keep the same stable object-id tie breaker: %d" % repeat_index)

	_set_player_cell(location, Vector2i(5, 5), "right")
	_add_test_object(location, "current_object", Vector2i(5, 5), false, "inspectable", true)
	_move_character(location, "debug_villager", Vector2i(6, 5), "left")
	var talk_candidate: Dictionary = location.get_resolved_interaction_candidate()
	if not _candidate_is(talk_candidate, "talk", "facing", "character"):
		_cleanup_instance(location)
		return _fail("facing NPC talk must have priority over ordinary current/facing objects")
	if str(location.get_interaction_prompt()).is_empty():
		_cleanup_instance(location)
		return _fail("facing NPC talk candidate must produce a prompt")
	_cleanup_instance(location)
	return true


func _test_concrete_facility_candidates(root: Node) -> bool:
	var manifest := _facility_contract_manifest()
	var interior: Node = _instantiate_generated_interior(root, manifest)
	if interior == null:
		return _fail("v65 could not instantiate concrete facility interior")
	var interior_id := str(manifest.get("interior_location_id", ""))
	var checks: Array[Dictionary] = [
		{ "cell": Vector2i(2, 2), "action_type": "rest", "target_id": "v65_facility_bed" },
		{ "cell": Vector2i(4, 2), "action_type": "shop", "target_id": "v65_facility_counter" },
		{ "cell": Vector2i(4, 3), "action_type": "craft", "target_id": "v65_facility_workbench" },
		{ "cell": Vector2i(5, 2), "action_type": "train", "target_id": "v65_facility_training" },
	]
	for check in checks:
		var cell: Vector2i = check.get("cell", Vector2i.ZERO) as Vector2i
		_set_player_cell(interior, cell, "down")
		var candidates: Array[Dictionary] = interior.get_interaction_candidates()
		if _count_candidates_for_targets(candidates, [str(check.get("target_id", ""))], "current", "object") != 1:
			_cleanup_instance(interior)
			return _fail("concrete interior facility object was not collected: %s" % str(check.get("target_id", "")))
		var candidate: Dictionary = interior.get_resolved_interaction_candidate()
		if not _candidate_is(candidate, str(check.get("action_type", "")), "current", "object"):
			_cleanup_instance(interior)
			return _fail("concrete interior facility resolved wrong action: %s" % str(check.get("target_id", "")))
		if str(candidate.get("source_location_id", "")) != interior_id:
			_cleanup_instance(interior)
			return _fail("concrete interior facility candidate must keep concrete source location id")
		if _candidate_uses_basic_location(candidate):
			_cleanup_instance(interior)
			return _fail("concrete interior facility candidate must not use generated_basic_interior as source or target id")
		if str(interior.get_interaction_prompt()).is_empty():
			_cleanup_instance(interior)
			return _fail("concrete interior facility candidate must produce a prompt: %s" % str(check.get("target_id", "")))
	_cleanup_instance(interior)
	return true


func _test_generated_wall_door_and_return(root: Node) -> bool:
	var container := root.get_node_or_null("WorldRoot")
	if container == null:
		return _fail("v65 smoke needs WorldRoot scene container")
	SceneLoader.configure(container)
	SceneLoader.load_location(GENERATED_SETTLEMENT_SCENE, "main_entrance")
	var exterior: Node = SceneLoader.current_scene
	if exterior == null or not exterior.has_method("get_location_grid"):
		return _fail("generated settlement did not load through SceneLoader")
	var exterior_grid: LocationGrid = exterior.get_location_grid()
	var door: LocationObject = _first_scene_transition_object(exterior_grid)
	if door == null:
		return _fail("generated settlement must expose a wall-door scene transition object")
	var concrete_id := door.target_location_id
	if concrete_id.is_empty() or concrete_id == BASIC_INTERIOR_ID:
		return _fail("wall door must target a concrete generated interior id")
	var return_entrance_cell := exterior_grid.get_entrance_cell(door.return_entrance_id)
	_set_player_cell(exterior, return_entrance_cell, _facing_from_delta(door.grid_position - return_entrance_cell))
	var door_candidate: Dictionary = exterior.get_resolved_interaction_candidate()
	if not _candidate_is(door_candidate, "scene_transition", "facing", "object"):
		return _fail("facing generated wall door must resolve a scene transition candidate")
	if str(door_candidate.get("interior_location_id", "")) != concrete_id:
		return _fail("wall-door candidate must keep concrete target interior id")
	if _candidate_uses_basic_location(door_candidate):
		return _fail("wall-door candidate must not use generated_basic_interior as source or target id")
	var door_transition: Dictionary = (door_candidate.get("metadata", {}) as Dictionary).get("transition_data", {}) as Dictionary
	if str(door_transition.get("target_location_id", "")) != concrete_id:
		return _fail("wall-door transition target must be the concrete interior id")
	if str(exterior.get_interaction_prompt()).is_empty():
		return _fail("wall-door candidate must produce a prompt")
	exterior._on_primary_action_requested()
	var interior: Node = SceneLoader.current_scene
	if interior == null or not interior.has_method("get_location_grid"):
		return _fail("executing wall-door candidate must load an interior scene")
	var interior_grid: LocationGrid = interior.get_location_grid()
	if interior_grid.location_id != concrete_id:
		return _fail("wall-door candidate loaded the wrong interior location: %s" % interior_grid.location_id)

	var return_door: LocationObject = _first_scene_transition_object(interior_grid)
	if return_door == null:
		return _fail("generated interior must expose a return transition object")
	_set_player_cell(interior, return_door.grid_position, "down")
	var current_return_candidate: Dictionary = interior.get_resolved_interaction_candidate()
	if not _candidate_is(current_return_candidate, "scene_transition", "current", "object"):
		return _fail("standing on interior return point must resolve current scene transition")
	if str(current_return_candidate.get("source_building_id", "")).is_empty():
		return _fail("return candidate must retain source_building_id")
	if _candidate_uses_basic_location(current_return_candidate):
		return _fail("current return candidate must not use generated_basic_interior as source or target id")
	if not _return_candidate_targets_exterior(current_return_candidate, exterior_grid.location_id):
		return _fail("current return candidate must target the exterior location and return entrance")
	if str(interior.get_interaction_prompt()).is_empty():
		return _fail("current return candidate must produce a prompt")
	interior._on_primary_action_requested()
	var returned_exterior: Node = SceneLoader.current_scene
	if returned_exterior == null or not returned_exterior.has_method("get_location_grid"):
		return _fail("current return candidate must load the exterior scene")
	if returned_exterior.get_location_grid().location_id != exterior_grid.location_id:
		return _fail("current return candidate must return to exterior location")

	var reloaded_exterior: Node = SceneLoader.current_scene
	var reloaded_grid: LocationGrid = reloaded_exterior.get_location_grid()
	var reloaded_door: LocationObject = _first_scene_transition_object(reloaded_grid)
	if reloaded_door == null:
		return _fail("could not find exterior wall door for facing return test")
	var reloaded_return_cell := reloaded_grid.get_entrance_cell(reloaded_door.return_entrance_id)
	_set_player_cell(reloaded_exterior, reloaded_return_cell, _facing_from_delta(reloaded_door.grid_position - reloaded_return_cell))
	reloaded_exterior._on_primary_action_requested()
	interior = SceneLoader.current_scene
	if interior == null or interior.get_location_grid().location_id != str(reloaded_door.target_location_id):
		return _fail("could not re-enter concrete interior for facing return test")
	_set_player_cell(interior, Vector2i(3, 4), "down")
	var facing_return_candidate: Dictionary = interior.get_resolved_interaction_candidate()
	if not _candidate_is(facing_return_candidate, "scene_transition", "facing", "object"):
		return _fail("facing interior return point must resolve facing scene transition")
	if str(facing_return_candidate.get("source_location_id", "")) == BASIC_INTERIOR_ID:
		return _fail("return candidate must not use generated_basic_interior as source location")
	if _candidate_uses_basic_location(facing_return_candidate):
		return _fail("facing return candidate must not use generated_basic_interior as source or target id")
	if not _return_candidate_targets_exterior(facing_return_candidate, exterior_grid.location_id):
		return _fail("facing return candidate must target the exterior location and return entrance")
	if str(interior.get_interaction_prompt()).is_empty():
		return _fail("facing return candidate must produce a prompt")
	interior._on_primary_action_requested()
	if SceneLoader.current_scene == null or SceneLoader.current_scene.get_location_grid().location_id != exterior_grid.location_id:
		return _fail("facing return candidate must return to exterior location")
	SceneLoader.unload_current_scene()
	return true


func _run_previous_phase_smokes(root: Node) -> bool:
	for smoke_path in [
		"res://scripts/tests/v64_generated_interiors_contract_smoke.gd",
		"res://scripts/tests/v64_policy_playable_settlement_smoke.gd",
		"res://scripts/tests/v63_settlement_scene_compiler_smoke.gd",
	]:
		var script := load(smoke_path) as Script
		if script == null:
			return _fail("could not load smoke: %s" % smoke_path)
		var smoke = script.new()
		if not bool(smoke.run(root)):
			return false
	return true


func _first_generated_bed_manifest() -> Dictionary:
	var compiler: RefCounted = TileSceneCompilerScript.new()
	var compiled: Dictionary = compiler.generate_location(_source_for_policy("farming_village"))
	for manifest_value in (compiled.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		for object_value in (manifest.get("objects", []) as Array):
			var object: Dictionary = object_value as Dictionary
			if str(object.get("facility_type", "")) == "rest" and str(object.get("rest_type", "")) == "bed":
				return manifest
	return {}


func _source_for_policy(policy_id: String) -> Dictionary:
	return {
		"id": "v65_%s_interaction_sample" % policy_id,
		"display_name": "V65 %s Interaction Sample" % policy_id,
		"tile_size": 32,
		"generator": {
			"type": "settlement",
			"settlement_policy_id": policy_id,
			"size": { "width": 48, "height": 32 },
			"context": {
				"map_size": { "width": 48, "height": 32 },
				"entrances": [{ "x": 0, "y": 16 }],
				"existing_obstacles": [],
				"existing_water": [],
				"important_world_points": [{ "x": 36, "y": 20 }]
			}
		}
	}


func _facility_contract_manifest() -> Dictionary:
	return {
		"exterior_location_id": "v65_facility_exterior",
		"source_building_id": "v65_facility_building",
		"interior_location_id": "v65_concrete_facility_contract",
		"display_name": "V65 Concrete Facility Contract",
		"scene_path": BASIC_LOCATION_SCENE,
		"exterior_return_entrance_id": "v65_facility_return",
		"interior_entry_entrance_id": "entry",
		"interior_exit_entrance_id": "exit",
		"size": { "width": 8, "height": 6 },
		"tile_size": 32,
		"entrances": [
			{ "id": "entry", "grid_position": { "x": 3, "y": 4 }, "facing": "up" },
			{ "id": "exit", "grid_position": { "x": 3, "y": 5 }, "facing": "down" },
		],
		"objects": [
			_facility_object_row("v65_facility_bed", "Generated Bed", Vector2i(2, 2), "bed", "rest", "bed", "rest"),
			_facility_object_row("v65_facility_counter", "Generated Counter", Vector2i(4, 2), "shop", "shop", "service_counter", "service"),
			_facility_object_row("v65_facility_workbench", "Generated Workbench", Vector2i(4, 3), "workbench", "crafting", "workstation", "work"),
			_facility_object_row("v65_facility_training", "Generated Training Point", Vector2i(5, 2), "training_dummy", "", "training", "train"),
		],
		"characters": [],
	}


func _facility_object_row(object_id: String, display_name: String, cell: Vector2i, kind: String, facility_type: String, facility_role: String, interaction_kind: String) -> Dictionary:
	var row := {
		"id": object_id,
		"display_name": display_name,
		"grid_position": { "x": cell.x, "y": cell.y },
		"blocks_movement": false,
		"draw_visual": false,
		"kind": kind,
		"facility_type": facility_type,
		"source_building_id": "v65_facility_building",
		"anchor_id": object_id,
		"facility_role": facility_role,
		"interaction_kind": interaction_kind,
	}
	if facility_type == "rest":
		row["rest_type"] = kind
	if facility_type == "shop":
		row["shop_id"] = "v65_facility_shop"
	return row


func _instantiate_generated_interior(root: Node, manifest: Dictionary) -> Node:
	SceneLoader.set_pending_location_context({
		"target_location_id": str(manifest.get("interior_location_id", "")),
		"interior_manifest": manifest.duplicate(true),
	})
	var scene: PackedScene = load(BASIC_LOCATION_SCENE) as PackedScene
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	return instance


func _instantiate_location(root: Node, data_path: String, entrance_id: String) -> Node:
	var scene: PackedScene = load(BASIC_LOCATION_SCENE) as PackedScene
	var instance: Node = scene.instantiate()
	instance.location_data_path = data_path
	if instance.has_method("set_entrance_id"):
		instance.set_entrance_id(entrance_id)
	root.add_child(instance)
	return instance


func _set_player_cell(location, cell: Vector2i, facing: String) -> void:
	_move_character(location, "debug_player", cell, facing)
	if location.has_method("_clear_interaction_candidate_cache"):
		location._clear_interaction_candidate_cache()


func _move_character(location, character_id: String, cell: Vector2i, facing: String) -> void:
	var grid: LocationGrid = location.get_location_grid()
	var character: CharacterEntity = grid.get_character_by_id(character_id)
	if character == null:
		return
	grid.unregister_character(character_id)
	grid.register_character(character_id, cell, character, character.blocks_movement)
	character.set_grid_position(cell)
	character.set_facing(facing)


func _add_test_object(location, object_id: String, cell: Vector2i, blocks_movement: bool, kind: String, inspectable: bool) -> void:
	var object := LocationObject.new()
	location.add_child(object)
	object.configure({
		"id": object_id,
		"display_name": object_id,
		"grid_position": { "x": cell.x, "y": cell.y },
		"blocks_movement": blocks_movement,
		"kind": kind,
		"is_inspectable": inspectable,
		"inspect_text": object_id,
	}, location)
	location.get_location_grid().register_object(object.object_id, object.grid_position, object, object.blocks_movement)


func _first_scene_transition_object(grid: LocationGrid) -> LocationObject:
	for object_value in grid.objects_by_id.values():
		var object: LocationObject = object_value as LocationObject
		if object != null and object.is_scene_transition():
			return object
	return null


func _candidate_is(candidate: Dictionary, action_type: String, relation: String, target_kind: String) -> bool:
	return str(candidate.get("action_type", "")) == action_type and str(candidate.get("relation", "")) == relation and str(candidate.get("target_kind", "")) == target_kind


func _count_candidates_for_targets(candidates: Array[Dictionary], target_ids: Array[String], relation: String, target_kind: String) -> int:
	var count := 0
	for candidate in candidates:
		if str(candidate.get("relation", "")) != relation:
			continue
		if str(candidate.get("target_kind", "")) != target_kind:
			continue
		if target_ids.has(str(candidate.get("target_id", ""))):
			count += 1
	return count


func _candidate_uses_basic_location(candidate: Dictionary) -> bool:
	for key in ["source_location_id", "target_location_id", "interior_location_id", "location_id"]:
		if str(candidate.get(key, "")) == BASIC_INTERIOR_ID:
			return true
	var transition_context: Dictionary = candidate.get("transition_context", {}) as Dictionary
	for key in ["source_location_id", "target_location_id", "interior_location_id", "location_id"]:
		if str(transition_context.get(key, "")) == BASIC_INTERIOR_ID:
			return true
	var metadata: Dictionary = candidate.get("metadata", {}) as Dictionary
	for metadata_key in ["transition_data", "facility_data"]:
		var child: Dictionary = metadata.get(metadata_key, {}) as Dictionary
		for key in ["source_location_id", "target_location_id", "interior_location_id", "location_id"]:
			if str(child.get(key, "")) == BASIC_INTERIOR_ID:
				return true
		var child_context: Dictionary = child.get("context", {}) as Dictionary
		for key in ["source_location_id", "target_location_id", "interior_location_id", "location_id"]:
			if str(child_context.get(key, "")) == BASIC_INTERIOR_ID:
				return true
	return false


func _return_candidate_targets_exterior(candidate: Dictionary, exterior_location_id: String) -> bool:
	var metadata: Dictionary = candidate.get("metadata", {}) as Dictionary
	var transition_data: Dictionary = metadata.get("transition_data", {}) as Dictionary
	if str(transition_data.get("target_location_id", "")) != exterior_location_id:
		return false
	var context: Dictionary = transition_data.get("context", {}) as Dictionary
	var expected_return_id := str(context.get("exterior_return_entrance_id", ""))
	return not expected_return_id.is_empty() and str(transition_data.get("target_entrance_id", "")) == expected_return_id


func _executed_matches(location, expected: Dictionary) -> bool:
	var executed: Dictionary = location.get_last_executed_interaction_candidate()
	return str(executed.get("target_id", "")) == str(expected.get("target_id", "")) \
		and str(executed.get("action_type", "")) == str(expected.get("action_type", "")) \
		and (executed.get("target_cell", Vector2i(-1, -1)) as Vector2i) == (expected.get("target_cell", Vector2i(-2, -2)) as Vector2i) \
		and str(executed.get("relation", "")) == str(expected.get("relation", ""))


func _facing_from_delta(delta: Vector2i) -> String:
	if absi(delta.x) >= absi(delta.y):
		return "right" if delta.x >= 0 else "left"
	return "down" if delta.y >= 0 else "up"


func _cleanup_instance(instance) -> void:
	if instance == null:
		return
	if instance.get_parent() != null:
		instance.get_parent().remove_child(instance)
	instance.queue_free()


func _fail(message: String) -> bool:
	push_error(message)
	return false
