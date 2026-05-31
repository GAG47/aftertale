extends Node2D

signal location_ready(location_id: String)
signal grid_position_changed(cell: Vector2i)
signal exit_requested(exit_data: Dictionary)

@export_file("*.json") var location_data_path: String = ""
@export var entrance_id: String = ""

@onready var tile_renderer: DebugTileRenderer = $DebugTileRenderer
@onready var objects_root: Node2D = $Objects
@onready var characters_root: Node2D = $Characters
@onready var camera: Camera2D = $Camera2D

var grid: LocationGrid
var crops_root: Node2D
var battle_overlay: BattleGridOverlay
var current_grid_position: Vector2i = Vector2i.ZERO
var controlled_character: CharacterEntity
var _location_data_cache: Dictionary = {}
var _character_spawn_data_by_id: Dictionary = {}
var _character_definition_by_id: Dictionary = {}
var _save_runtime_on_exit: bool = true


func _ready() -> void:
	_load_location_data()
	if grid == null:
		return

	_spawn_objects_from_data()
	_setup_battle_overlay()
	_setup_crops_root()
	refresh_crop_markers()
	_spawn_characters_from_data()

	InputManager.move_requested.connect(_on_move_requested)
	InputManager.primary_action_requested.connect(_on_primary_action_requested)
	InputManager.rest_requested.connect(_on_rest_requested)
	CropSystem.crop_changed.connect(_on_crop_changed)
	BattleSystem.battle_state_changed.connect(_refresh_battle_overlay)
	NpcScheduleSystem.register_location_root(self)
	GameState.set_scene_context(grid.location_id, grid.location_id)
	location_ready.emit(grid.location_id)


func _exit_tree() -> void:
	if _save_runtime_on_exit and _has_controlled_character():
		GameState.save_character_runtime(controlled_character)

	if InputManager.move_requested.is_connected(_on_move_requested):
		InputManager.move_requested.disconnect(_on_move_requested)
	if InputManager.primary_action_requested.is_connected(_on_primary_action_requested):
		InputManager.primary_action_requested.disconnect(_on_primary_action_requested)
	if InputManager.rest_requested.is_connected(_on_rest_requested):
		InputManager.rest_requested.disconnect(_on_rest_requested)
	if CropSystem.crop_changed.is_connected(_on_crop_changed):
		CropSystem.crop_changed.disconnect(_on_crop_changed)
	if BattleSystem.battle_state_changed.is_connected(_refresh_battle_overlay):
		BattleSystem.battle_state_changed.disconnect(_refresh_battle_overlay)
	NpcScheduleSystem.unregister_location_root(self)


func grid_to_world(cell: Vector2i) -> Vector2:
	if grid == null:
		return Vector2.ZERO
	return grid.grid_to_world(cell)


func get_location_grid() -> LocationGrid:
	return grid


func get_controlled_character() -> CharacterEntity:
	if not _has_controlled_character():
		return null

	return controlled_character


func get_controlled_character_state() -> Dictionary:
	if not _has_controlled_character():
		return {}

	return {
		"character_id": controlled_character.character_id,
		"grid_position": {
			"x": controlled_character.grid_position.x,
			"y": controlled_character.grid_position.y,
		},
		"facing": controlled_character.facing,
	}


func restore_controlled_character(state: Dictionary) -> bool:
	if grid == null or not _has_controlled_character():
		return false

	var saved_character_id: String = str(state.get("character_id", controlled_character.character_id))
	if saved_character_id != controlled_character.character_id:
		return false

	var saved_position: Dictionary = state.get("grid_position", {}) as Dictionary
	var saved_cell: Vector2i = Vector2i(
		int(saved_position.get("x", controlled_character.grid_position.x)),
		int(saved_position.get("y", controlled_character.grid_position.y))
	)
	var saved_facing: String = str(state.get("facing", controlled_character.facing))
	if not grid.in_bounds(saved_cell) or not grid.is_walkable(saved_cell):
		return false

	var previous_cell: Vector2i = controlled_character.grid_position
	grid.unregister_character(controlled_character.character_id)
	if not grid.register_character(controlled_character.character_id, saved_cell, controlled_character, controlled_character.blocks_movement):
		grid.register_character(controlled_character.character_id, previous_cell, controlled_character, controlled_character.blocks_movement)
		return false

	controlled_character.set_grid_position(saved_cell)
	controlled_character.set_facing(saved_facing)
	current_grid_position = saved_cell
	grid_position_changed.emit(current_grid_position)
	GameState.save_character_runtime(controlled_character)
	return true


