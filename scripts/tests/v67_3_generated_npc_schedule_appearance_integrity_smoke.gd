extends RefCounted

const StoreScript := preload("res://scripts/systems/settlements/generated_settlement_store.gd")
const AppearanceRendererScript := preload("res://scripts/systems/characters/character_appearance_renderer.gd")
const BASIC_INTERIOR_SCENE := "res://scenes/locations/generated_basic_interior.tscn"

const SETTLEMENT_ID := "v67_3_integrity_settlement"
const TEMPLATE_ID := "v67_3_integrity_template"
const WORLD_ID := "v67_3_integrity_world"
const SAVE_PATH := "user://saves/v67_3_slot.json"
const SOURCE_PATH := "res://data/locations/v67_3_integrity_template.json"
const OVERLAP_LOCATION_PATH := "user://v67_3_overlap_location.json"
const OVERLAP_CHARACTER_A_PATH := "user://v67_3_overlap_a.json"
const OVERLAP_CHARACTER_B_PATH := "user://v67_3_overlap_b.json"
const RUNTIME_LOCATION_PATH := "user://v67_3_runtime_location.json"
const RUNTIME_CHARACTER_PATH := "user://v67_3_runtime_character.json"


func run(root: Node) -> bool:
	if root != null and root.has_node("WorldRoot"):
		SceneLoader.configure(root.get_node("WorldRoot"))

	SaveManager.configure_active_save_context(SAVE_PATH, WORLD_ID)
	var store: RefCounted = StoreScript.new()
	StoreScript.clear_generated_data_for_active_context()
	if store.has_snapshot(SETTLEMENT_ID):
		return _fail("v67.3 active generated data clear left an old snapshot behind")
	GameState.start_new_session("v67_3_integrity_session")
	TimeManager.reset()
	NpcScheduleSystem.reset_schedule_state()
	DefinitionLoader.clear_cache()
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
	if not _generated_character_runtime_uses_map_sprite(root, snapshot):
		return false
	if not _assignments_are_valid(snapshot):
		return false
	if not _building_capacity_is_valid(snapshot):
		return false
	if not _schedule_integrity_is_valid(snapshot):
		return false
	if not _entrance_and_exit_targets_are_exposed(snapshot):
		return false
	if not _location_root_spawn_avoids_blocking_overlap(root, snapshot):
		return false
	if not _runtime_schedule_transitions_are_visible(root, snapshot):
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


func _generated_character_runtime_uses_map_sprite(root: Node, snapshot: Dictionary) -> bool:
	var definitions: Array = snapshot.get("npc_definitions", []) as Array
	if definitions.is_empty():
		return _fail("v67.3 runtime appearance test needs a generated NPC definition")
	var snapshot_definition: Dictionary = definitions[0] as Dictionary
	var character_source := str(snapshot_definition.get("source", ""))
	var definition := DefinitionLoader.load_json_resource(character_source)
	if definition.is_empty():
		return _fail("v67.3 runtime appearance test could not load generated character source: %s" % character_source)
	var character := CharacterEntity.new()
	character.configure(definition, {
		"id": str(definition.get("id", "v67_3_runtime_appearance")),
		"source": character_source,
		"grid_position": { "x": 1, "y": 1 },
		"facing": "down",
	}, root)
	var appearance := character.appearance.duplicate(true)
	var render_path := str(AppearanceRendererScript.render_path_for_appearance(appearance))
	character.queue_free()
	if str(appearance.get("display_mode", "")) != "map_sprite":
		return _fail("v67.3 generated NPC runtime appearance did not keep map_sprite mode")
	var layers: Dictionary = appearance.get("layers", {}) as Dictionary
	if not layers.is_empty():
		return _fail("v67.3 generated NPC runtime appearance still carried modular layers")
	if render_path != "map_sprite":
		return _fail("v67.3 generated NPC renderer did not select map_sprite path: %s" % render_path)
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


