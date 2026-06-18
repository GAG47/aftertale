extends Node2D

signal location_ready(location_id: String)
signal grid_position_changed(cell: Vector2i)
signal exit_requested(exit_data: Dictionary)
signal facility_requested(facility_data: Dictionary)

const NpcMovementAgentScript := preload("res://scripts/systems/schedules/npc_movement_agent.gd")
const NpcActivityAgentScript := preload("res://scripts/systems/schedules/npc_activity_agent.gd")
const NpcAutonomyAgentScript := preload("res://scripts/systems/schedules/npc_autonomy_agent.gd")
const CAMERA_ZOOM_MIN := 0.75
const CAMERA_ZOOM_MAX := 3.0
const CAMERA_ZOOM_STEP := 0.15
const CAMERA_DEAD_ZONE_RATIO := Vector2(0.42, 0.42)
const CAMERA_MANUAL_PAN_SPEED := 520.0
const CAMERA_SMOOTH_SPEED := 8.0
const CAMERA_SNAP_DISTANCE := 0.35

@export_file("*.json") var location_data_path: String = ""
@export var entrance_id: String = ""

@onready var tile_renderer: DebugTileRenderer = $DebugTileRenderer
@onready var floor_decoration_renderer: Node = get_node_or_null("FloorDecorationRenderer")
@onready var structure_renderer: Node = get_node_or_null("StructureRenderer")
@onready var building_renderer: Node = get_node_or_null("BuildingRenderer")
@onready var objects_root: Node2D = $Objects
@onready var characters_root: Node2D = $Characters
@onready var camera: Camera2D = $Camera2D

var grid: LocationGrid
var crops_root: Node2D
var battle_overlay: BattleGridOverlay
var battle_feedback_root: Node2D
var interaction_overlay: InteractionTargetOverlay
var current_grid_position: Vector2i = Vector2i.ZERO
var controlled_character: CharacterEntity
var _location_data_cache: Dictionary = {}
var _character_spawn_data_by_id: Dictionary = {}
var _character_definition_by_id: Dictionary = {}
var _save_runtime_on_exit: bool = true
var _party_follower_ids: Array[String] = []
var _npc_movement_agent
var _npc_activity_agent
var _npc_autonomy_agent
var _camera_default_zoom: Vector2 = Vector2.ONE
var _camera_detached: bool = false
var _camera_target_position: Vector2 = Vector2.ZERO
var _last_camera_viewport_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	_setup_scene_layer_order()
	_load_location_data()
	if grid == null:
		return

	_spawn_objects_from_data()
	_setup_battle_overlay()
	_setup_battle_feedback_root()
	_setup_interaction_overlay()
	_setup_crops_root()
	refresh_crop_markers()
	_spawn_characters_from_data()
	_sync_party_followers()
	_recenter_camera_to_focus(true)
	_set_camera_target(_camera_target_position, true)
	_refresh_interaction_overlay()

	InputManager.move_requested.connect(_on_move_requested)
	InputManager.primary_action_requested.connect(_on_primary_action_requested)
	InputManager.rest_requested.connect(_on_rest_requested)
	InputManager.camera_zoom_requested.connect(_on_camera_zoom_requested)
	InputManager.camera_zoom_reset_requested.connect(_on_camera_zoom_reset_requested)
	InputManager.camera_pan_requested.connect(_on_camera_pan_requested)
	InputManager.camera_drag_requested.connect(_on_camera_drag_requested)
	InputManager.camera_recenter_requested.connect(_on_camera_recenter_requested)
	ActionSystem.action_executed.connect(_on_action_result_for_presentation)
	ActionSystem.action_failed.connect(_on_action_result_for_presentation)
	PartySystem.party_changed.connect(_on_party_changed)
	CropSystem.crop_changed.connect(_on_crop_changed)
	BattleSystem.battle_state_changed.connect(_refresh_battle_overlay)
	NpcScheduleSystem.register_location_root(self)
	GameState.set_scene_context(grid.location_id, grid.location_id)
	location_ready.emit(grid.location_id)


func _process(delta: float) -> void:
	_update_camera_viewport_fit()
	_update_manual_camera_keyboard_pan(delta)
	_update_camera_smoothing(delta)
	_update_npc_schedule_movement(delta)
	_update_npc_autonomy(delta)
	_update_npc_activities(delta)


func _setup_scene_layer_order() -> void:
	tile_renderer.z_index = -100
	if floor_decoration_renderer != null:
		floor_decoration_renderer.z_index = -50
	objects_root.z_index = 0
	if structure_renderer != null:
		structure_renderer.z_index = 5
	characters_root.z_index = 10
	characters_root.y_sort_enabled = true
	if building_renderer != null:
		building_renderer.z_index = 30


func _exit_tree() -> void:
	if _save_runtime_on_exit and _has_controlled_character():
		GameState.save_character_runtime(controlled_character)

	if InputManager.move_requested.is_connected(_on_move_requested):
		InputManager.move_requested.disconnect(_on_move_requested)
	if InputManager.primary_action_requested.is_connected(_on_primary_action_requested):
		InputManager.primary_action_requested.disconnect(_on_primary_action_requested)
	if InputManager.rest_requested.is_connected(_on_rest_requested):
		InputManager.rest_requested.disconnect(_on_rest_requested)
	if InputManager.camera_zoom_requested.is_connected(_on_camera_zoom_requested):
		InputManager.camera_zoom_requested.disconnect(_on_camera_zoom_requested)
	if InputManager.camera_zoom_reset_requested.is_connected(_on_camera_zoom_reset_requested):
		InputManager.camera_zoom_reset_requested.disconnect(_on_camera_zoom_reset_requested)
	if InputManager.camera_pan_requested.is_connected(_on_camera_pan_requested):
		InputManager.camera_pan_requested.disconnect(_on_camera_pan_requested)
	if InputManager.camera_drag_requested.is_connected(_on_camera_drag_requested):
		InputManager.camera_drag_requested.disconnect(_on_camera_drag_requested)
	if InputManager.camera_recenter_requested.is_connected(_on_camera_recenter_requested):
		InputManager.camera_recenter_requested.disconnect(_on_camera_recenter_requested)
	if ActionSystem.action_executed.is_connected(_on_action_result_for_presentation):
		ActionSystem.action_executed.disconnect(_on_action_result_for_presentation)
	if ActionSystem.action_failed.is_connected(_on_action_result_for_presentation):
		ActionSystem.action_failed.disconnect(_on_action_result_for_presentation)
	if PartySystem.party_changed.is_connected(_on_party_changed):
		PartySystem.party_changed.disconnect(_on_party_changed)
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
	_update_building_renderer_focus()
	grid_position_changed.emit(current_grid_position)
	GameState.save_character_runtime(controlled_character)
	return true


func set_entrance_id(value: String) -> void:
	entrance_id = value


func set_save_runtime_on_exit(value: bool) -> void:
	_save_runtime_on_exit = value


func set_debug_presentation_visible(value: bool) -> void:
	for renderer in [floor_decoration_renderer, structure_renderer, building_renderer]:
		if renderer == null:
			continue
		if renderer.has_method("set_debug_layers_visible"):
			renderer.set_debug_layers_visible(value)


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


func get_interaction_prompt() -> String:
	if grid == null or not _has_controlled_character():
		return ""

	var current_object: LocationObject = grid.get_primary_object_at(controlled_character.grid_position)
	if current_object != null and current_object.is_pickable:
		return "E/Enter 拾取：%s" % current_object.display_name

	var crop_prompt: String = _get_crop_interaction_prompt(controlled_character.grid_position)
	if not crop_prompt.is_empty():
		return crop_prompt

	var current_transition_prompt := _get_current_cell_transition_prompt(controlled_character.grid_position)
	if not current_transition_prompt.is_empty():
		return current_transition_prompt

	var target_cell: Vector2i = controlled_character.get_facing_cell()
	var target_character: CharacterEntity = grid.get_character_at(target_cell)
	if target_character != null:
		if PartySystem.is_member(target_character.character_id):
			return "E/Enter 调查前方  B 背包  J 任务  C 角色  滚轮/+/- 缩放"
		if target_character.is_combatable:
			return "E/Enter 攻击：%s" % target_character.display_name
		if target_character.is_interactable:
			return "E/Enter 交谈：%s" % target_character.display_name

	var target_object: LocationObject = grid.get_primary_object_at(target_cell)
	if target_object != null:
		if target_object.is_pickable:
			return "E/Enter 拾取：%s" % target_object.display_name
		if target_object.is_scene_transition():
			return "E/Enter 进入：%s" % target_object.display_name
		if target_object.is_facility():
			if target_object.facility_type == "crafting":
				return "E/Enter 制作：%s" % target_object.display_name
			if target_object.facility_type == "shop":
				return "E/Enter 交易：%s" % target_object.display_name
			if target_object.facility_type == "rest":
				return _get_rest_facility_prompt(target_object)
			if target_object.facility_type == "save":
				return "E/Enter 存档：%s" % target_object.display_name
		if target_object.is_usable:
			return "E/Enter 使用：%s" % target_object.display_name
		if target_object.is_inspectable:
			return "E/Enter 调查：%s" % target_object.display_name

	var exit_data: Dictionary = grid.get_exit_at(target_cell)
	if not exit_data.is_empty():
		return "向前移动：前往 %s" % str(exit_data.get("target_entrance_id", "下一个地点"))

	return "E/Enter 调查前方  B 背包  J 任务  C 角色  滚轮/+/- 缩放"