func set_entrance_id(value: String) -> void:
	entrance_id = value


func set_save_runtime_on_exit(value: bool) -> void:
	_save_runtime_on_exit = value


func is_cell_plantable(cell: Vector2i) -> bool:
	if grid == null or not grid.in_bounds(cell):
		return false

	var terrain_data: Dictionary = grid.terrain_at(cell)
	return bool(terrain_data.get("plantable", false))


func refresh_crop_markers() -> void:
	if grid == null:
		return
	if crops_root == null or not is_instance_valid(crops_root):
		return

	for child in crops_root.get_children():
		child.queue_free()

	var crops: Array = CropSystem.get_location_crops(grid.location_id)
	for crop_value in crops:
		var crop_state: Dictionary = crop_value as Dictionary
		var cell: Vector2i = _cell_from_dict(crop_state.get("cell", {}) as Dictionary)
		var crop_definition: Dictionary = CropSystem.get_crop_definition(str(crop_state.get("crop_id", "")))
		var marker: CropMarker = CropMarker.new()
		marker.position = grid.grid_to_world(cell)
		marker.configure(crop_state, crop_definition, grid.tile_size)
		crops_root.add_child(marker)


func get_location_summary() -> Dictionary:
	if grid == null:
		return {}

	return {
		"id": grid.location_id,
		"display_name": grid.display_name,
		"width": grid.width,
		"height": grid.height,
		"tile_size": grid.tile_size,
		"object_count": grid.objects_by_id.size(),
		"character_count": grid.characters_by_id.size(),
		"exit_count": grid.exits_by_cell.size(),
		"state": grid.state,
		"debug_position": current_grid_position,
		"controlled_character": _get_controlled_character_summary(),
		"controlled_inventory": _get_controlled_inventory_summary(),
		"characters": _get_character_summaries(),
		"crop_count": CropSystem.get_location_crops(grid.location_id).size(),
		"crops": CropSystem.get_location_crops(grid.location_id),
		"shops": (_location_data_cache.get("shops", []) as Array).duplicate(true),
	}


func _load_location_data() -> void:
	_location_data_cache = _read_location_data()
	if _location_data_cache.is_empty():
		return

	grid = LocationGrid.from_dictionary(_location_data_cache)
	if not grid.is_valid():
		push_error("Location data is invalid: %s" % location_data_path)
		return

	tile_renderer.configure(grid)
	camera.position = Vector2(grid.width * grid.tile_size, grid.height * grid.tile_size) * 0.5


func _spawn_objects_from_data() -> void:
	if _location_data_cache.is_empty():
		return

	var object_rows: Array = _location_data_cache.get("objects", []) as Array
	for object_data_value in object_rows:
		var object_data: Dictionary = object_data_value as Dictionary
		var object_id: String = str(object_data.get("id", ""))
		if GameState.is_location_object_removed(grid.location_id, object_id):
			continue

		var object: LocationObject = LocationObject.new()
		objects_root.add_child(object)
		object.configure(object_data, self)
		grid.register_object(object.object_id, object.grid_position, object, object.blocks_movement)


func _setup_crops_root() -> void:
	crops_root = Node2D.new()
	crops_root.name = "Crops"
	add_child(crops_root)
	move_child(crops_root, objects_root.get_index() + 1)


func _setup_battle_overlay() -> void:
	battle_overlay = BattleGridOverlay.new()
	battle_overlay.name = "BattleGridOverlay"
	battle_overlay.visible = false
	add_child(battle_overlay)
	move_child(battle_overlay, tile_renderer.get_index() + 1)
	battle_overlay.configure(grid)


