extends RefCounted

const TileSceneCompilerScript := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")
const RoadGraphScript := preload("res://scripts/systems/settlements/settlement_road_graph.gd")

const POLICY_IDS := ["farming_village", "forest_village", "roadside_trade_village", "mining_camp"]
const GAME_SETTLEMENT_PATH := "res://data/locations/generated_settlement.json"
const GENERATED_INTERIOR_SCENE := "res://scenes/locations/generated_basic_interior.tscn"


func run(root: Node) -> bool:
	var results: Dictionary = {}
	for policy_id in POLICY_IDS:
		var source := _source_for_policy(policy_id)
		var compiler: RefCounted = TileSceneCompilerScript.new()
		var compiled: Dictionary = compiler.generate_location(source)
		if compiled.is_empty():
			return _fail("v64 policy failed to generate: %s" % policy_id)
		var errors: Array[String] = compiler.validate_compiled_location(compiled)
		if not errors.is_empty():
			return _fail("v64 policy failed compiled connectivity: %s %s" % [policy_id, ", ".join(errors)])
		if not _compiled_connectivity_is_valid(compiled):
			return _fail("v64 policy must preserve v62.5 road connectivity: %s" % policy_id)
		if not _has_playable_hooks(compiled):
			return _fail("v64 generated settlement must expose playable hooks: %s" % policy_id)
		if not _has_no_generated_shop_hooks(compiled):
			return _fail("v64 generated settlement must not compile shop counters: %s" % policy_id)
		if not _has_no_external_blocking_door_objects(compiled):
			return _fail("v64 generated settlement must not compile external blocking door objects: %s" % policy_id)
		results[policy_id] = compiled

	if not _plot_use_counts_are_distinct(results):
		return _fail("v64 policy plot use counts must be observably different")
	if not _agent_weight_summaries_are_distinct(results):
		return _fail("v64 policy agent weight summaries must differ")
	if int(((results.get("roadside_trade_village", {}) as Dictionary).get("generation_summary", {}) as Dictionary).get("plot_count", 0)) <= 18:
		return _fail("v64 roadside 48x32 settlement must not be capped at the old 18 plot demo size")
	if not _policy_weight_contracts_hold():
		return false
	if not _generated_settlement_uses_policy_id():
		return false
	if not _interior_exit_current_cell_prompt_works(root):
		return false

	print("v64 policy playable settlement smoke test passed")
	return true