func _load_location_data() -> void:
	_location_data_cache = _read_location_data()
	if _location_data_cache.is_empty():
		return

	grid = LocationGrid.from_dictionary(_location_data_cache)
	if not grid.is_valid():
		push_error("Location data is invalid: %s" % location_data_path)
		return

	_setup_npc_movement_agent()
	_setup_npc_activity_agent()
	_setup_npc_autonomy_agent()
	tile_renderer.configure(grid)
	_configure_scene_layer_renderer(floor_decoration_renderer)
	_configure_scene_layer_renderer(structure_renderer)
	_configure_scene_layer_renderer(building_renderer)
	camera.position = Vector2(grid.width * grid.tile_size, grid.height * grid.tile_size) * 0.5
	_camera_target_position = camera.position
	var shared_zoom := clampf(SceneLoader.get_camera_zoom(), _get_camera_min_zoom(), CAMERA_ZOOM_MAX)
	camera.zoom = Vector2(shared_zoom, shared_zoom)
	_camera_default_zoom = Vector2(SceneLoader.get_default_camera_zoom(), SceneLoader.get_default_camera_zoom())
	_last_camera_viewport_size = get_viewport_rect().size
	_clamp_camera_to_map()


func _on_camera_zoom_requested(steps: int) -> void:
	if camera == null or steps == 0:
		return

	var target_zoom := clampf(camera.zoom.x + CAMERA_ZOOM_STEP * float(steps), _get_camera_min_zoom(), CAMERA_ZOOM_MAX)
	_set_camera_zoom(target_zoom)


func _on_camera_zoom_reset_requested() -> void:
	if camera == null:
		return

	_set_camera_zoom(clampf(_camera_default_zoom.x, _get_camera_min_zoom(), CAMERA_ZOOM_MAX))


func _set_camera_zoom(value: float) -> void:
	var clamped_value: float = clampf(value, _get_camera_min_zoom(), CAMERA_ZOOM_MAX)
	camera.zoom = Vector2(clamped_value, clamped_value)
	SceneLoader.set_camera_zoom(clamped_value)
	_set_camera_target(_camera_target_position, true)
	if not _camera_detached:
		_recenter_camera_to_focus(false)


func _update_camera_viewport_fit() -> void:
	if camera == null or grid == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size == _last_camera_viewport_size:
		return
	_last_camera_viewport_size = viewport_size
	var min_zoom: float = _get_camera_min_zoom()
	if camera.zoom.x < min_zoom:
		_set_camera_zoom(min_zoom)
	else:
		_set_camera_target(_camera_target_position, true)


func _get_camera_min_zoom() -> float:
	return CAMERA_ZOOM_MIN


func _on_camera_pan_requested(direction: Vector2i) -> void:
	_pan_camera(Vector2(direction), CAMERA_MANUAL_PAN_SPEED / maxf(0.1, camera.zoom.x) * 0.12)


func _on_camera_drag_requested(screen_delta: Vector2) -> void:
	if camera == null:
		return

	camera.position = _clamp_camera_position(camera.position - screen_delta / maxf(0.1, camera.zoom.x))
	_camera_target_position = camera.position
	_camera_detached = true


func _on_camera_recenter_requested() -> void:
	_recenter_camera_to_focus(true)


func _update_manual_camera_keyboard_pan(delta: float) -> void:
	if camera == null:
		return
	if not Input.is_key_pressed(KEY_SHIFT):
		return
	if InputManager.input_locked:
		return

	var direction := Vector2.ZERO
	if Input.is_action_pressed(InputManager.ACTION_MOVE_UP):
		direction.y -= 1.0
	if Input.is_action_pressed(InputManager.ACTION_MOVE_DOWN):
		direction.y += 1.0
	if Input.is_action_pressed(InputManager.ACTION_MOVE_LEFT):
		direction.x -= 1.0
	if Input.is_action_pressed(InputManager.ACTION_MOVE_RIGHT):
		direction.x += 1.0
	if direction == Vector2.ZERO:
		return

	_pan_camera(direction.normalized(), CAMERA_MANUAL_PAN_SPEED / maxf(0.1, camera.zoom.x) * delta)


func _pan_camera(direction: Vector2, amount: float) -> void:
	if camera == null or direction == Vector2.ZERO:
		return

	_camera_target_position = _clamp_camera_position(_camera_target_position + direction * amount)
	_camera_detached = true


func _update_camera_smoothing(delta: float) -> void:
	if camera == null:
		return

	_camera_target_position = _clamp_camera_position(_camera_target_position)
	var distance: float = camera.position.distance_to(_camera_target_position)
	if distance <= CAMERA_SNAP_DISTANCE:
		camera.position = _camera_target_position
		return

	var weight: float = 1.0 - exp(-CAMERA_SMOOTH_SPEED * maxf(0.0, delta))
	camera.position = camera.position.lerp(_camera_target_position, clampf(weight, 0.0, 1.0))


func _set_camera_target(target_position: Vector2, snap: bool = false) -> void:
	if camera == null:
		return

	_camera_target_position = _clamp_camera_position(target_position)
	if snap:
		camera.position = _camera_target_position


func _recenter_camera_to_focus(force_center: bool = true) -> void:
	var focus_position: Vector2 = _get_camera_focus_world_position()
	if focus_position == Vector2.INF:
		return

	_camera_detached = false
	if force_center:
		_set_camera_target(focus_position)
		return

	_ensure_camera_contains_world_position(focus_position)


func _get_camera_focus_world_position() -> Vector2:
	if camera == null:
		return Vector2.INF

	if GameState.current_mode == GameState.GameMode.COMBAT and BattleSystem.is_active():
		var battle_summary: Dictionary = BattleSystem.get_summary()
		var current_unit: Dictionary = battle_summary.get("current_unit", {}) as Dictionary
		var current_id: String = str(current_unit.get("character_id", ""))
		var current_character: CharacterEntity = grid.get_character_by_id(current_id) if grid != null else null
		if current_character != null:
			return current_character.position

	if _has_controlled_character():
		return controlled_character.position

	if grid != null:
		return Vector2(grid.width * grid.tile_size, grid.height * grid.tile_size) * 0.5

	return Vector2.INF


func _ensure_camera_contains_world_position(world_position: Vector2) -> void:
	if camera == null or world_position == Vector2.INF:
		return

	var dead_zone: Rect2 = _get_camera_dead_zone_world_rect()
	if dead_zone.has_point(world_position):
		return

	var target_position: Vector2 = _camera_target_position
	if world_position.x < dead_zone.position.x:
		target_position.x -= dead_zone.position.x - world_position.x
	elif world_position.x > dead_zone.position.x + dead_zone.size.x:
		target_position.x += world_position.x - (dead_zone.position.x + dead_zone.size.x)

	if world_position.y < dead_zone.position.y:
		target_position.y -= dead_zone.position.y - world_position.y
	elif world_position.y > dead_zone.position.y + dead_zone.size.y:
		target_position.y += world_position.y - (dead_zone.position.y + dead_zone.size.y)

	_set_camera_target(target_position)


func _is_world_position_visible(world_position: Vector2, margin_ratio: float = 0.08) -> bool:
	if camera == null:
		return true

	var visible_rect: Rect2 = _get_camera_visible_world_rect()
	var shrink_amount: Vector2 = visible_rect.size * clampf(margin_ratio, 0.0, 0.45)
	visible_rect.position += shrink_amount
	visible_rect.size -= shrink_amount * 2.0
	return visible_rect.has_point(world_position)


func _get_camera_dead_zone_world_rect() -> Rect2:
	var visible_rect: Rect2 = _get_camera_visible_world_rect()
	var dead_zone_size: Vector2 = visible_rect.size * CAMERA_DEAD_ZONE_RATIO
	return Rect2(_camera_target_position - dead_zone_size * 0.5, dead_zone_size)


func _get_camera_visible_world_rect() -> Rect2:
	if camera == null:
		return Rect2()

	var viewport_size: Vector2 = get_viewport_rect().size
	var zoom_value: float = maxf(0.1, camera.zoom.x)
	var visible_size: Vector2 = viewport_size / zoom_value
	return Rect2(_camera_target_position - visible_size * 0.5, visible_size)


func _clamp_camera_to_map() -> void:
	if camera == null or grid == null:
		return

	camera.position = _clamp_camera_position(camera.position)
	_camera_target_position = _clamp_camera_position(_camera_target_position)


func _clamp_camera_position(position_value: Vector2) -> Vector2:
	if camera == null or grid == null:
		return position_value

	var map_size := Vector2(grid.width * grid.tile_size, grid.height * grid.tile_size)
	var visible_size: Vector2 = get_viewport_rect().size / maxf(0.1, camera.zoom.x)
	var half_visible: Vector2 = visible_size * 0.5
	var result: Vector2 = position_value

	if map_size.x <= visible_size.x:
		result.x = map_size.x * 0.5
	else:
		result.x = clampf(result.x, half_visible.x, map_size.x - half_visible.x)

	if map_size.y <= visible_size.y:
		result.y = map_size.y * 0.5
	else:
		result.y = clampf(result.y, half_visible.y, map_size.y - half_visible.y)

	return result