func _spawn_characters_from_data() -> void:
	if _location_data_cache.is_empty():
		return

	var character_rows: Array = _location_data_cache.get("characters", []) as Array
	for character_spawn_value in character_rows:
		var spawn_data: Dictionary = character_spawn_value as Dictionary
		var source_path: String = str(spawn_data.get("source", ""))
		var definition: Dictionary = _read_json_resource(source_path)
		if definition.is_empty():
			continue

		var character_id: String = str(spawn_data.get("id", definition.get("id", "")))
		if character_id.is_empty():
			continue
		if GameState.is_location_character_removed(grid.location_id, character_id):
			continue

		_character_spawn_data_by_id[character_id] = spawn_data.duplicate(true)
		_character_definition_by_id[character_id] = definition.duplicate(true)

		var resolved_spawn_data: Dictionary = _build_spawn_data(spawn_data, definition)
		var active_entry: Dictionary = _get_active_schedule_entry(definition, resolved_spawn_data)
		if not active_entry.is_empty():
			var scheduled_location_id: String = str(active_entry.get("location_id", grid.location_id))
			if scheduled_location_id != grid.location_id:
				continue

			_apply_schedule_entry_to_spawn_data(resolved_spawn_data, active_entry, scheduled_location_id)

		_spawn_character(definition, resolved_spawn_data)


func _apply_entrance_to_spawn_data(spawn_data: Dictionary) -> void:
	var selected_entrance: String = entrance_id
	if selected_entrance.is_empty():
		if _location_data_cache.is_empty():
			return

		selected_entrance = str(_location_data_cache.get("default_entrance", ""))

	var entrance_cell: Vector2i = grid.get_entrance_cell(selected_entrance)
	spawn_data["grid_position"] = { "x": entrance_cell.x, "y": entrance_cell.y }

	var entrance_data: Dictionary = grid.get_entrance(selected_entrance)
	if entrance_data.has("facing"):
		spawn_data["facing"] = str(entrance_data.get("facing", "down"))


func apply_current_schedule(absolute_minutes: int) -> void:
	if grid == null:
		return

	var result: ActionResult = ActionResult.succeeded("ScheduleUpdate", "", {
		"location_id": grid.location_id,
		"absolute_minutes": absolute_minutes,
	})
	var change_count: int = 0

	for character_id_value in _character_spawn_data_by_id.keys():
		var character_id: String = str(character_id_value)
		var spawn_data: Dictionary = _character_spawn_data_by_id[character_id] as Dictionary
		var definition: Dictionary = _character_definition_by_id[character_id] as Dictionary
		if _is_player_spawn(spawn_data, definition):
			continue

		var active_entry: Dictionary = _get_active_schedule_entry(definition, spawn_data)
		if active_entry.is_empty():
			continue

		var scheduled_location_id: String = str(active_entry.get("location_id", grid.location_id))
		var character: CharacterEntity = grid.get_character_by_id(character_id)
		if scheduled_location_id != grid.location_id:
			if character != null:
				_remove_scheduled_character(character, active_entry, result)
				change_count += 1
			continue

		if character == null:
			var resolved_spawn_data: Dictionary = _build_spawn_data(spawn_data, definition)
			_apply_schedule_entry_to_spawn_data(resolved_spawn_data, active_entry, scheduled_location_id)
			var spawned_character: CharacterEntity = _spawn_character(definition, resolved_spawn_data)
			if spawned_character != null:
				result.add_world_change({
					"type": "scheduled_character_arrived",
					"character_id": spawned_character.character_id,
					"location_id": grid.location_id,
					"entry_id": spawned_character.current_schedule_entry_id,
					"grid_position": spawned_character.grid_position,
					"activity": spawned_character.current_activity,
				})
				result.add_feedback("%s arrived for %s." % [spawned_character.display_name, spawned_character.current_activity])
				NpcScheduleSystem.schedule_applied.emit(spawned_character.character_id, grid.location_id, spawned_character.current_schedule_entry_id)
				change_count += 1
			continue

		if _apply_schedule_entry_to_character(character, active_entry, scheduled_location_id, result):
			NpcScheduleSystem.schedule_applied.emit(character.character_id, grid.location_id, character.current_schedule_entry_id)
			change_count += 1

	if change_count > 0:
		ActionSystem.publish_result(result)