func _source_for_policy(policy_id: String) -> Dictionary:
	return {
		"id": "v64_%s_sample" % policy_id,
		"display_name": "V64 %s Sample" % policy_id,
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


func _compiled_connectivity_is_valid(compiled: Dictionary) -> bool:
	var connectivity := RoadGraphScript.analyze_compiled_location(compiled)
	for key in [
		"compiled_road_connected",
		"compiled_entrance_connected",
		"compiled_core_connected",
		"compiled_plot_access_connected",
		"compiled_building_front_connected",
	]:
		if not bool(connectivity.get(key, false)):
			return false
	return true


func _has_playable_hooks(compiled: Dictionary) -> bool:
	var summary: Dictionary = compiled.get("generation_summary", {}) as Dictionary
	var gameplay_hooks: Dictionary = summary.get("gameplay_hooks", {}) as Dictionary
	if int(gameplay_hooks.get("generated_npc_count", -1)) != 0:
		return false
	if int(gameplay_hooks.get("character_records", -1)) != 0:
		return false
	if not (compiled.get("characters", []) as Array).is_empty():
		return false
	if int(gameplay_hooks.get("enterable_building_count", 0)) <= 0:
		return false
	if not _has_enterable_generated_building(compiled):
		return false
	if not _has_no_generated_npcs(compiled):
		return false
	if not _small_structures_are_not_enterable(compiled):
		return false
	if not _public_hooks_are_valid(compiled):
		return false
	return true


func _has_enterable_generated_building(compiled: Dictionary) -> bool:
	for object_value in (compiled.get("objects", []) as Array):
		var object: Dictionary = object_value as Dictionary
		if str(object.get("facility_type", "")) != "scene_transition":
			continue
		if str(object.get("target_scene_path", "")).is_empty():
			continue
		if str(object.get("interior_template_id", "")).is_empty():
			continue
		if str(object.get("source_blueprint_id", "")).is_empty():
			continue
		if not _is_enterable_footprint_size(object.get("footprint_size", {}) as Dictionary):
			return false
		if str(object.get("return_entrance_id", "")) == "main_entrance":
			return false
		if not _has_entrance(compiled, str(object.get("return_entrance_id", ""))):
			return false
		return true
	return false


func _has_no_generated_npcs(compiled: Dictionary) -> bool:
	for character_value in (compiled.get("characters", []) as Array):
		var character: Dictionary = character_value as Dictionary
		if bool(character.get("generated_from_blueprint", false)):
			return false
		if str(character.get("display_name", "")) == "Generated Settler":
			return false
		if str(character.get("id", "")).begins_with("generated_settlement_npc_"):
			return false
	return true


func _small_structures_are_not_enterable(compiled: Dictionary) -> bool:
	for object_value in (compiled.get("objects", []) as Array):
		var object: Dictionary = object_value as Dictionary
		if str(object.get("facility_type", "")) != "scene_transition":
			continue
		if _is_enterable_footprint_size(object.get("footprint_size", {}) as Dictionary):
			continue
		if not str(object.get("interior_template_id", "")).is_empty():
			return false
	return true


func _public_hooks_are_valid(compiled: Dictionary) -> bool:
	var summary: Dictionary = compiled.get("generation_summary", {}) as Dictionary
	var gameplay_hooks: Dictionary = summary.get("gameplay_hooks", {}) as Dictionary
	var public_hook_count: int = int(gameplay_hooks.get("public_hook_count", 0))
	var has_public := false
	for object_value in (compiled.get("objects", []) as Array):
		var object: Dictionary = object_value as Dictionary
		if str(object.get("source_anchor_id", "")).begins_with("notice_"):
			has_public = true
	return public_hook_count <= 0 or has_public


func _has_no_generated_shop_hooks(compiled: Dictionary) -> bool:
	if not (compiled.get("shops", []) as Array).is_empty():
		return false
	for object_value in (compiled.get("objects", []) as Array):
		var object: Dictionary = object_value as Dictionary
		if str(object.get("facility_type", "")) == "shop":
			return false
		if str(object.get("display_name", "")) == "Generated Shop Counter":
			return false
		if str(object.get("shop_id", "")).begins_with("generated_shop_"):
			return false
	return true


func _has_no_external_blocking_door_objects(compiled: Dictionary) -> bool:
	for object_value in (compiled.get("objects", []) as Array):
		var object: Dictionary = object_value as Dictionary
		if str(object.get("id", "")).begins_with("door_"):
			return false
		if str(object.get("kind", "")) == "door" and bool(object.get("blocks_movement", false)):
			return false
		if str(object.get("kind", "")) == "wall_door":
			if bool(object.get("blocks_movement", true)):
				return false
			if bool(object.get("draw_visual", true)):
				return false
	return true


func _has_entrance(compiled: Dictionary, entrance_id: String) -> bool:
	if entrance_id.is_empty():
		return false
	for entrance_value in (compiled.get("entrances", []) as Array):
		var entrance: Dictionary = entrance_value as Dictionary
		if str(entrance.get("id", "")) == entrance_id:
			return true
	return false


func _is_enterable_footprint_size(footprint_size: Dictionary) -> bool:
	var width := int(footprint_size.get("width", 0))
	var height := int(footprint_size.get("height", 0))
	return (width >= 2 and height >= 3) or (width >= 3 and height >= 2)


func _plot_use_counts_are_distinct(results: Dictionary) -> bool:
	var signatures: Dictionary = {}
	for policy_id in results.keys():
		var compiled: Dictionary = results.get(policy_id, {}) as Dictionary
		var counts: Dictionary = (compiled.get("generation_summary", {}) as Dictionary).get("plot_use_counts", {}) as Dictionary
		signatures[JSON.stringify(counts)] = true
	return signatures.size() >= 3


func _agent_weight_summaries_are_distinct(results: Dictionary) -> bool:
	var signatures: Dictionary = {}
	for policy_id in results.keys():
		var compiled: Dictionary = results.get(policy_id, {}) as Dictionary
		var summary: Dictionary = (compiled.get("generation_summary", {}) as Dictionary).get("agent_weight_summary", {}) as Dictionary
		signatures[JSON.stringify(summary)] = true
	return signatures.size() == POLICY_IDS.size()


func _policy_weight_contracts_hold() -> bool:
	var farming := SettlementPolicy.from_profile_id("farming_village")
	var roadside := SettlementPolicy.from_profile_id("roadside_trade_village")
	var mining := SettlementPolicy.from_profile_id("mining_camp")
	var forest := SettlementPolicy.from_profile_id("forest_village")
	if float(farming.plot_use_weight_overrides.get("production", 0.0)) <= float(farming.plot_use_weight_overrides.get("commercial", 0.0)):
		return _fail("v64 farming_village production weight must exceed commercial")
	if float(roadside.plot_use_weight_overrides.get("commercial", 0.0)) <= float(farming.plot_use_weight_overrides.get("commercial", 0.0)):
		return _fail("v64 roadside_trade_village commercial weight must exceed farming_village")
	if float(mining.plot_use_weight_overrides.get("production", 0.0)) < 2.0:
		return _fail("v64 mining_camp production weight must be high")
	if float(mining.demand_weight_overrides.get("residential", 0.0)) < 1.2:
		return _fail("v64 mining_camp worker housing demand must be high")
	if forest.density >= roadside.density:
		return _fail("v64 forest_village density must be lower than roadside_trade_village")
	return true


func _generated_settlement_uses_policy_id() -> bool:
	DefinitionLoader.clear_cache()
	var location: Dictionary = DefinitionLoader.load_resolved_location(GAME_SETTLEMENT_PATH)
	if location.is_empty():
		return _fail("v64 generated_settlement.json must load")
	var state: Dictionary = location.get("state", {}) as Dictionary
	if str(state.get("settlement_policy_id", "")) != "roadside_trade_village":
		return _fail("v64 generated_settlement.json must be driven by settlement_policy_id")
	if not _has_playable_hooks(location):
		return _fail("v64 generated_settlement.json compiled output must expose gameplay hooks")
	if not _has_no_generated_shop_hooks(location):
		return _fail("v64 generated_settlement.json must not compile generated shop counters")
	if not _roadside_default_is_residential_first(location):
		return _fail("v64 generated_settlement.json should not be dominated by commercial plots")
	return true


func _roadside_default_is_residential_first(location: Dictionary) -> bool:
	var counts: Dictionary = (location.get("generation_summary", {}) as Dictionary).get("plot_use_counts", {}) as Dictionary
	return int(counts.get("residential", 0)) > int(counts.get("commercial", 0))


func _interior_exit_current_cell_prompt_works(root: Node) -> bool:
	var scene := load(GENERATED_INTERIOR_SCENE) as PackedScene
	if scene == null:
		return _fail("v64 generated basic interior scene must load")
	var instance := scene.instantiate()
	root.add_child(instance)
	var grid: LocationGrid = instance.get_location_grid() if instance.has_method("get_location_grid") else null
	if grid == null:
		_cleanup_instance(instance)
		return _fail("v64 generated basic interior must expose a grid")
	var player: CharacterEntity = grid.characters_by_id.get("debug_player", null) as CharacterEntity
	if player == null:
		_cleanup_instance(instance)
		return _fail("v64 generated basic interior must spawn debug player")
	player.set_grid_position(Vector2i(3, 5))
	var prompt := str(instance.get_interaction_prompt()) if instance.has_method("get_interaction_prompt") else ""
	_cleanup_instance(instance)
	if prompt.find("Leave") < 0:
		return _fail("v64 interior exit must be interactable from the current cell")
	return true


func _cleanup_instance(instance: Node) -> void:
	if instance == null:
		return
	if instance.get_parent() != null:
		instance.get_parent().remove_child(instance)
	instance.queue_free()


func _fail(message: String) -> bool:
	push_error(message)
	return false