func _building_capacity_is_valid(snapshot: Dictionary) -> bool:
	var summary: Dictionary = snapshot.get("population_summary", {}) as Dictionary
	var capacity_summary: Dictionary = summary.get("building_capacity_summary", {}) as Dictionary
	if capacity_summary.is_empty():
		return _fail("v67.3 population summary must include building_capacity_summary")
	var totals: Dictionary = capacity_summary.get("totals", {}) as Dictionary
	var residential_total := int(totals.get("residential_capacity", 0))
	if residential_total <= 0:
		return _fail("v67.3 generated settlement must expose positive residential capacity")
	if (snapshot.get("npc_definitions", []) as Array).size() > residential_total:
		return _fail("v67.3 generated NPC count exceeds residential capacity")

	var residential_capacity_by_location: Dictionary = {}
	var buildings: Dictionary = capacity_summary.get("buildings", {}) as Dictionary
	for building_id_value in buildings.keys():
		var building_row: Dictionary = buildings.get(building_id_value, {}) as Dictionary
		if str(building_row.get("use_type", "")) != "residential":
			continue
		var location_id := str(building_row.get("interior_location_id", ""))
		var capacity := int(building_row.get("residential_capacity", 0))
		if location_id.is_empty() or capacity <= 0:
			continue
		residential_capacity_by_location[location_id] = capacity
	if residential_capacity_by_location.is_empty():
		return _fail("v67.3 capacity audit could not resolve residential interiors")

	var home_npcs_by_location: Dictionary = {}
	var private_claim_by_target: Dictionary = {}
	for assignment_value in (snapshot.get("npc_role_assignments", []) as Array):
		var assignment: Dictionary = assignment_value as Dictionary
		var npc_id := str(assignment.get("npc_id", ""))
		for target_field in ["home_target", "rest_target"]:
			var target: Dictionary = assignment.get(target_field, {}) as Dictionary
			var location_id := str(target.get("location_id", ""))
			if not residential_capacity_by_location.has(location_id):
				continue
			if not home_npcs_by_location.has(location_id):
				home_npcs_by_location[location_id] = {}
			(home_npcs_by_location[location_id] as Dictionary)[npc_id] = true
			var target_key := str(target.get("target_key", ""))
			if target_key.is_empty():
				target_key = "%s:%s" % [location_id, str(target.get("anchor_id", ""))]
			if private_claim_by_target.has(target_key) and str(private_claim_by_target.get(target_key, "")) != npc_id:
				return _fail("v67.3 private home/rest target was assigned to multiple NPCs: %s" % target_key)
			private_claim_by_target[target_key] = npc_id

	for location_id_value in home_npcs_by_location.keys():
		var location_id := str(location_id_value)
		var npc_rows: Dictionary = home_npcs_by_location.get(location_id, {}) as Dictionary
		var capacity := int(residential_capacity_by_location.get(location_id, 0))
		if npc_rows.size() > capacity:
			return _fail("v67.3 residential interior over capacity: %s %d>%d" % [location_id, npc_rows.size(), capacity])
	return true


func _schedule_integrity_is_valid(snapshot: Dictionary) -> bool:
	var anchors_by_location := _anchors_by_location(snapshot)
	var interior_locations := _generated_interior_location_set(snapshot)
	var exterior_id := str(snapshot.get("exterior_location_id", ""))
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
				if not _cross_scene_transition_anchors_are_valid(entry, interior_locations, exterior_id):
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