func _build_spawn_data(spawn_data: Dictionary, definition: Dictionary) -> Dictionary:
	var resolved_spawn_data: Dictionary = spawn_data.duplicate(true)
	if bool(resolved_spawn_data.get("spawn_at_entrance", false)):
		_apply_entrance_to_spawn_data(resolved_spawn_data)

	if not resolved_spawn_data.has("id"):
		resolved_spawn_data["id"] = str(definition.get("id", ""))

	return resolved_spawn_data


func _spawn_character(definition: Dictionary, resolved_spawn_data: Dictionary) -> CharacterEntity:
	var character: CharacterEntity = CharacterEntity.new()
	characters_root.add_child(character)
	character.configure(definition, resolved_spawn_data, self)

	var registered: bool = grid.register_character(
		character.character_id,
		character.grid_position,
		character,
		character.blocks_movement
	)
	if not registered:
		character.queue_free()
		return null

	if character.is_player_controlled:
		var runtime_state: Dictionary = GameState.get_character_runtime(character.character_id)
		if not runtime_state.is_empty():
			character.apply_runtime_state(runtime_state)
		controlled_character = character
		current_grid_position = character.grid_position
		GameState.player_id = character.character_id

	return character


func _get_active_schedule_entry(definition: Dictionary, spawn_data: Dictionary) -> Dictionary:
	var schedule_rows: Array = spawn_data.get("schedule", definition.get("schedule", [])) as Array
	if schedule_rows.is_empty():
		return {}

	return NpcScheduleSystem.get_active_entry(schedule_rows, TimeManager.get_absolute_minutes())


func _apply_schedule_entry_to_spawn_data(spawn_data: Dictionary, entry: Dictionary, scheduled_location_id: String) -> void:
	if entry.has("grid_position"):
		spawn_data["grid_position"] = (entry.get("grid_position", {}) as Dictionary).duplicate(true)
	if entry.has("facing"):
		spawn_data["facing"] = str(entry.get("facing", "down"))

	spawn_data["schedule_entry_id"] = str(entry.get("id", ""))
	spawn_data["activity"] = str(entry.get("activity", "idle"))
	spawn_data["scheduled_location_id"] = scheduled_location_id


func _apply_schedule_entry_to_character(character: CharacterEntity, entry: Dictionary, scheduled_location_id: String, result: ActionResult) -> bool:
	var entry_id: String = str(entry.get("id", ""))
	var next_activity: String = str(entry.get("activity", character.current_activity))
	var next_facing: String = str(entry.get("facing", character.facing))
	var entry_changed: bool = character.current_schedule_entry_id != entry_id
	var activity_changed: bool = character.current_activity != next_activity
	var facing_changed: bool = character.facing != next_facing
	var changed: bool = false

	if entry.has("grid_position"):
		var target_position: Dictionary = entry.get("grid_position", {}) as Dictionary
		var target_cell: Vector2i = _cell_from_dict(target_position)
		if character.grid_position != target_cell and (entry_changed or activity_changed):
			if _move_scheduled_character(character, target_cell, result):
				changed = true
			else:
				result.add_world_change({
					"type": "scheduled_character_blocked",
					"character_id": character.character_id,
					"location_id": grid.location_id,
					"entry_id": entry_id,
					"target": target_cell,
				})
				result.add_feedback("%s could not reach scheduled activity %s." % [character.display_name, next_activity])
				changed = true

	if facing_changed:
		character.set_facing(next_facing)
		changed = true

	if entry_changed or activity_changed or changed:
		character.set_schedule_state(entry, scheduled_location_id)
		result.add_world_change({
			"type": "scheduled_character_state_changed",
			"character_id": character.character_id,
			"location_id": grid.location_id,
			"entry_id": character.current_schedule_entry_id,
			"activity": character.current_activity,
			"grid_position": character.grid_position,
			"facing": character.facing,
		})
		result.add_feedback("%s is now %s." % [character.display_name, character.current_activity])
		return true

	return false


