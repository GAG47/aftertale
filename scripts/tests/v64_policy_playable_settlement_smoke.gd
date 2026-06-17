extends RefCounted

const TileSceneCompilerScript := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")
const RoadGraphScript := preload("res://scripts/systems/settlements/settlement_road_graph.gd")

const POLICY_IDS := ["farming_village", "forest_village", "roadside_trade_village", "mining_camp"]
const GAME_SETTLEMENT_PATH := "res://data/locations/generated_settlement.json"


func run(_root: Node) -> bool:
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
	if int(gameplay_hooks.get("buildings_with_interior", 0)) <= 0:
		return false
	if not _has_enterable_generated_building(compiled):
		return false
	if not _has_generated_npc_from_anchor(compiled):
		return false
	if not _optional_shop_and_public_hooks_are_valid(compiled):
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
		if str(object.get("return_entrance_id", "")) == "main_entrance":
			return false
		if not _has_entrance(compiled, str(object.get("return_entrance_id", ""))):
			return false
		return true
	return false


func _has_generated_npc_from_anchor(compiled: Dictionary) -> bool:
	for character_value in (compiled.get("characters", []) as Array):
		var character: Dictionary = character_value as Dictionary
		if not bool(character.get("generated_from_blueprint", false)):
			continue
		if str(character.get("source_anchor_id", "")).is_empty():
			continue
		if not _schedule_has_distinct_anchor_targets(character.get("schedule", []) as Array):
			continue
		return true
	return false


func _optional_shop_and_public_hooks_are_valid(compiled: Dictionary) -> bool:
	var summary: Dictionary = compiled.get("generation_summary", {}) as Dictionary
	var gameplay_hooks: Dictionary = summary.get("gameplay_hooks", {}) as Dictionary
	var shop_anchor_count: int = int(gameplay_hooks.get("shop_anchor_count", 0))
	var public_hook_count: int = int(gameplay_hooks.get("public_hook_count", 0))
	var has_shop := false
	var has_public := false
	for object_value in (compiled.get("objects", []) as Array):
		var object: Dictionary = object_value as Dictionary
		if str(object.get("facility_type", "")) == "shop" and not str(object.get("source_anchor_id", "")).is_empty():
			if str(object.get("shop_id", "")) == "field_stall" or not str(object.get("shop_id", "")).begins_with("generated_shop_"):
				return false
			if str(object.get("vendor_character_id", "")).is_empty():
				return false
			has_shop = true
		if str(object.get("source_anchor_id", "")).begins_with("notice_"):
			has_public = true
	return (shop_anchor_count <= 0 or has_shop) and (public_hook_count <= 0 or has_public)


func _has_entrance(compiled: Dictionary, entrance_id: String) -> bool:
	if entrance_id.is_empty():
		return false
	for entrance_value in (compiled.get("entrances", []) as Array):
		var entrance: Dictionary = entrance_value as Dictionary
		if str(entrance.get("id", "")) == entrance_id:
			return true
	return false


func _schedule_has_distinct_anchor_targets(schedule: Array) -> bool:
	var anchors: Dictionary = {}
	for row_value in schedule:
		var row: Dictionary = row_value as Dictionary
		var anchor_id := str(row.get("anchor_id", ""))
		if not anchor_id.is_empty():
			anchors[anchor_id] = true
	return anchors.size() >= 2


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
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