func _setup_npc_movement_agent() -> void:
	_npc_movement_agent = NpcMovementAgentScript.new()
	_npc_movement_agent.configure(grid)


func _setup_npc_activity_agent() -> void:
	_npc_activity_agent = NpcActivityAgentScript.new()
	_npc_activity_agent.configure(grid)


func _setup_npc_autonomy_agent() -> void:
	_npc_autonomy_agent = NpcAutonomyAgentScript.new()
	_npc_autonomy_agent.configure(grid)


func _update_npc_schedule_movement(delta: float) -> void:
	if grid == null or _npc_movement_agent == null:
		return

	var events: Array[Dictionary] = _npc_movement_agent.update(delta)
	if events.is_empty():
		return

	var result: ActionResult = ActionResult.succeeded("NpcMovementUpdate", "", {
		"location_id": grid.location_id,
	})
	for event in events:
		result.add_world_change(event)
		match str(event.get("type", "")):
			"scheduled_character_arrived":
				result.add_feedback("%s arrived for %s." % [
					_get_character_display_name(str(event.get("character_id", ""))),
					str(event.get("activity", "schedule")),
				])
				_depart_scheduled_character_after_cross_scene_arrival(str(event.get("character_id", "")), result)
			"scheduled_character_blocked":
				result.add_feedback("%s could not continue scheduled movement." % _get_character_display_name(str(event.get("character_id", ""))))

	ActionSystem.publish_result(result)
	_refresh_interaction_overlay()


func _depart_scheduled_character_after_cross_scene_arrival(character_id: String, result: ActionResult) -> void:
	if grid == null or character_id.is_empty():
		return
	var character: CharacterEntity = grid.get_character_by_id(character_id)
	if character == null:
		return
	if character.scheduled_location_id.is_empty() or character.scheduled_location_id == grid.location_id:
		return
	var entry := _get_character_schedule_entry(character, character.current_schedule_entry_id)
	if entry.is_empty():
		entry = {
			"id": character.current_schedule_entry_id,
			"location_id": character.scheduled_location_id,
			"anchor_id": character.current_schedule_anchor_id,
			"activity": character.current_activity,
		}
	_remove_scheduled_character(character, entry, result)


func _get_character_schedule_entry(character: CharacterEntity, entry_id: String) -> Dictionary:
	if character == null or entry_id.is_empty():
		return {}
	for entry_value in character.schedule:
		var entry: Dictionary = entry_value as Dictionary
		if str(entry.get("id", "")) == entry_id:
			return entry.duplicate(true)
	return {}


func _update_npc_autonomy(delta: float) -> void:
	if grid == null or _npc_autonomy_agent == null:
		return

	var events: Array[Dictionary] = _npc_autonomy_agent.update(delta, _npc_movement_agent)
	if events.is_empty():
		return

	var result: ActionResult = ActionResult.succeeded("NpcAutonomyUpdate", "", {
		"location_id": grid.location_id,
	})
	var should_resume_schedule: bool = false
	for event in events:
		result.add_world_change(event)
		match str(event.get("type", "")):
			"scheduled_character_interruption_started":
				result.add_feedback("%s interrupted schedule: %s." % [
					_get_character_display_name(str(event.get("character_id", ""))),
					str(event.get("reason", "event")),
				])
			"scheduled_character_interruption_cleared":
				should_resume_schedule = true
				result.add_feedback("%s resumed schedule after %s." % [
					_get_character_display_name(str(event.get("character_id", ""))),
					str(event.get("reason", "event")),
				])

	ActionSystem.publish_result(result)
	if should_resume_schedule:
		apply_current_schedule(TimeManager.get_absolute_minutes())
	_refresh_interaction_overlay()


func _update_npc_activities(delta: float) -> void:
	if grid == null or _npc_activity_agent == null:
		return

	var events: Array[Dictionary] = _npc_activity_agent.update(delta, _npc_movement_agent)
	if events.is_empty():
		return

	var result: ActionResult = ActionResult.succeeded("NpcActivityUpdate", "", {
		"location_id": grid.location_id,
	})
	for event in events:
		result.add_world_change(event)
		if str(event.get("type", "")) == "scheduled_character_activity_entered":
			result.add_feedback("%s began %s." % [
				_get_character_display_name(str(event.get("character_id", ""))),
				str(event.get("activity", "an activity")),
			])

	ActionSystem.publish_result(result)
	_refresh_interaction_overlay()


func _configure_scene_layer_renderer(renderer: Node) -> void:
	if renderer == null or not renderer.has_method("configure"):
		return

	renderer.configure(
		grid,
		_location_data_cache.get("floor_overlays", []) as Array,
		_location_data_cache.get("floor_decorations", []) as Array,
		_location_data_cache.get("structures", []) as Array,
		_location_data_cache.get("roofs", []) as Array,
		_location_data_cache.get("zones", _location_data_cache.get("districts", [])) as Array
	)


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


func _setup_battle_feedback_root() -> void:
	battle_feedback_root = Node2D.new()
	battle_feedback_root.name = "BattleFeedback"
	add_child(battle_feedback_root)
	move_child(battle_feedback_root, characters_root.get_index() + 1)


func _setup_interaction_overlay() -> void:
	interaction_overlay = InteractionTargetOverlay.new()
	interaction_overlay.name = "InteractionTargetOverlay"
	add_child(interaction_overlay)
	move_child(interaction_overlay, tile_renderer.get_index() + 1)
	interaction_overlay.configure(grid)


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
		var offscreen_state: Dictionary = NpcScheduleSystem.get_offscreen_character_state(grid.location_id, character_id)
		var active_entry: Dictionary = _get_active_schedule_entry(definition, resolved_spawn_data)
		if not active_entry.is_empty():
			if not _schedule_entry_matches_location_context(active_entry):
				continue
			var scheduled_location_id: String = str(active_entry.get("location_id", grid.location_id))
			if scheduled_location_id != grid.location_id:
				continue

			_apply_schedule_entry_to_spawn_data(resolved_spawn_data, active_entry, scheduled_location_id)
			_apply_matching_offscreen_state_to_spawn_data(resolved_spawn_data, offscreen_state, active_entry)
		elif not offscreen_state.is_empty() and str(offscreen_state.get("location_id", grid.location_id)) == grid.location_id:
			_apply_offscreen_state_to_spawn_data(resolved_spawn_data, offscreen_state)

		_spawn_character(definition, resolved_spawn_data)

	if not _has_controlled_character():
		_spawn_default_player_from_entrance()


func _spawn_default_player_from_entrance() -> void:
	var definition := _read_json_resource("res://data/characters/debug_player.json")
	if definition.is_empty():
		return
	var spawn_data := {
		"id": "debug_player",
		"source": "res://data/characters/debug_player.json",
		"spawn_at_entrance": true,
		"facing": "right",
	}
	var resolved_spawn_data := _build_spawn_data(spawn_data, definition)
	_character_spawn_data_by_id["debug_player"] = spawn_data.duplicate(true)
	_character_definition_by_id["debug_player"] = definition.duplicate(true)
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
		if PartySystem.is_member(character_id):
			continue
		var spawn_data: Dictionary = _character_spawn_data_by_id[character_id] as Dictionary
		var definition: Dictionary = _character_definition_by_id[character_id] as Dictionary
		if _is_player_spawn(spawn_data, definition):
			continue

		var active_entry: Dictionary = _get_active_schedule_entry(definition, spawn_data)
		if active_entry.is_empty():
			continue
		var character: CharacterEntity = grid.get_character_by_id(character_id)
		if not _schedule_entry_matches_location_context(active_entry):
			if character != null:
				_remove_scheduled_character(character, active_entry, result)
				change_count += 1
			continue

		var scheduled_location_id: String = str(active_entry.get("location_id", grid.location_id))
		if character != null and _npc_autonomy_agent != null and _npc_autonomy_agent.has_active_interruption(character_id):
			continue
		if scheduled_location_id != grid.location_id:
			if character != null:
				if _schedule_entry_starts_from_current_location(active_entry):
					if _apply_schedule_entry_to_character(character, active_entry, scheduled_location_id, result):
						NpcScheduleSystem.schedule_applied.emit(character.character_id, grid.location_id, character.current_schedule_entry_id)
						change_count += 1
				else:
					_remove_scheduled_character(character, active_entry, result)
					change_count += 1
			elif _try_spawn_cross_scene_traveler(spawn_data, definition, active_entry, absolute_minutes, result):
				NpcScheduleSystem.schedule_applied.emit(character_id, grid.location_id, str(active_entry.get("id", "")))
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
	if spawn_data.has("source"):
		resolved_spawn_data["source"] = str(spawn_data.get("source", ""))
	if bool(resolved_spawn_data.get("spawn_at_entrance", false)):
		_apply_entrance_to_spawn_data(resolved_spawn_data)

	if not resolved_spawn_data.has("id"):
		resolved_spawn_data["id"] = str(definition.get("id", ""))

	return resolved_spawn_data


func _spawn_character(definition: Dictionary, resolved_spawn_data: Dictionary) -> CharacterEntity:
	var character: CharacterEntity = CharacterEntity.new()
	character.z_index = 0
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
		if entrance_id.is_empty() and not runtime_state.is_empty():
			character.apply_runtime_state(runtime_state)
		controlled_character = character
		current_grid_position = character.grid_position
		_update_building_renderer_focus()
		GameState.player_id = character.character_id
		if not character.grid_position_changed.is_connected(_on_controlled_character_grid_position_changed):
			character.grid_position_changed.connect(_on_controlled_character_grid_position_changed)
		if not character.facing_changed.is_connected(_on_controlled_character_facing_changed):
			character.facing_changed.connect(_on_controlled_character_facing_changed)

	return character