func _move_scheduled_character(character: CharacterEntity, target_cell: Vector2i, result: ActionResult) -> bool:
	if not grid.can_enter(target_cell):
		return false

	var from_cell: Vector2i = character.grid_position
	if not grid.move_character(character.character_id, from_cell, target_cell, character.blocks_movement):
		return false

	character.set_grid_position(target_cell)
	result.add_world_change({
		"type": "scheduled_character_moved",
		"character_id": character.character_id,
		"from": from_cell,
		"to": target_cell,
		"location_id": grid.location_id,
	})
	return true


func _remove_scheduled_character(character: CharacterEntity, entry: Dictionary, result: ActionResult) -> void:
	grid.unregister_character(character.character_id)
	result.add_world_change({
		"type": "scheduled_character_departed",
		"character_id": character.character_id,
		"from_location_id": grid.location_id,
		"to_location_id": str(entry.get("location_id", "")),
		"entry_id": str(entry.get("id", "")),
		"activity": str(entry.get("activity", "idle")),
	})
	result.add_feedback("%s left for %s." % [character.display_name, str(entry.get("activity", "a schedule"))])
	NpcScheduleSystem.schedule_applied.emit(character.character_id, grid.location_id, str(entry.get("id", "")))
	character.queue_free()


func _is_player_spawn(spawn_data: Dictionary, definition: Dictionary) -> bool:
	return bool(spawn_data.get("is_player_controlled", definition.get("is_player_controlled", false)))


func _on_move_requested(direction: Vector2i) -> void:
	if GameState.current_mode == GameState.GameMode.COMBAT:
		BattleSystem.request_move_current_unit(direction)
		_refresh_battle_overlay()
		return

	if GameState.current_mode != GameState.GameMode.EXPLORATION:
		return

	if grid == null or not _has_controlled_character():
		return

	var target: Dictionary = { "direction": direction }
	var context: Dictionary = { "location_root": self }
	var action: GameAction = ActionSystem.create_action("MoveAction", controlled_character, target, context) as GameAction
	var result: ActionResult = ActionSystem.submit(action) as ActionResult
	if result.success and not _result_has_change_type(result, "location_exit_requested") and _has_controlled_character():
		current_grid_position = controlled_character.grid_position
		grid_position_changed.emit(current_grid_position)


func request_exit_transition(exit_data: Dictionary) -> void:
	exit_requested.emit(exit_data)
	SceneLoader.load_location(
		str(exit_data.get("target_scene_path", "")),
		str(exit_data.get("target_entrance_id", ""))
	)


func remove_location_object(object_id: String) -> bool:
	var object: LocationObject = grid.get_object_by_id(object_id)
	if object == null:
		return false

	grid.unregister_object(object_id)
	GameState.mark_location_object_removed(grid.location_id, object_id)
	object.queue_free()
	return true


func mark_character_defeated(character_id: String) -> bool:
	if grid == null or character_id.is_empty():
		return false

	var character: CharacterEntity = grid.get_character_by_id(character_id)
	if character == null:
		return false

	_character_spawn_data_by_id.erase(character_id)
	_character_definition_by_id.erase(character_id)
	grid.unregister_character(character_id)
	GameState.mark_location_character_removed(grid.location_id, character_id)
	if controlled_character == character:
		controlled_character = null
	character.queue_free()
	return true


func _on_primary_action_requested() -> void:
	if GameState.current_mode == GameState.GameMode.COMBAT:
		BattleSystem.request_attack_current_unit()
		_refresh_battle_overlay()
		return

	if GameState.current_mode != GameState.GameMode.EXPLORATION:
		return

	if not _has_controlled_character() or grid == null:
		return

	var target_cell: Vector2i = controlled_character.get_facing_cell()
	var target_character: CharacterEntity = grid.get_character_at(target_cell)
	if target_character != null and target_character.is_combatable:
		_submit_battle_start(target_character)
		return

	if target_character != null and target_character.is_interactable:
		_submit_talk_interaction(target_character)
		return

	var current_object: LocationObject = grid.get_primary_object_at(controlled_character.grid_position)
	if current_object != null and current_object.is_pickable:
		_submit_object_interaction(current_object, controlled_character.grid_position)
		return

	if _try_submit_crop_interaction(controlled_character.grid_position):
		return

	var target_object: LocationObject = grid.get_primary_object_at(target_cell)
	if target_object == null:
		_submit_inspect_empty(target_cell)
		return

	_submit_object_interaction(target_object, target_cell)