func _cross_scene_transition_anchors_are_valid(entry: Dictionary, interior_locations: Dictionary, exterior_id: String) -> bool:
	var entry_id := str(entry.get("id", ""))
	var source_location_id := str(entry.get("source_location_id", ""))
	var target_location_id := str(entry.get("location_id", ""))
	var anchors: Dictionary = entry.get("transition_anchor_by_location", {}) as Dictionary
	if not anchors.has(source_location_id) or not anchors.has(target_location_id):
		return _fail("v67.3 cross-location entry missing source/target transition anchors: %s" % entry_id)
	if interior_locations.has(source_location_id):
		if str(entry.get("departure_anchor_id", "")) != "interior_exit":
			return _fail("v67.3 interior departure must use interior_exit: %s" % entry_id)
		if str(anchors.get(source_location_id, "")) != "interior_exit":
			return _fail("v67.3 interior transition map must use interior_exit: %s" % entry_id)
	if interior_locations.has(target_location_id):
		if str(entry.get("arrival_anchor_id", "")) != "interior_entry":
			return _fail("v67.3 interior arrival must use interior_entry: %s" % entry_id)
		if str(anchors.get(target_location_id, "")) != "interior_entry":
			return _fail("v67.3 target interior transition map must use interior_entry: %s" % entry_id)
	if interior_locations.has(source_location_id) and target_location_id == exterior_id:
		var exterior_anchor := str(anchors.get(target_location_id, ""))
		if exterior_anchor.is_empty():
			return _fail("v67.3 exterior arrival must use the source building door: %s" % entry_id)
		if not exterior_anchor.begins_with("building_entrance_"):
			return _fail("v67.3 exterior arrival must use a building entrance anchor: %s" % entry_id)
		if str(entry.get("target_type", "")) == "public" and exterior_anchor == str(entry.get("anchor_id", "")):
			return _fail("v67.3 public exterior arrival must not use the final activity anchor: %s" % entry_id)
	if source_location_id == exterior_id and interior_locations.has(target_location_id):
		var exterior_departure := str(anchors.get(source_location_id, ""))
		if exterior_departure.is_empty() or not exterior_departure.begins_with("building_entrance_"):
			return _fail("v67.3 exterior departure into an interior must use a building entrance anchor: %s" % entry_id)
	return true