func _sync_party_followers(force_reposition: bool = true) -> void:
	if grid == null or not _has_controlled_character():
		return

	_release_removed_party_followers()
	_party_follower_ids.clear()
	for member_id in PartySystem.get_companion_ids():
		var follower: CharacterEntity = grid.get_character_by_id(member_id)
		if follower == null:
			follower = _spawn_party_follower(member_id)
		if follower == null:
			continue
		_prepare_party_follower(follower)
		_party_follower_ids.append(member_id)
		PartySystem.refresh_member(follower)

	if force_reposition:
		_reposition_party_followers(true)


func _release_removed_party_followers() -> void:
	if grid == null:
		return

	for follower_id in _party_follower_ids:
		if PartySystem.is_member(follower_id):
			continue
		var follower: CharacterEntity = grid.get_character_by_id(follower_id)
		if follower == null:
			continue
		follower.character_kind = CharacterEntity.KIND_NPC
		follower.is_interactable = true
		follower.is_combatable = false
		PartySystem.refresh_member(follower)
		GameState.save_character_runtime(follower)


func _spawn_party_follower(member_id: String) -> CharacterEntity:
	var source_path: String = PartySystem.get_member_source(member_id)
	if source_path.is_empty():
		var summary: Dictionary = PartySystem.get_member_summary(member_id)
		source_path = str(summary.get("definition_source", ""))
	if source_path.is_empty():
		return null

	var definition: Dictionary = _read_json_resource(source_path)
	if definition.is_empty():
		return null

	var spawn_cell: Vector2i = _find_party_spawn_cell(member_id)
	if spawn_cell.x < 0 or spawn_cell.y < 0:
		return null
	var spawn_data: Dictionary = {
		"id": member_id,
		"source": source_path,
		"grid_position": { "x": spawn_cell.x, "y": spawn_cell.y },
		"facing": controlled_character.facing,
		"character_kind": CharacterEntity.KIND_COMPANION,
		"is_player_controlled": false,
		"is_interactable": false,
		"is_combatable": true,
	}
	var runtime_state: Dictionary = GameState.get_character_runtime(member_id)
	if runtime_state.has("attributes"):
		spawn_data["attributes"] = (runtime_state.get("attributes", {}) as Dictionary).duplicate(true)

	var character: CharacterEntity = _spawn_character(definition, spawn_data)
	if character != null and not runtime_state.is_empty():
		character.apply_runtime_state(runtime_state)
	return character


func _prepare_party_follower(character: CharacterEntity) -> void:
	character.character_kind = CharacterEntity.KIND_COMPANION
	character.is_player_controlled = false
	character.is_interactable = false
	character.is_combatable = true
	character.blocks_movement = true
	character.set_facing(controlled_character.facing)
	GameState.save_character_runtime(character)


func _find_party_spawn_cell(member_id: String) -> Vector2i:
	var preferred_cell: Vector2i = controlled_character.grid_position + PartySystem.get_formation_offset(member_id, controlled_character.facing)
	var fallback_cells: Array[Vector2i] = _get_party_candidate_cells(preferred_cell)
	for cell in fallback_cells:
		if grid.can_enter(cell):
			return cell
	for radius in range(1, 4):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var cell: Vector2i = controlled_character.grid_position + Vector2i(x, y)
				if grid.can_enter(cell):
					return cell
	return Vector2i(-1, -1)


func _get_active_schedule_entry(definition: Dictionary, spawn_data: Dictionary) -> Dictionary:
	return _get_active_schedule_entry_at(definition, spawn_data, TimeManager.get_absolute_minutes())


func _get_active_schedule_entry_at(definition: Dictionary, spawn_data: Dictionary, absolute_minutes: int) -> Dictionary:
	var schedule_rows: Array = _get_schedule_rows(definition, spawn_data)
	if schedule_rows.is_empty():
		return {}

	return NpcScheduleSystem.get_active_entry(schedule_rows, absolute_minutes)


func _get_schedule_rows(definition: Dictionary, spawn_data: Dictionary) -> Array:
	return spawn_data.get("schedule", definition.get("schedule", [])) as Array


func _schedule_entry_matches_location_context(entry: Dictionary) -> bool:
	if grid == null:
		return true
	var scheduled_location_id := str(entry.get("location_id", grid.location_id))
	return scheduled_location_id == grid.location_id or _schedule_entry_starts_from_current_location(entry)


func _schedule_entry_starts_from_current_location(entry: Dictionary) -> bool:
	return not _get_transition_anchor_for_current_location(entry).is_empty()


func _apply_schedule_entry_to_spawn_data(spawn_data: Dictionary, entry: Dictionary, scheduled_location_id: String) -> void:
	var target: Dictionary = _resolve_schedule_target(entry)
	if target.has("grid_position"):
		spawn_data["grid_position"] = (target.get("grid_position", {}) as Dictionary).duplicate(true)
	if target.has("facing"):
		spawn_data["facing"] = str(target.get("facing", "down"))

	spawn_data["schedule_entry_id"] = str(entry.get("id", ""))
	spawn_data["anchor_id"] = str(entry.get("anchor_id", ""))
	spawn_data["activity_type"] = str(entry.get("activity_type", "idle"))
	spawn_data["activity"] = str(entry.get("activity", "idle"))
	spawn_data["movement"] = str(entry.get("movement", "walk"))
	spawn_data["scheduled_location_id"] = scheduled_location_id


func _apply_matching_offscreen_state_to_spawn_data(spawn_data: Dictionary, offscreen_state: Dictionary, active_entry: Dictionary) -> void:
	if offscreen_state.is_empty():
		return
	if str(offscreen_state.get("entry_id", "")) != str(active_entry.get("id", "")):
		return

	_apply_offscreen_state_to_spawn_data(spawn_data, offscreen_state)


func _apply_offscreen_state_to_spawn_data(spawn_data: Dictionary, offscreen_state: Dictionary) -> void:
	if offscreen_state.has("grid_position"):
		spawn_data["grid_position"] = (offscreen_state.get("grid_position", {}) as Dictionary).duplicate(true)
	if offscreen_state.has("facing"):
		spawn_data["facing"] = str(offscreen_state.get("facing", "down"))

	spawn_data["schedule_entry_id"] = str(offscreen_state.get("entry_id", spawn_data.get("schedule_entry_id", "")))
	spawn_data["anchor_id"] = str(offscreen_state.get("anchor_id", spawn_data.get("anchor_id", "")))
	spawn_data["activity_type"] = str(offscreen_state.get("activity_type", spawn_data.get("activity_type", "idle")))
	spawn_data["activity"] = str(offscreen_state.get("activity", spawn_data.get("activity", "idle")))
	spawn_data["movement"] = str(offscreen_state.get("movement", spawn_data.get("movement", "walk")))
	spawn_data["scheduled_location_id"] = str(offscreen_state.get("location_id", grid.location_id))


func _try_spawn_cross_scene_traveler(
	spawn_data: Dictionary,
	definition: Dictionary,
	active_entry: Dictionary,
	absolute_minutes: int,
	result: ActionResult
) -> bool:
	if grid == null or _npc_movement_agent == null:
		return false

	var target_anchor_id := _get_transition_anchor_for_current_location(active_entry)
	if target_anchor_id.is_empty():
		return false
	if _minutes_since_entry_start(active_entry, absolute_minutes) > 1:
		return false

	var previous_entry := _get_entry_before_active_start(definition, spawn_data, active_entry, absolute_minutes)
	if previous_entry.is_empty() or str(previous_entry.get("id", "")) == str(active_entry.get("id", "")):
		return false

	var source_anchor_id := _get_transition_anchor_for_current_location(previous_entry)
	if source_anchor_id.is_empty() or source_anchor_id == target_anchor_id:
		return false

	var source_anchor: Dictionary = grid.get_anchor(source_anchor_id)
	var target_anchor: Dictionary = grid.get_anchor(target_anchor_id)
	if source_anchor.is_empty() or target_anchor.is_empty():
		return false

	var source_cell := _cell_from_dict(source_anchor.get("grid_position", {}) as Dictionary)
	var target_cell := _cell_from_dict(target_anchor.get("grid_position", {}) as Dictionary)
	var spawn_cell := _find_cross_scene_spawn_cell(source_cell, target_cell)
	if spawn_cell.x < 0 or spawn_cell.y < 0:
		return false

	var resolved_spawn_data: Dictionary = _build_spawn_data(spawn_data, definition)
	resolved_spawn_data["grid_position"] = _dict_from_cell(spawn_cell)
	resolved_spawn_data["facing"] = str(source_anchor.get("facing", resolved_spawn_data.get("facing", "down")))
	resolved_spawn_data["schedule_entry_id"] = str(active_entry.get("id", ""))
	resolved_spawn_data["anchor_id"] = str(active_entry.get("anchor_id", ""))
	resolved_spawn_data["activity_type"] = str(active_entry.get("activity_type", "idle"))
	resolved_spawn_data["activity"] = str(active_entry.get("activity", "idle"))
	resolved_spawn_data["movement"] = str(active_entry.get("movement", "walk"))
	resolved_spawn_data["scheduled_location_id"] = str(active_entry.get("location_id", grid.location_id))

	var character := _spawn_character(definition, resolved_spawn_data)
	if character == null:
		return false

	var movement_entry: Dictionary = active_entry.duplicate(true)
	movement_entry["facing"] = str(target_anchor.get("facing", active_entry.get("facing", character.facing)))
	var movement_request: Dictionary = _request_scheduled_character_movement(
		character,
		movement_entry,
		str(active_entry.get("location_id", grid.location_id)),
		target_cell
	)
	var movement_state := str(movement_request.get("state", ""))
	if movement_state == "started":
		result.add_world_change({
			"type": "scheduled_character_cross_scene_segment_started",
			"character_id": character.character_id,
			"location_id": grid.location_id,
			"entry_id": str(active_entry.get("id", "")),
			"from_anchor_id": source_anchor_id,
			"to_anchor_id": target_anchor_id,
			"from": spawn_cell,
			"target": target_cell,
			"to_location_id": str(active_entry.get("location_id", "")),
		})
		result.add_feedback("%s left %s for %s." % [
			character.display_name,
			str(previous_entry.get("activity", "the previous stop")),
			str(active_entry.get("activity", "the next stop")),
		])
		return true

	if movement_state == "arrived":
		_depart_scheduled_character_after_cross_scene_arrival(character.character_id, result)
		return true

	result.add_world_change({
		"type": "scheduled_character_blocked",
		"character_id": character.character_id,
		"location_id": grid.location_id,
		"entry_id": str(active_entry.get("id", "")),
		"target": target_cell,
		"reason": str(movement_request.get("reason", "cross_scene_segment_blocked")),
	})
	result.add_feedback("%s could not leave for %s." % [character.display_name, str(active_entry.get("activity", "schedule"))])
	return true