func _on_rest_requested() -> void:
	if GameState.current_mode == GameState.GameMode.COMBAT:
		BattleSystem.wait_current_unit()
		_refresh_battle_overlay()
		return

	if GameState.current_mode != GameState.GameMode.EXPLORATION:
		return

	if not _has_controlled_character():
		return

	var target: Dictionary = { "minutes": 60 }
	var context: Dictionary = { "location_root": self }
	var action: GameAction = ActionSystem.create_action("RestAction", controlled_character, target, context) as GameAction
	ActionSystem.submit(action)


func _try_submit_crop_interaction(cell: Vector2i) -> bool:
	if grid == null or not _has_controlled_character():
		return false

	var crop_state: Dictionary = CropSystem.get_crop_at(grid.location_id, cell)
	if not crop_state.is_empty():
		if bool(crop_state.get("mature", false)):
			_submit_crop_action("HarvestAction", cell)
			return true
		if not bool(crop_state.get("watered", false)):
			_submit_crop_action("WaterAction", cell)
			return true

		ActionSystem.publish_result(ActionResult.failed("InspectCrop", controlled_character.character_id, "%s is still growing." % str(crop_state.get("display_name", "The crop"))))
		return true

	if is_cell_plantable(cell) and not CropSystem.get_seed_item_id(controlled_character).is_empty():
		_submit_crop_action("PlantAction", cell)
		return true

	return false


func _submit_crop_action(action_type: String, cell: Vector2i) -> void:
	var target: Dictionary = {
		"cell": cell,
	}
	var context: Dictionary = {
		"location_root": self,
	}
	var action: GameAction = ActionSystem.create_action(action_type, controlled_character, target, context) as GameAction
	ActionSystem.submit(action)


func try_flee_battle() -> bool:
	if GameState.current_mode != GameState.GameMode.COMBAT:
		return false

	BattleSystem.flee_current_unit()
	_refresh_battle_overlay()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if GameState.current_mode != GameState.GameMode.COMBAT:
		_update_battle_hover(Vector2i(-9999, -9999), "", [])
		return
	if grid == null or not BattleSystem.is_player_turn():
		_update_battle_hover(Vector2i(-9999, -9999), "", [])
		return
	if event is InputEventMouseMotion:
		_update_battle_hover_from_mouse()
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	var clicked_cell: Vector2i = _mouse_to_grid_cell()
	if not grid.in_bounds(clicked_cell):
		return

	get_viewport().set_input_as_handled()
	_submit_battle_click(clicked_cell)


func _submit_battle_click(clicked_cell: Vector2i) -> void:
	var preview: Dictionary = BattleSystem.get_player_tactical_preview()
	var attack_cells: Array = preview.get("attack_cells", []) as Array
	if _cell_array_has(attack_cells, clicked_cell):
		BattleSystem.request_use_skill_current_unit(BattleSystem.get_selected_skill_id(), clicked_cell)
		_refresh_battle_overlay()
		return

	var move_cells: Array = preview.get("move_cells", []) as Array
	if _cell_array_has(move_cells, clicked_cell):
		BattleSystem.request_move_current_unit_to(clicked_cell)
		_refresh_battle_overlay()
		return

	var target_character: CharacterEntity = grid.get_character_at(clicked_cell)
	if target_character != null:
		BattleSystem.request_use_skill_current_unit(BattleSystem.get_selected_skill_id(), clicked_cell)
		_refresh_battle_overlay()
		return

	ActionSystem.publish_result(ActionResult.failed("BattleSelect", GameState.player_id, "请选择高亮的移动格，或选择可攻击的目标。"))


func _update_battle_hover_from_mouse() -> void:
	var hover_grid_cell: Vector2i = _mouse_to_grid_cell()
	if not grid.in_bounds(hover_grid_cell):
		_update_battle_hover(Vector2i(-9999, -9999), "", [])
		return

	var preview: Dictionary = BattleSystem.get_player_tactical_preview()
	var attack_cells: Array = preview.get("attack_cells", []) as Array
	if _cell_array_has(attack_cells, hover_grid_cell):
		_update_battle_hover(hover_grid_cell, "attack", BattleSystem.get_area_cells_for_current_skill(hover_grid_cell))
		return

	var move_cells: Array = preview.get("move_cells", []) as Array
	if _cell_array_has(move_cells, hover_grid_cell):
		_update_battle_hover(hover_grid_cell, "move", [])
		return

	_update_battle_hover(Vector2i(-9999, -9999), "", [])