func _generated_interior_location_set(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var location_id := str(manifest.get("interior_location_id", ""))
		if not location_id.is_empty():
			result[location_id] = true
	return result


func _entrance_and_exit_targets_are_exposed(snapshot: Dictionary) -> bool:
	var exterior_id := str(snapshot.get("exterior_location_id", ""))
	var anchors_by_location := _anchors_by_location(snapshot)
	var exterior_has_building_entrance := false
	for target_value in (snapshot.get("schedule_targets", []) as Array):
		var target: Dictionary = target_value as Dictionary
		var role := str(target.get("role", ""))
		if str(target.get("location_id", "")) == exterior_id and role in ["building_entrance", "exterior_transition"]:
			exterior_has_building_entrance = true
			var anchor_id := str(target.get("anchor_id", ""))
			if not (anchors_by_location.get(exterior_id, {}) as Dictionary).has(anchor_id):
				return _fail("v67.3 exterior entrance schedule target anchor is not resolvable: %s" % anchor_id)
	if not exterior_has_building_entrance:
		return _fail("v67.3 exterior must expose building entrance schedule target")

	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var location_id := str(manifest.get("interior_location_id", ""))
		var anchors: Dictionary = anchors_by_location.get(location_id, {}) as Dictionary
		if not anchors.has("interior_entry") or not anchors.has("interior_exit"):
			return _fail("v67.3 generated interior must expose concrete interior_entry/interior_exit anchors")
		var roles: Dictionary = {}
		for target_value in (manifest.get("schedule_targets", []) as Array):
			var target: Dictionary = target_value as Dictionary
			roles[str(target.get("role", ""))] = true
			var anchor_id := str(target.get("anchor_id", ""))
			if not anchors.has(anchor_id):
				return _fail("v67.3 generated interior schedule target anchor is not resolvable: %s/%s" % [location_id, anchor_id])
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


func _runtime_schedule_transitions_are_visible(root: Node, snapshot: Dictionary) -> bool:
	if root == null:
		return _fail("v67.3 runtime transition tests need root")
	var fixture := _runtime_fixture(snapshot)
	if fixture.is_empty():
		return _fail("v67.3 runtime transition fixture could not be resolved")
	if not _runtime_arrival_uses_entry_then_walks(root, snapshot, fixture):
		return false
	if not _runtime_departure_walks_to_exit_then_removes(root, snapshot, fixture):
		return false
	if not _runtime_offscreen_settle_keeps_non_current_offscreen(root, snapshot, fixture):
		return false
	return true


func _runtime_arrival_uses_entry_then_walks(root: Node, snapshot: Dictionary, fixture: Dictionary) -> bool:
	var npc_id := "v67_3_runtime_arrival"
	var schedule := [
		_cross_location_entry(
			npc_id,
			"arrival",
			"08:00",
			"08:05",
			str(fixture.get("exterior_location_id", "")),
			fixture.get("exterior_target", {}) as Dictionary,
			str(fixture.get("interior_location_id", "")),
			fixture.get("interior_target", {}) as Dictionary,
			str((fixture.get("exterior_target", {}) as Dictionary).get("anchor_id", "")),
			"interior_entry",
			"entering the building"
		),
	]
	if not _write_json(RUNTIME_CHARACTER_PATH, _runtime_character_definition(snapshot, npc_id, schedule)):
		return false
	var location_data := (fixture.get("interior_location", {}) as Dictionary).duplicate(true)
	location_data["characters"] = [
		_player_spawn_row({ "x": 1, "y": 1 }),
		{
			"id": npc_id,
			"source": RUNTIME_CHARACTER_PATH,
			"grid_position": { "x": 4, "y": 4 },
			"facing": "down",
		},
	]
	if not _write_json(RUNTIME_LOCATION_PATH, location_data):
		return false

	TimeManager.reset(1, 8, 0)
	NpcScheduleSystem.reset_schedule_state()
	var instance := _instantiate_runtime_location(root, location_data, RUNTIME_LOCATION_PATH)
	if instance == null:
		return false
	var grid: LocationGrid = instance.get_location_grid() if instance.has_method("get_location_grid") else null
	if grid == null:
		_cleanup_instance(instance)
		return _fail("v67.3 runtime arrival test did not expose a grid")
	var character: CharacterEntity = grid.get_character_by_id(npc_id)
	if character == null:
		_cleanup_instance(instance)
		return _fail("v67.3 runtime arrival NPC did not spawn")
	var entry_cell := _anchor_cell(grid, "interior_entry")
	var target_cell := _cell_from_dict((fixture.get("interior_target", {}) as Dictionary).get("grid_position", {}) as Dictionary)
	if character.grid_position != entry_cell:
		_cleanup_instance(instance)
		return _fail("v67.3 runtime arrival spawned at %s instead of interior_entry %s" % [str(character.grid_position), str(entry_cell)])

	_tick_location(instance, 18)
	character = grid.get_character_by_id(npc_id)
	var final_cell := character.grid_position if character != null else Vector2i(-1, -1)
	_cleanup_instance(instance)
	NpcScheduleSystem.reset_schedule_state()
	if character == null:
		return _fail("v67.3 runtime arrival NPC was removed after entering current location")
	if final_cell != target_cell:
		return _fail("v67.3 runtime arrival NPC did not walk from entry to target: %s != %s" % [str(final_cell), str(target_cell)])
	return true


func _runtime_departure_walks_to_exit_then_removes(root: Node, snapshot: Dictionary, fixture: Dictionary) -> bool:
	var npc_id := "v67_3_runtime_departure"
	var interior_id := str(fixture.get("interior_location_id", ""))
	var exterior_id := str(fixture.get("exterior_location_id", ""))
	var interior_target: Dictionary = fixture.get("interior_target", {}) as Dictionary
	var exterior_target: Dictionary = fixture.get("exterior_target", {}) as Dictionary
	var schedule := [
		_same_location_entry(npc_id, "inside", "07:55", "07:59", interior_id, interior_target, "working inside"),
		_cross_location_entry(npc_id, "depart", "08:00", "08:05", interior_id, interior_target, exterior_id, exterior_target, "interior_exit", str(exterior_target.get("anchor_id", "")), "leaving the building"),
	]
	if not _write_json(RUNTIME_CHARACTER_PATH, _runtime_character_definition(snapshot, npc_id, schedule)):
		return false
	var location_data := (fixture.get("interior_location", {}) as Dictionary).duplicate(true)
	location_data["characters"] = [
		_player_spawn_row({ "x": 1, "y": 1 }),
		{
			"id": npc_id,
			"source": RUNTIME_CHARACTER_PATH,
			"grid_position": { "x": 4, "y": 4 },
			"facing": "down",
		},
	]
	if not _write_json(RUNTIME_LOCATION_PATH, location_data):
		return false

	TimeManager.reset(1, 7, 59)
	NpcScheduleSystem.reset_schedule_state()
	var instance := _instantiate_runtime_location(root, location_data, RUNTIME_LOCATION_PATH)
	if instance == null:
		return false
	var grid: LocationGrid = instance.get_location_grid() if instance.has_method("get_location_grid") else null
	if grid == null:
		_cleanup_instance(instance)
		return _fail("v67.3 runtime departure test did not expose a grid")
	var character: CharacterEntity = grid.get_character_by_id(npc_id)
	if character == null:
		_cleanup_instance(instance)
		return _fail("v67.3 runtime departure NPC did not spawn before leaving")
	var target_cell := _cell_from_dict(interior_target.get("grid_position", {}) as Dictionary)
	if character.grid_position != target_cell:
		_cleanup_instance(instance)
		return _fail("v67.3 runtime departure NPC did not start at its current schedule target")

	TimeManager.advance_minutes(1)
	character = grid.get_character_by_id(npc_id)
	if character == null:
		_cleanup_instance(instance)
		return _fail("v67.3 runtime departure removed NPC immediately instead of walking to exit")
	_tick_location(instance, 18)
	character = grid.get_character_by_id(npc_id)
	_cleanup_instance(instance)
	NpcScheduleSystem.reset_schedule_state()
	if character != null:
		return _fail("v67.3 runtime departure NPC was not removed after reaching the exit")
	return true


func _runtime_offscreen_settle_keeps_non_current_offscreen(root: Node, snapshot: Dictionary, fixture: Dictionary) -> bool:
	var npc_id := "v67_3_runtime_offscreen"
	var interior_id := str(fixture.get("interior_location_id", ""))
	var exterior_id := str(fixture.get("exterior_location_id", ""))
	var interior_target: Dictionary = fixture.get("interior_target", {}) as Dictionary
	var exterior_target: Dictionary = fixture.get("exterior_target", {}) as Dictionary
	var schedule := [
		_same_location_entry(npc_id, "inside", "07:55", "07:59", interior_id, interior_target, "working inside"),
		_cross_location_entry(npc_id, "depart", "08:00", "08:05", interior_id, interior_target, exterior_id, exterior_target, "interior_exit", str(exterior_target.get("anchor_id", "")), "leaving the building"),
	]
	if not _write_json(RUNTIME_CHARACTER_PATH, _runtime_character_definition(snapshot, npc_id, schedule)):
		return false
	var location_data := (fixture.get("interior_location", {}) as Dictionary).duplicate(true)
	location_data["characters"] = [
		_player_spawn_row({ "x": 1, "y": 1 }),
		{
			"id": npc_id,
			"source": RUNTIME_CHARACTER_PATH,
			"grid_position": { "x": 4, "y": 4 },
			"facing": "down",
		},
	]
	if not _write_json(RUNTIME_LOCATION_PATH, location_data):
		return false

	NpcScheduleSystem.reset_schedule_state()
	TimeManager.reset(1, 8, 2)
	NpcScheduleSystem.settle_offscreen_location(RUNTIME_LOCATION_PATH, _absolute_minutes(1, 7, 59), _absolute_minutes(1, 8, 2))
	var exterior_summary: Dictionary = NpcScheduleSystem.get_offscreen_summary(exterior_id)
	var settled := false
	for state_value in (exterior_summary.get("characters", []) as Array):
		var state: Dictionary = state_value as Dictionary
		if str(state.get("character_id", "")) == npc_id and str(state.get("location_id", "")) == exterior_id:
			settled = true
	if not settled:
		return _fail("v67.3 offscreen settle did not move NPC state to the target exterior location")

	var instance := _instantiate_runtime_location(root, location_data, RUNTIME_LOCATION_PATH)
	if instance == null:
		return false
	var grid: LocationGrid = instance.get_location_grid() if instance.has_method("get_location_grid") else null
	if grid == null:
		_cleanup_instance(instance)
		return _fail("v67.3 offscreen source re-entry test did not expose a grid")
	var character: CharacterEntity = grid.get_character_by_id(npc_id)
	_cleanup_instance(instance)
	NpcScheduleSystem.reset_schedule_state()
	if character != null:
		return _fail("v67.3 offscreen NPC reappeared in the source location after settling elsewhere")
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


func _runtime_fixture(snapshot: Dictionary) -> Dictionary:
	var exterior_id := str(snapshot.get("exterior_location_id", ""))
	var exterior_location: Dictionary = {}
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if str(location.get("id", "")) == exterior_id:
			exterior_location = location.duplicate(true)
			break
	if exterior_location.is_empty():
		return {}

	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var interior_id := str(manifest.get("interior_location_id", ""))
		var building_id := str(manifest.get("source_building_id", ""))
		var interior_location := DefinitionLoader.resolve_location_by_id(interior_id)
		if interior_location.is_empty():
			continue
		var interior_target := _first_interior_activity_target(manifest.get("schedule_targets", []) as Array)
		if interior_target.is_empty():
			continue
		var exterior_target := _first_exterior_target_for_building(snapshot, building_id)
		if exterior_target.is_empty():
			continue
		var anchors := _anchor_map(interior_location.get("anchors", []) as Array)
		if not anchors.has("interior_entry") or not anchors.has("interior_exit"):
			continue
		return {
			"exterior_location_id": exterior_id,
			"exterior_location": exterior_location,
			"interior_location_id": interior_id,
			"interior_location": interior_location.duplicate(true),
			"source_building_id": building_id,
			"interior_target": interior_target,
			"exterior_target": exterior_target,
		}
	return {}


func _first_interior_activity_target(targets: Array) -> Dictionary:
	for target_value in targets:
		var target: Dictionary = target_value as Dictionary
		var role := str(target.get("role", ""))
		if role in ["interior_entry", "interior_exit"]:
			continue
		if (target.get("grid_position", {}) as Dictionary).is_empty():
			continue
		return target.duplicate(true)
	return {}


func _first_exterior_target_for_building(snapshot: Dictionary, building_id: String) -> Dictionary:
	for preferred_role in ["building_entrance", "exterior_transition"]:
		for target_value in (snapshot.get("schedule_targets", []) as Array):
			var target: Dictionary = target_value as Dictionary
			if str(target.get("source_building_id", "")) != building_id:
				continue
			if str(target.get("role", "")) != preferred_role:
				continue
			if (target.get("grid_position", {}) as Dictionary).is_empty():
				continue
			return target.duplicate(true)
	return {}


func _runtime_character_definition(snapshot: Dictionary, npc_id: String, schedule: Array) -> Dictionary:
	var definitions: Array = snapshot.get("npc_definitions", []) as Array
	var definition: Dictionary = (definitions[0] as Dictionary).duplicate(true) if not definitions.is_empty() else {}
	definition["id"] = npc_id
	definition["display_name"] = npc_id.capitalize().replace("_", " ")
	definition["schedule"] = schedule.duplicate(true)
	definition["generated"] = true
	definition["is_player_controlled"] = false
	definition["blocks_movement"] = true
	return definition


func _same_location_entry(npc_id: String, suffix: String, start_time: String, end_time: String, location_id: String, target: Dictionary, activity: String) -> Dictionary:
	var anchor_id := str(target.get("anchor_id", ""))
	var entry := {
		"id": "%s__%s" % [npc_id, suffix],
		"start": start_time,
		"end": end_time,
		"location_id": location_id,
		"anchor_id": anchor_id,
		"facing": str(target.get("facing", "down")),
		"activity_type": "work",
		"activity": activity,
		"movement": "walk",
		"source_location_id": location_id,
		"source_anchor_id": anchor_id,
		"target_location_id": location_id,
		"target_anchor_id": anchor_id,
		"transition_kind": "same_location",
		"departure_location_id": location_id,
		"departure_anchor_id": anchor_id,
		"arrival_location_id": location_id,
		"arrival_anchor_id": anchor_id,
		"transition_anchor_by_location": {},
	}
	(entry.get("transition_anchor_by_location", {}) as Dictionary)[location_id] = anchor_id
	if target.has("grid_position"):
		entry["grid_position"] = (target.get("grid_position", {}) as Dictionary).duplicate(true)
	if target.has("activity_cells"):
		entry["activity_cells"] = (target.get("activity_cells", []) as Array).duplicate(true)
	return entry


func _cross_location_entry(
	npc_id: String,
	suffix: String,
	start_time: String,
	end_time: String,
	source_location_id: String,
	source_target: Dictionary,
	target_location_id: String,
	target: Dictionary,
	source_transition_anchor_id: String,
	target_transition_anchor_id: String,
	activity: String
) -> Dictionary:
	var target_anchor_id := str(target.get("anchor_id", ""))
	var source_anchor_id := str(source_target.get("anchor_id", ""))
	var transition_anchors := {}
	transition_anchors[source_location_id] = source_transition_anchor_id
	transition_anchors[target_location_id] = target_transition_anchor_id
	var entry := {
		"id": "%s__%s" % [npc_id, suffix],
		"start": start_time,
		"end": end_time,
		"location_id": target_location_id,
		"anchor_id": target_anchor_id,
		"facing": str(target.get("facing", "down")),
		"activity_type": "travel",
		"activity": activity,
		"movement": "walk",
		"source_location_id": source_location_id,
		"source_anchor_id": source_anchor_id,
		"target_location_id": target_location_id,
		"target_anchor_id": target_anchor_id,
		"transition_kind": "cross_location",
		"departure_location_id": source_location_id,
		"departure_anchor_id": source_transition_anchor_id,
		"arrival_location_id": target_location_id,
		"arrival_anchor_id": target_transition_anchor_id,
		"transition_anchor_by_location": transition_anchors,
	}
	if target.has("grid_position"):
		entry["grid_position"] = (target.get("grid_position", {}) as Dictionary).duplicate(true)
	if target.has("activity_cells"):
		entry["activity_cells"] = (target.get("activity_cells", []) as Array).duplicate(true)
	if target.has("exterior_location_id"):
		entry["exterior_location_id"] = str(target.get("exterior_location_id", ""))
	if target.has("interior_location_id"):
		entry["interior_location_id"] = str(target.get("interior_location_id", ""))
	if target.has("exterior_anchor_id"):
		entry["exterior_anchor_id"] = str(target.get("exterior_anchor_id", ""))
	return entry


func _player_spawn_row(cell: Dictionary) -> Dictionary:
	return {
		"id": "debug_player",
		"source": "res://data/characters/debug_player.json",
		"grid_position": cell.duplicate(true),
		"facing": "down",
		"is_player_controlled": true,
	}


func _instantiate_runtime_location(root: Node, location_data: Dictionary, path: String) -> Node:
	var scene := load(BASIC_INTERIOR_SCENE) as PackedScene
	if scene == null:
		_fail("v67.3 runtime test could not load basic location shell")
		return null
	SceneLoader.consume_pending_location_context()
	var instance := scene.instantiate()
	instance.location_data_path = path
	if instance.has_method("set_save_runtime_on_exit"):
		instance.set_save_runtime_on_exit(false)
	root.add_child(instance)
	return instance


func _tick_location(instance: Node, count: int) -> void:
	if instance == null:
		return
	for _index in range(count):
		if instance.has_method("_process"):
			instance._process(0.30)


func _anchor_cell(grid: LocationGrid, anchor_id: String) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	var anchor: Dictionary = grid.get_anchor(anchor_id)
	return _cell_from_dict(anchor.get("grid_position", {}) as Dictionary)


func _absolute_minutes(day: int, hour: int, minute: int) -> int:
	return (maxi(day, 1) - 1) * TimeManager.MINUTES_PER_DAY + clampi(hour, 0, 23) * 60 + clampi(minute, 0, 59)


func _write_json(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("v67.3 could not write JSON file: %s" % path)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	DefinitionLoader.clear_cache(path)
	DefinitionLoader.clear_generated_runtime_cache()
	return true


func _cell_key_from_dict(value: Dictionary) -> String:
	return "%d,%d" % [int(value.get("x", 0)), int(value.get("y", 0))]


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))


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