func _get_entry_before_active_start(definition: Dictionary, spawn_data: Dictionary, active_entry: Dictionary, absolute_minutes: int) -> Dictionary:
	var schedule_rows: Array = _get_schedule_rows(definition, spawn_data)
	if schedule_rows.is_empty():
		return {}

	var elapsed_since_start: int = _minutes_since_entry_start(active_entry, absolute_minutes)
	if elapsed_since_start < 0:
		return NpcScheduleSystem.get_active_entry(schedule_rows, maxi(0, absolute_minutes - 1))

	var previous_absolute_minute: int = maxi(0, absolute_minutes - elapsed_since_start - 1)
	return NpcScheduleSystem.get_active_entry(schedule_rows, previous_absolute_minute)


func _minutes_since_entry_start(entry: Dictionary, absolute_minutes: int) -> int:
	var start_minute: int = TimeManager.parse_time_to_minute(str(entry.get("start", "")))
	if start_minute < 0:
		return -1
	var current_minute: int = absolute_minutes % TimeManager.MINUTES_PER_DAY
	return (current_minute - start_minute + TimeManager.MINUTES_PER_DAY) % TimeManager.MINUTES_PER_DAY


func _find_cross_scene_spawn_cell(source_cell: Vector2i, target_cell: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = [
		source_cell,
		source_cell + Vector2i.LEFT,
		source_cell + Vector2i.RIGHT,
		source_cell + Vector2i.DOWN,
		source_cell + Vector2i.UP,
		source_cell + Vector2i(-1, 1),
		source_cell + Vector2i(1, 1),
		source_cell + Vector2i(-1, -1),
		source_cell + Vector2i(1, -1),
	]
	var best_cell := Vector2i(-1, -1)
	var best_distance := INF
	for candidate in candidates:
		if not grid.can_enter(candidate):
			continue
		var distance := candidate.distance_squared_to(target_cell)
		if distance < best_distance:
			best_distance = distance
			best_cell = candidate
	return best_cell


func _apply_schedule_entry_to_character(character: CharacterEntity, entry: Dictionary, scheduled_location_id: String, result: ActionResult) -> bool:
	var entry_id: String = str(entry.get("id", ""))
	var next_activity_type: String = str(entry.get("activity_type", character.current_activity_type))
	var next_activity: String = str(entry.get("activity", character.current_activity))
	var next_facing: String = str(entry.get("facing", character.facing))
	var entry_changed: bool = character.current_schedule_entry_id != entry_id
	var activity_type_changed: bool = character.current_activity_type != next_activity_type
	var activity_changed: bool = character.current_activity != next_activity
	var facing_changed: bool = character.facing != next_facing
	var changed: bool = false
	var movement_active: bool = false

	var schedule_target: Dictionary = _resolve_schedule_target(entry)
	if schedule_target.has("grid_position"):
		var target_position: Dictionary = schedule_target.get("grid_position", {}) as Dictionary
		var target_cell: Vector2i = _cell_from_dict(target_position)
		if schedule_target.has("facing"):
			next_facing = str(schedule_target.get("facing", next_facing))
			facing_changed = character.facing != next_facing
		movement_active = _npc_movement_agent != null and _npc_movement_agent.has_active_intent(character.character_id, entry_id, target_cell)
		if character.grid_position != target_cell and (entry_changed or activity_type_changed or activity_changed) and not movement_active:
			var movement_entry: Dictionary = entry.duplicate(true)
			movement_entry["facing"] = next_facing
			var movement_request: Dictionary = _request_scheduled_character_movement(character, movement_entry, scheduled_location_id, target_cell)
			var movement_state: String = str(movement_request.get("state", ""))
			if movement_state == "started":
				result.add_world_change({
					"type": "scheduled_character_movement_started",
					"character_id": character.character_id,
					"location_id": grid.location_id,
					"entry_id": entry_id,
					"from": character.grid_position,
					"target": target_cell,
					"activity_type": str(entry.get("activity_type", "idle")),
					"activity": next_activity,
				})
				result.add_feedback("%s started walking to %s." % [character.display_name, next_activity])
				changed = true
				movement_active = true
			elif movement_state == "arrived":
				changed = true
			elif movement_state == "blocked":
				result.add_world_change({
					"type": "scheduled_character_blocked",
					"character_id": character.character_id,
					"location_id": grid.location_id,
					"entry_id": entry_id,
					"target": target_cell,
					"reason": str(movement_request.get("reason", "")),
				})
				result.add_feedback("%s could not reach scheduled activity %s." % [character.display_name, next_activity])
				changed = true

	if facing_changed and not movement_active:
		character.set_facing(next_facing)
		changed = true

	if entry_changed or activity_type_changed or activity_changed or changed:
		character.set_schedule_state(entry, scheduled_location_id)
		result.add_world_change({
			"type": "scheduled_character_state_changed",
			"character_id": character.character_id,
			"location_id": grid.location_id,
			"entry_id": character.current_schedule_entry_id,
			"anchor_id": character.current_schedule_anchor_id,
			"activity_type": character.current_activity_type,
			"activity": character.current_activity,
			"movement": character.current_movement_mode,
			"grid_position": character.grid_position,
			"facing": character.facing,
		})
		result.add_feedback("%s is now %s." % [character.display_name, character.current_activity])
		return true

	return false


func _resolve_schedule_target(entry: Dictionary) -> Dictionary:
	var target: Dictionary = {}
	var anchor_id: String = str(entry.get("anchor_id", ""))
	if str(entry.get("location_id", grid.location_id)) != grid.location_id:
		anchor_id = _get_transition_anchor_for_current_location(entry)
	if not anchor_id.is_empty() and grid != null:
		var anchor: Dictionary = grid.get_anchor(anchor_id)
		if not anchor.is_empty():
			var anchor_position: Dictionary = anchor.get("grid_position", {}) as Dictionary
			if not anchor_position.is_empty():
				target["grid_position"] = anchor_position.duplicate(true)
			if anchor.has("facing"):
				target["facing"] = str(anchor.get("facing", "down"))

	if not target.has("grid_position") and entry.has("grid_position"):
		target["grid_position"] = (entry.get("grid_position", {}) as Dictionary).duplicate(true)

	if entry.has("facing"):
		target["facing"] = str(entry.get("facing", "down"))

	return target


func _get_transition_anchor_for_current_location(entry: Dictionary) -> String:
	if grid == null:
		return ""

	var anchors_by_location: Dictionary = entry.get("transition_anchor_by_location", {}) as Dictionary
	return str(anchors_by_location.get(grid.location_id, ""))


func _request_scheduled_character_movement(character: CharacterEntity, entry: Dictionary, scheduled_location_id: String, target_cell: Vector2i) -> Dictionary:
	if _npc_movement_agent == null:
		return {
			"state": "blocked",
			"reason": "missing_movement_agent",
		}

	return _npc_movement_agent.request_schedule_movement(character, entry, scheduled_location_id, target_cell)


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
	if _npc_movement_agent != null:
		_npc_movement_agent.cancel_movement(character.character_id)
	if _npc_activity_agent != null:
		_npc_activity_agent.cancel_character(character.character_id)
	if _npc_autonomy_agent != null:
		_npc_autonomy_agent.cancel_character(character.character_id)
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
		if not BattleSystem.is_move_mode():
			ActionSystem.publish_result(ActionResult.failed("BattleMove", GameState.player_id, "请先选择移动。"))
			_refresh_battle_overlay()
			return
		BattleSystem.request_move_current_unit(direction)
		_refresh_battle_overlay()
		return

	if GameState.current_mode != GameState.GameMode.EXPLORATION:
		return

	if grid == null or not _has_controlled_character():
		return

	if _try_swap_with_party_follower(direction):
		_recenter_camera_to_focus(false)
		_refresh_interaction_overlay()
		return

	var target: Dictionary = { "direction": direction }
	var context: Dictionary = { "location_root": self }
	var action: GameAction = ActionSystem.create_action("MoveAction", controlled_character, target, context) as GameAction
	var result: ActionResult = ActionSystem.submit(action) as ActionResult
	if _has_controlled_character() and not _result_has_change_type(result, "location_exit_requested"):
		_recenter_camera_to_focus(false)
	_refresh_interaction_overlay()
	if result.success and _result_has_change_type(result, "character_moved") and not _result_has_change_type(result, "location_exit_requested") and _has_controlled_character():
		current_grid_position = controlled_character.grid_position
		_step_party_followers_after_player_move(result)


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
	_refresh_interaction_overlay()
	return true


func _reposition_party_followers(force_place: bool = false) -> void:
	if grid == null or not _has_controlled_character():
		return
	if GameState.current_mode == GameState.GameMode.COMBAT:
		return

	var occupied_targets: Dictionary = {}
	for member_id in PartySystem.get_companion_ids():
		var follower: CharacterEntity = grid.get_character_by_id(member_id)
		if follower == null:
			continue

		var preferred_cell: Vector2i = controlled_character.grid_position + PartySystem.get_formation_offset(member_id, controlled_character.facing)
		var target_cell: Vector2i = _find_available_follow_cell(preferred_cell, follower, occupied_targets)
		occupied_targets[grid.cell_key(target_cell)] = true
		_move_party_follower_to(follower, target_cell, force_place)


func _step_party_followers_after_player_move(move_result: ActionResult) -> void:
	if grid == null or not _has_controlled_character():
		return
	if GameState.current_mode == GameState.GameMode.COMBAT:
		return

	var player_move: Dictionary = _get_world_change(move_result, "character_moved", controlled_character.character_id)
	if player_move.is_empty():
		return

	var next_target: Vector2i = player_move.get("from", controlled_character.grid_position) as Vector2i
	var reserved_cells: Dictionary = {}
	reserved_cells[grid.cell_key(controlled_character.grid_position)] = true

	for member_id in PartySystem.get_companion_ids():
		var follower: CharacterEntity = grid.get_character_by_id(member_id)
		if follower == null:
			continue

		var follower_from: Vector2i = follower.grid_position
		if not reserved_cells.has(grid.cell_key(next_target)):
			_move_party_follower_to(follower, next_target, false, true)
		reserved_cells[grid.cell_key(follower.grid_position)] = true
		next_target = follower_from


func _find_available_follow_cell(preferred_cell: Vector2i, follower: CharacterEntity, occupied_targets: Dictionary) -> Vector2i:
	var candidates: Array[Vector2i] = _get_party_candidate_cells(preferred_cell)
	for cell in candidates:
		if occupied_targets.has(grid.cell_key(cell)):
			continue
		if cell == follower.grid_position:
			return cell
		if grid.can_enter(cell):
			return cell
	return follower.grid_position


func _get_party_candidate_cells(preferred_cell: Vector2i) -> Array[Vector2i]:
	return [
		preferred_cell,
		preferred_cell + Vector2i.LEFT,
		preferred_cell + Vector2i.RIGHT,
		preferred_cell + Vector2i.UP,
		preferred_cell + Vector2i.DOWN,
		preferred_cell + Vector2i(-1, 1),
		preferred_cell + Vector2i(1, 1),
		preferred_cell + Vector2i(-1, -1),
		preferred_cell + Vector2i(1, -1),
	]


func _move_party_follower_to(follower: CharacterEntity, target_cell: Vector2i, force_place: bool, allow_party_target: bool = false) -> bool:
	if follower == null or not is_instance_valid(follower):
		return false
	if follower.grid_position == target_cell:
		follower.set_facing(controlled_character.facing)
		return true

	var from_cell: Vector2i = follower.grid_position
	if force_place:
		grid.unregister_character(follower.character_id)
		if not grid.register_character(follower.character_id, target_cell, follower, follower.blocks_movement):
			grid.register_character(follower.character_id, from_cell, follower, follower.blocks_movement)
			return false
	else:
		if not _can_party_follower_enter_cell(target_cell, follower, allow_party_target):
			return false
		if not grid.move_character(follower.character_id, from_cell, target_cell, follower.blocks_movement):
			return false

	follower.set_grid_position(target_cell)
	follower.face_direction(target_cell - from_cell)
	PartySystem.refresh_member(follower)
	GameState.save_character_runtime(follower)
	return true


func _try_swap_with_party_follower(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO or grid == null or not _has_controlled_character():
		return false

	var player_from: Vector2i = controlled_character.grid_position
	var target_cell: Vector2i = player_from + direction
	var follower: CharacterEntity = grid.get_character_at(target_cell)
	if follower == null or not PartySystem.is_member(follower.character_id) or follower.character_id == controlled_character.character_id:
		return false

	controlled_character.face_direction(direction)
	var follower_from: Vector2i = follower.grid_position
	grid.unregister_character(controlled_character.character_id)
	grid.unregister_character(follower.character_id)
	var player_registered: bool = grid.register_character(controlled_character.character_id, follower_from, controlled_character, controlled_character.blocks_movement)
	var follower_registered: bool = grid.register_character(follower.character_id, player_from, follower, follower.blocks_movement)
	if not player_registered or not follower_registered:
		grid.unregister_character(controlled_character.character_id)
		grid.unregister_character(follower.character_id)
		grid.register_character(controlled_character.character_id, player_from, controlled_character, controlled_character.blocks_movement)
		grid.register_character(follower.character_id, follower_from, follower, follower.blocks_movement)
		return false

	controlled_character.set_grid_position(follower_from)
	follower.set_grid_position(player_from)
	follower.set_facing(controlled_character.facing)
	current_grid_position = controlled_character.grid_position
	PartySystem.refresh_member(follower)
	GameState.save_character_runtime(controlled_character)
	GameState.save_character_runtime(follower)

	var result: ActionResult = ActionResult.succeeded("PartySwap", controlled_character.character_id, {
		"direction": direction,
		"follower_id": follower.character_id,
	})
	result.add_world_change({
		"type": "party_member_swapped",
		"leader_id": controlled_character.character_id,
		"member_id": follower.character_id,
		"leader_from": player_from,
		"leader_to": follower_from,
		"member_from": follower_from,
		"member_to": player_from,
		"location_id": grid.location_id,
	})
	result.add_feedback("%s 与 %s 交换了位置。" % [controlled_character.display_name, follower.display_name])
	ActionSystem.publish_result(result)
	return true


func _can_party_follower_enter_cell(target_cell: Vector2i, follower: CharacterEntity, allow_party_target: bool) -> bool:
	if grid == null or not grid.is_walkable(target_cell):
		return false
	if grid.can_enter(target_cell):
		return true
	if not allow_party_target:
		return false

	var occupant: CharacterEntity = grid.get_character_at(target_cell)
	if occupant == null or occupant == follower:
		return false
	return PartySystem.is_member(occupant.character_id)


func _on_primary_action_requested() -> void:
	if GameState.current_mode == GameState.GameMode.COMBAT:
		_refresh_interaction_overlay()
		BattleSystem.request_attack_current_unit()
		_refresh_battle_overlay()
		return

	if GameState.current_mode != GameState.GameMode.EXPLORATION:
		return

	if not _has_controlled_character() or grid == null:
		return

	var target_cell: Vector2i = controlled_character.get_facing_cell()
	var target_character: CharacterEntity = grid.get_character_at(target_cell)
	if target_character != null and PartySystem.is_member(target_character.character_id):
		target_character = null
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

	if _try_submit_current_cell_transition(controlled_character.grid_position):
		return

	var target_object: LocationObject = grid.get_primary_object_at(target_cell)
	if target_object == null:
		_submit_inspect_empty(target_cell)
		return

	_submit_object_interaction(target_object, target_cell)


func _on_rest_requested() -> void:
	if GameState.current_mode == GameState.GameMode.COMBAT:
		_refresh_interaction_overlay()
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
	_refresh_interaction_overlay()


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
		_refresh_interaction_overlay()
		return true

	if is_cell_plantable(cell) and not CropSystem.get_seed_item_id(controlled_character).is_empty():
		_submit_crop_action("PlantAction", cell)
		return true

	return false


func _get_crop_interaction_prompt(cell: Vector2i) -> String:
	var crop_state: Dictionary = CropSystem.get_crop_at(grid.location_id, cell)
	if not crop_state.is_empty():
		if bool(crop_state.get("mature", false)):
			return "E/Enter 收获：%s" % str(crop_state.get("display_name", "作物"))
		if not bool(crop_state.get("watered", false)):
			return "E/Enter 浇水：%s" % str(crop_state.get("display_name", "作物"))
		return "作物正在生长：%s" % str(crop_state.get("display_name", "作物"))

	if is_cell_plantable(cell) and not CropSystem.get_seed_item_id(controlled_character).is_empty():
		return "E/Enter 种植种子"

	return ""


func _get_current_cell_transition_prompt(cell: Vector2i) -> String:
	if grid == null:
		return ""
	var current_object: LocationObject = grid.get_primary_object_at(cell)
	if current_object != null and current_object.is_scene_transition():
		return "E/Enter Leave: %s" % current_object.display_name
	var exit_data: Dictionary = grid.get_exit_at(cell)
	if not exit_data.is_empty():
		return "E/Enter Leave: %s" % str(exit_data.get("target_entrance_id", "next location"))
	return ""


func _try_submit_current_cell_transition(cell: Vector2i) -> bool:
	if grid == null:
		return false
	var current_object: LocationObject = grid.get_primary_object_at(cell)
	if current_object != null and current_object.is_scene_transition():
		_submit_scene_transition_object(current_object)
		return true
	var exit_data: Dictionary = grid.get_exit_at(cell)
	if not exit_data.is_empty():
		request_exit_transition(exit_data)
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
	_refresh_interaction_overlay()


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
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if BattleSystem.get_tactical_mode() == BattleSystem.TACTICAL_MODE_SKILL:
			get_viewport().set_input_as_handled()
			BattleSystem.cancel_skill_targeting_to_skill_menu()
			_update_battle_hover(Vector2i(-9999, -9999), "", [])
			_refresh_battle_overlay()
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var clicked_cell: Vector2i = _mouse_to_grid_cell()
	if not grid.in_bounds(clicked_cell):
		return

	get_viewport().set_input_as_handled()
	_submit_battle_click(clicked_cell)


func _submit_battle_click(clicked_cell: Vector2i) -> void:
	var preview: Dictionary = BattleSystem.get_player_tactical_preview()
	var tactical_mode: String = str(preview.get("tactical_mode", "command"))
	if tactical_mode == BattleSystem.TACTICAL_MODE_MOVE:
		var mode_move_cells: Array = preview.get("move_cells", []) as Array
		if _cell_array_has(mode_move_cells, clicked_cell):
			BattleSystem.request_move_current_unit_to(clicked_cell)
			_refresh_battle_overlay()
			return
		ActionSystem.publish_result(ActionResult.failed("BattleSelect", GameState.player_id, "请选择蓝色移动格。"))
		return

	if tactical_mode == BattleSystem.TACTICAL_MODE_SKILL:
		var mode_attack_cells: Array = preview.get("attack_cells", []) as Array
		if _cell_array_has(mode_attack_cells, clicked_cell):
			BattleSystem.request_use_skill_current_unit(BattleSystem.get_selected_skill_id(), clicked_cell)
			_refresh_battle_overlay()
			return
		ActionSystem.publish_result(ActionResult.failed("BattleSelect", GameState.player_id, "请选择技能范围内的目标格。"))
		return

	ActionSystem.publish_result(ActionResult.failed("BattleSelect", GameState.player_id, "请先选择移动或技能。"))
	return

	ActionSystem.publish_result(ActionResult.failed("BattleSelect", GameState.player_id, "请选择高亮的移动格，或选择可攻击的目标。"))


func _update_battle_hover_from_mouse() -> void:
	var hover_grid_cell: Vector2i = _mouse_to_grid_cell()
	if not grid.in_bounds(hover_grid_cell):
		_update_battle_hover(Vector2i(-9999, -9999), "", [])
		return

	var preview: Dictionary = BattleSystem.get_player_tactical_preview()
	var tactical_mode: String = str(preview.get("tactical_mode", "command"))
	if tactical_mode == BattleSystem.TACTICAL_MODE_SKILL:
		var mode_attack_cells: Array = preview.get("attack_cells", []) as Array
		if _cell_array_has(mode_attack_cells, hover_grid_cell):
			_update_battle_hover(hover_grid_cell, "attack", BattleSystem.get_area_cells_for_current_skill(hover_grid_cell))
			return

	if tactical_mode == BattleSystem.TACTICAL_MODE_MOVE:
		var mode_move_cells: Array = preview.get("move_cells", []) as Array
		if _cell_array_has(mode_move_cells, hover_grid_cell):
			_update_battle_hover(hover_grid_cell, "move", [])
			return

	_update_battle_hover(Vector2i(-9999, -9999), "", [])
	return


func _update_battle_hover(cell: Vector2i, kind: String, area_cells: Array = []) -> void:
	if battle_overlay == null or not is_instance_valid(battle_overlay):
		return

	battle_overlay.set_hover_cell(cell, kind, area_cells)


func _refresh_battle_overlay() -> void:
	if battle_overlay == null or not is_instance_valid(battle_overlay):
		return

	if not BattleSystem.is_active():
		battle_overlay.clear_preview()
		_clear_battle_character_presentations()
		_refresh_interaction_overlay()
		return

	battle_overlay.set_preview(BattleSystem.get_player_tactical_preview())
	_refresh_battle_character_presentations()
	if not _camera_detached:
		_recenter_camera_to_focus(false)
	_refresh_interaction_overlay()


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
	if target_object.is_scene_transition():
		_submit_scene_transition_object(target_object)
		return

	if target_object.is_facility():
		match target_object.facility_type:
			"crafting", "shop":
				facility_requested.emit(target_object.get_facility_data())
			"rest":
				_submit_rest_facility(target_object)
			"save":
				_submit_save_facility(target_object)
			_:
				facility_requested.emit(target_object.get_facility_data())
		_refresh_interaction_overlay()
		return

	var target: Dictionary = {
		"object": target_object,
		"target_cell": target_cell,
	}
	var context: Dictionary = { "location_root": self }
	var action_type: String = _choose_interaction_action(target_object)
	var action: GameAction = ActionSystem.create_action(action_type, controlled_character, target, context) as GameAction
	ActionSystem.submit(action)
	_refresh_interaction_overlay()


func _submit_scene_transition_object(target_object: LocationObject) -> void:
	var transition_data: Dictionary = target_object.get_transition_data()
	var target_scene_path := str(transition_data.get("target_scene_path", ""))
	var target_entrance_id := str(transition_data.get("target_entrance_id", ""))
	if target_scene_path == "__return__":
		SceneLoader.load_pending_return_location()
		return
	if target_scene_path.is_empty():
		return

	var return_entrance_id := str(transition_data.get("return_entrance_id", ""))
	if not return_entrance_id.is_empty():
		SceneLoader.set_pending_return_location(SceneLoader.current_scene_path, return_entrance_id)

	var context: Dictionary = transition_data.get("context", {}) as Dictionary
	if not context.is_empty():
		SceneLoader.set_pending_location_context(context)
	SceneLoader.load_location(target_scene_path, target_entrance_id)


func _submit_talk_interaction(target_character: CharacterEntity) -> void:
	var target: Dictionary = { "speaker": target_character }
	var context: Dictionary = { "location_root": self }
	var action: GameAction = ActionSystem.create_action("TalkAction", controlled_character, target, context) as GameAction
	ActionSystem.submit(action)
	_refresh_interaction_overlay()


func _submit_battle_start(target_character: CharacterEntity) -> void:
	BattleSystem.start_battle(self, controlled_character, target_character)
	if target_character != null:
		_focus_camera_on_world_position_if_needed(target_character.position, true)
	_refresh_interaction_overlay()


func _submit_inspect_empty(target_cell: Vector2i) -> void:
	var target: Dictionary = {
		"target_cell": target_cell,
		"empty": true,
	}
	var context: Dictionary = { "location_root": self }
	var action: GameAction = ActionSystem.create_action("InspectAction", controlled_character, target, context) as GameAction
	ActionSystem.submit(action)
	_refresh_interaction_overlay()


func _choose_interaction_action(target_object: LocationObject) -> String:
	if target_object.is_pickable:
		return "PickUpAction"
	if target_object.is_usable:
		return "UseItemAction"
	return "InspectAction"


func _get_rest_facility_prompt(target_object: LocationObject) -> String:
	match target_object.rest_type:
		"bed":
			return "E/Enter 休息到明早：%s" % target_object.display_name
		"campfire":
			return "E/Enter 烤火休息：%s" % target_object.display_name
		"inn":
			return "E/Enter 入住：%s（%d 金币）" % [target_object.display_name, target_object.cost]
		_:
			return "E/Enter 休息：%s" % target_object.display_name


func _submit_rest_facility(target_object: LocationObject) -> void:
	var target: Dictionary = target_object.get_facility_data()
	target["target_scope"] = "party"
	var context: Dictionary = { "location_root": self }
	var action: GameAction = ActionSystem.create_action("RestAction", controlled_character, target, context) as GameAction
	ActionSystem.submit(action)


func _submit_save_facility(_target_object: LocationObject) -> void:
	SaveManager.save_game()


func _read_location_data() -> Dictionary:
	return DefinitionLoader.load_resolved_location(location_data_path, SceneLoader.consume_pending_location_context())


func _read_json_resource(resource_path: String) -> Dictionary:
	return DefinitionLoader.load_json_resource(resource_path)


func _on_crop_changed(location_id: String, _cell: Vector2i, _crop_state: Dictionary) -> void:
	if grid == null or location_id != grid.location_id:
		return

	refresh_crop_markers()
	_refresh_interaction_overlay()


func _on_party_changed() -> void:
	if GameState.current_mode == GameState.GameMode.COMBAT:
		return
	_sync_party_followers(false)
	_refresh_interaction_overlay()


func _on_action_result_for_presentation(_action_type: String, _actor_id: String, result: ActionResult) -> void:
	if result == null:
		return

	_refresh_battle_character_presentations()
	if result.success:
		_focus_camera_from_action_result(result)
		_spawn_battle_feedback_from_result(result)
		return

	if GameState.current_mode == GameState.GameMode.COMBAT and _has_controlled_character():
		_spawn_battle_feedback(controlled_character.character_id, "无效", Color(0.92, 0.92, 0.92, 0.95))


func _focus_camera_from_action_result(result: ActionResult) -> void:
	if result == null or GameState.current_mode != GameState.GameMode.COMBAT:
		return

	var focus_cell: Vector2i = Vector2i(-9999, -9999)
	if result.target.has("target_cell"):
		focus_cell = _variant_to_cell(result.target.get("target_cell"))

	for change in result.world_changes:
		var change_type: String = str(change.get("type", ""))
		match change_type:
			"battle_unit_moved":
				focus_cell = _variant_to_cell(change.get("to", focus_cell))
			"battle_skill_used":
				focus_cell = _variant_to_cell(change.get("target_cell", focus_cell))
			"battle_unit_damaged", "battle_unit_healed", "battle_status_applied":
				var target_id: String = str(change.get("target_id", change.get("character_id", "")))
				var target_character: CharacterEntity = grid.get_character_by_id(target_id) if grid != null else null
				if target_character != null:
					_focus_camera_on_world_position_if_needed(target_character.position, false)
					return

	if grid != null and grid.in_bounds(focus_cell):
		_focus_camera_on_world_position_if_needed(grid.grid_to_world(focus_cell), false)


func _focus_camera_on_world_position_if_needed(world_position: Vector2, force_center: bool = false) -> void:
	if camera == null:
		return
	if force_center or not _is_world_position_visible(world_position):
		_camera_detached = false
		_set_camera_target(world_position)


func _variant_to_cell(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_VECTOR2:
		var vector_value: Vector2 = value as Vector2
		return Vector2i(floori(vector_value.x), floori(vector_value.y))
	if typeof(value) == TYPE_DICTIONARY:
		var dict_value: Dictionary = value as Dictionary
		return Vector2i(int(dict_value.get("x", -9999)), int(dict_value.get("y", -9999)))
	return Vector2i(-9999, -9999)


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


func _get_character_display_name(character_id: String) -> String:
	if grid == null or character_id.is_empty():
		return character_id

	var character: CharacterEntity = grid.get_character_by_id(character_id)
	if character == null:
		return character_id

	return character.display_name


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))


func _dict_from_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _has_controlled_character() -> bool:
	return controlled_character != null and is_instance_valid(controlled_character)


func _update_building_renderer_focus() -> void:
	if building_renderer == null:
		return
	if not building_renderer.has_method("set_active_cell"):
		return

	building_renderer.set_active_cell(current_grid_position)


func _refresh_battle_character_presentations() -> void:
	if grid == null:
		return
	if not BattleSystem.is_active():
		_clear_battle_character_presentations()
		return

	var summary: Dictionary = BattleSystem.get_summary()
	var current_unit: Dictionary = summary.get("current_unit", {}) as Dictionary
	var current_id: String = str(current_unit.get("character_id", ""))
	_clear_battle_character_presentations()

	var units: Array = summary.get("units", []) as Array
	for unit_value in units:
		var unit: Dictionary = unit_value as Dictionary
		var character_id: String = str(unit.get("character_id", ""))
		var character: CharacterEntity = grid.get_character_by_id(character_id)
		if character == null:
			continue
		character.set_battle_presentation(unit, character_id == current_id)


func _clear_battle_character_presentations() -> void:
	if grid == null:
		return

	for character_value in grid.characters_by_id.values():
		if typeof(character_value) != TYPE_OBJECT or not is_instance_valid(character_value):
			continue
		var character: CharacterEntity = character_value as CharacterEntity
		if character != null:
			character.clear_battle_presentation()


func _spawn_battle_feedback_from_result(result: ActionResult) -> void:
	for change_value in result.world_changes:
		var change: Dictionary = change_value as Dictionary
		match str(change.get("type", "")):
			"battle_skill_used":
				_play_battle_character_effect(str(change.get("character_id", "")), "skill")
			"battle_unit_damaged":
				_play_battle_character_effect(str(change.get("target_id", "")), "damage")
				_spawn_battle_feedback(
					str(change.get("target_id", "")),
					"-%d" % int(change.get("damage", 0)),
					Color(1.0, 0.28, 0.20, 0.98)
				)
			"battle_unit_healed":
				_play_battle_character_effect(str(change.get("target_id", "")), "heal")
				_spawn_battle_feedback(
					str(change.get("target_id", "")),
					"+%d" % int(change.get("healing", 0)),
					Color(0.38, 1.0, 0.45, 0.98)
				)
			"battle_status_applied":
				_play_battle_character_effect(str(change.get("target_id", "")), "status")
				_spawn_battle_feedback(
					str(change.get("target_id", "")),
					str((change.get("status", {}) as Dictionary).get("display_name", "状态")),
					Color(0.78, 0.60, 1.0, 0.98)
				)
			"battle_unit_defeated":
				_spawn_battle_feedback(
					str(change.get("character_id", "")),
					"击败",
					Color(1.0, 0.88, 0.30, 0.98)
				)


func _play_battle_character_effect(character_id: String, effect_type: String) -> void:
	if character_id.is_empty() or grid == null:
		return
	var character: CharacterEntity = grid.get_character_by_id(character_id)
	if character == null:
		return
	character.play_battle_effect(effect_type)


func _spawn_battle_feedback(character_id: String, text: String, color: Color) -> void:
	if character_id.is_empty() or text.is_empty():
		return
	if grid == null or battle_feedback_root == null or not is_instance_valid(battle_feedback_root):
		return

	var character: CharacterEntity = grid.get_character_by_id(character_id)
	if character == null:
		return

	var popup: BattleFeedbackPopup = BattleFeedbackPopup.new()
	popup.position = character.position + Vector2(0.0, -6.0)
	battle_feedback_root.add_child(popup)
	popup.configure(text, color)


func _refresh_interaction_overlay() -> void:
	if interaction_overlay == null or not is_instance_valid(interaction_overlay):
		return
	if grid == null or not _has_controlled_character() or GameState.current_mode != GameState.GameMode.EXPLORATION:
		interaction_overlay.clear_target()
		return

	var current_cell: Vector2i = controlled_character.grid_position
	var current_object: LocationObject = grid.get_primary_object_at(current_cell)
	if current_object != null and current_object.is_pickable:
		interaction_overlay.set_target(current_cell, "pickup")
		return

	var crop_kind: String = _get_crop_interaction_kind(current_cell)
	if not crop_kind.is_empty():
		interaction_overlay.set_target(current_cell, crop_kind)
		return

	if not _get_current_cell_transition_prompt(current_cell).is_empty():
		interaction_overlay.set_target(current_cell, "exit")
		return

	var target_cell: Vector2i = controlled_character.get_facing_cell()
	if not grid.in_bounds(target_cell):
		interaction_overlay.clear_target()
		return

	var target_character: CharacterEntity = grid.get_character_at(target_cell)
	if target_character != null:
		if target_character.is_combatable:
			interaction_overlay.set_target(target_cell, "attack", current_cell)
			return
		if target_character.is_interactable:
			interaction_overlay.set_target(target_cell, "talk", current_cell)
			return

	var target_object: LocationObject = grid.get_primary_object_at(target_cell)
	if target_object != null:
		if target_object.is_pickable:
			interaction_overlay.set_target(target_cell, "pickup", current_cell)
			return
		if target_object.is_facility():
			interaction_overlay.set_target(target_cell, "use", current_cell)
			return
		if target_object.is_usable:
			interaction_overlay.set_target(target_cell, "use", current_cell)
			return
		if target_object.is_inspectable:
			interaction_overlay.set_target(target_cell, "inspect", current_cell)
			return

	var exit_data: Dictionary = grid.get_exit_at(target_cell)
	if not exit_data.is_empty():
		interaction_overlay.set_target(target_cell, "exit", current_cell)
		return

	interaction_overlay.set_target(target_cell, "inspect", current_cell)


func _get_crop_interaction_kind(cell: Vector2i) -> String:
	var crop_state: Dictionary = CropSystem.get_crop_at(grid.location_id, cell)
	if not crop_state.is_empty():
		return "crop"

	if is_cell_plantable(cell) and not CropSystem.get_seed_item_id(controlled_character).is_empty():
		return "crop"

	return ""


func _on_controlled_character_grid_position_changed(_character_id: String, _previous_cell: Vector2i, new_cell: Vector2i) -> void:
	current_grid_position = new_cell
	_update_building_renderer_focus()
	grid_position_changed.emit(current_grid_position)
	_refresh_interaction_overlay()


func _on_controlled_character_facing_changed(_character_id: String, _facing: String) -> void:
	_refresh_interaction_overlay()


func _result_has_change_type(result: ActionResult, change_type: String) -> bool:
	if result == null:
		return false

	for change in result.world_changes:
		if str(change.get("type", "")) == change_type:
			return true

	return false


func _get_world_change(result: ActionResult, change_type: String, character_id: String = "") -> Dictionary:
	if result == null:
		return {}

	for change in result.world_changes:
		if str(change.get("type", "")) != change_type:
			continue
		if not character_id.is_empty() and str(change.get("character_id", "")) != character_id:
			continue
		return change.duplicate(true)

	return {}