func _update_battle_hover(cell: Vector2i, kind: String, area_cells: Array = []) -> void:
	if battle_overlay == null or not is_instance_valid(battle_overlay):
		return

	battle_overlay.set_hover_cell(cell, kind, area_cells)


func _refresh_battle_overlay() -> void:
	if battle_overlay == null or not is_instance_valid(battle_overlay):
		return

	if not BattleSystem.is_active():
		battle_overlay.clear_preview()
		return

	battle_overlay.set_preview(BattleSystem.get_player_tactical_preview())


func _mouse_to_grid_cell() -> Vector2i:
	var local_position: Vector2 = to_local(get_global_mouse_position())
	return Vector2i(floori(local_position.x / float(grid.tile_size)), floori(local_position.y / float(grid.tile_size)))


func _cell_array_has(cells: Array, target_cell: Vector2i) -> bool:
	for cell_value in cells:
		var cell: Vector2i = cell_value as Vector2i
		if cell == target_cell:
			return true

	return false


func _submit_object_interaction(target_object: LocationObject, target_cell: Vector2i) -> void:
	var target: Dictionary = {
		"object": target_object,
		"target_cell": target_cell,
	}
	var context: Dictionary = { "location_root": self }
	var action_type: String = _choose_interaction_action(target_object)
	var action: GameAction = ActionSystem.create_action(action_type, controlled_character, target, context) as GameAction
	ActionSystem.submit(action)


func _submit_talk_interaction(target_character: CharacterEntity) -> void:
	var target: Dictionary = { "speaker": target_character }
	var context: Dictionary = { "location_root": self }
	var action: GameAction = ActionSystem.create_action("TalkAction", controlled_character, target, context) as GameAction
	ActionSystem.submit(action)


func _submit_battle_start(target_character: CharacterEntity) -> void:
	BattleSystem.start_battle(self, controlled_character, target_character)


func _submit_inspect_empty(target_cell: Vector2i) -> void:
	var target: Dictionary = {
		"target_cell": target_cell,
		"empty": true,
	}
	var context: Dictionary = { "location_root": self }
	var action: GameAction = ActionSystem.create_action("InspectAction", controlled_character, target, context) as GameAction
	ActionSystem.submit(action)


func _choose_interaction_action(target_object: LocationObject) -> String:
	if target_object.is_pickable:
		return "PickUpAction"
	if target_object.is_usable:
		return "UseItemAction"
	return "InspectAction"


func _read_location_data() -> Dictionary:
	return DefinitionLoader.load_location(location_data_path)


func _read_json_resource(resource_path: String) -> Dictionary:
	return DefinitionLoader.load_json_resource(resource_path)


func _on_crop_changed(location_id: String, _cell: Vector2i, _crop_state: Dictionary) -> void:
	if grid == null or location_id != grid.location_id:
		return

	refresh_crop_markers()


func _get_controlled_character_summary() -> Dictionary:
	if not _has_controlled_character():
		return {}

	return controlled_character.get_summary()


func _get_controlled_inventory_summary() -> Array:
	if not _has_controlled_character() or controlled_character.inventory == null:
		return []

	return controlled_character.inventory.get_summary()


func _get_character_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	if grid == null:
		return summaries

	for character_value in grid.characters_by_id.values():
		if typeof(character_value) != TYPE_OBJECT or not is_instance_valid(character_value):
			continue
		var character: CharacterEntity = character_value as CharacterEntity
		if character != null:
			summaries.append(character.get_summary())

	return summaries


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))


func _has_controlled_character() -> bool:
	return controlled_character != null and is_instance_valid(controlled_character)


func _result_has_change_type(result: ActionResult, change_type: String) -> bool:
	if result == null:
		return false

	for change in result.world_changes:
		if str(change.get("type", "")) == change_type:
			return true

	return false
