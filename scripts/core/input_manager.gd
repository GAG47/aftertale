extends Node

signal move_requested(direction: Vector2i)
signal primary_action_requested()
signal rest_requested()
signal cancel_requested()
signal inventory_toggle_requested()
signal quest_toggle_requested()
signal character_toggle_requested()
signal region_map_toggle_requested()
signal debug_toggle_requested()
signal save_requested()
signal load_requested()
signal camera_zoom_requested(steps: int)
signal camera_zoom_reset_requested()
signal camera_pan_requested(direction: Vector2i)
signal camera_drag_requested(screen_delta: Vector2)
signal camera_recenter_requested()

const ACTION_MOVE_UP := "move_up"
const ACTION_MOVE_DOWN := "move_down"
const ACTION_MOVE_LEFT := "move_left"
const ACTION_MOVE_RIGHT := "move_right"
const ACTION_INTERACT := "interact"
const ACTION_REST := "rest"
const ACTION_CANCEL := "cancel"
const ACTION_INVENTORY_TOGGLE := "inventory_toggle"
const ACTION_QUEST_TOGGLE := "quest_toggle"
const ACTION_CHARACTER_TOGGLE := "character_toggle"
const ACTION_REGION_MAP_TOGGLE := "region_map_toggle"
const ACTION_DEBUG_TOGGLE := "debug_toggle"
const ACTION_SAVE := "save_game"
const ACTION_LOAD := "load_game"
const ACTION_CAMERA_ZOOM_IN := "camera_zoom_in"
const ACTION_CAMERA_ZOOM_OUT := "camera_zoom_out"
const ACTION_CAMERA_ZOOM_RESET := "camera_zoom_reset"
const ACTION_CAMERA_RECENTER := "camera_recenter"
const MOVE_REPEAT_INITIAL_DELAY := 0.18
const MOVE_REPEAT_INTERVAL := 0.12

var input_locked: bool = false
var _camera_drag_active: bool = false
var _held_move_direction: Vector2i = Vector2i.ZERO
var _move_repeat_timer: float = 0.0
var _move_repeat_ready: bool = false


func _ready() -> void:
	_register_default_actions()


func _process(delta: float) -> void:
	_update_held_move_repeat(delta)


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		_clear_held_move_repeat()
		return

	if _handle_camera_zoom_event(event):
		get_viewport().set_input_as_handled()
		return

	if _handle_camera_drag_event(event):
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_CAMERA_RECENTER):
		camera_recenter_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_DEBUG_TOGGLE):
		debug_toggle_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_SAVE):
		save_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_LOAD):
		load_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_INTERACT):
		primary_action_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_REST):
		rest_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_INVENTORY_TOGGLE):
		inventory_toggle_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_QUEST_TOGGLE):
		quest_toggle_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_CHARACTER_TOGGLE):
		character_toggle_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_REGION_MAP_TOGGLE):
		region_map_toggle_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_CANCEL):
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
		return

	var direction := Vector2i.ZERO
	if event.is_action_pressed(ACTION_MOVE_UP):
		direction = Vector2i.UP
	elif event.is_action_pressed(ACTION_MOVE_DOWN):
		direction = Vector2i.DOWN
	elif event.is_action_pressed(ACTION_MOVE_LEFT):
		direction = Vector2i.LEFT
	elif event.is_action_pressed(ACTION_MOVE_RIGHT):
		direction = Vector2i.RIGHT

	if direction != Vector2i.ZERO:
		if _is_camera_pan_modifier_pressed(event):
			_clear_held_move_repeat()
			camera_pan_requested.emit(direction)
			get_viewport().set_input_as_handled()
			return
		if _is_key_echo(event):
			get_viewport().set_input_as_handled()
			return
		_start_held_move_repeat(direction)
		move_requested.emit(direction)
		get_viewport().set_input_as_handled()


func set_input_locked(value: bool) -> void:
	input_locked = value
	if input_locked:
		_clear_held_move_repeat()


func _register_default_actions() -> void:
	_register_key_action(ACTION_MOVE_UP, KEY_W)
	_register_key_action(ACTION_MOVE_UP, KEY_UP)
	_register_key_action(ACTION_MOVE_DOWN, KEY_S)
	_register_key_action(ACTION_MOVE_DOWN, KEY_DOWN)
	_register_key_action(ACTION_MOVE_LEFT, KEY_A)
	_register_key_action(ACTION_MOVE_LEFT, KEY_LEFT)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_D)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_RIGHT)
	_register_key_action(ACTION_INTERACT, KEY_E)
	_register_key_action(ACTION_INTERACT, KEY_ENTER)
	_register_key_action(ACTION_REST, KEY_R)
	_register_key_action(ACTION_INVENTORY_TOGGLE, KEY_B)
	_register_key_action(ACTION_QUEST_TOGGLE, KEY_J)
	_register_key_action(ACTION_CHARACTER_TOGGLE, KEY_C)
	_register_key_action(ACTION_REGION_MAP_TOGGLE, KEY_M)
	_register_key_action(ACTION_CANCEL, KEY_ESCAPE)
	_register_key_action(ACTION_DEBUG_TOGGLE, KEY_F3)
	_register_key_action(ACTION_SAVE, KEY_F5)
	_register_key_action(ACTION_LOAD, KEY_F9)
	_register_key_action(ACTION_CAMERA_ZOOM_IN, KEY_EQUAL)
	_register_key_action(ACTION_CAMERA_ZOOM_IN, KEY_KP_ADD)
	_register_key_action(ACTION_CAMERA_ZOOM_OUT, KEY_MINUS)
	_register_key_action(ACTION_CAMERA_ZOOM_OUT, KEY_KP_SUBTRACT)
	_register_key_action(ACTION_CAMERA_ZOOM_RESET, KEY_0)
	_register_key_action(ACTION_CAMERA_RECENTER, KEY_HOME)


func _handle_camera_zoom_event(event: InputEvent) -> bool:
	if event.is_action_pressed(ACTION_CAMERA_ZOOM_IN):
		camera_zoom_requested.emit(1)
		return true

	if event.is_action_pressed(ACTION_CAMERA_ZOOM_OUT):
		camera_zoom_requested.emit(-1)
		return true

	if event.is_action_pressed(ACTION_CAMERA_ZOOM_RESET):
		camera_zoom_reset_requested.emit()
		return true

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if not mouse_event.pressed:
			return false
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_zoom_requested.emit(1)
			return true
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom_requested.emit(-1)
			return true

	return false


func _handle_camera_drag_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_MIDDLE:
			return false
		_camera_drag_active = mouse_button.pressed
		return true

	if event is InputEventMouseMotion and _camera_drag_active:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_camera_drag_active = false
			return false
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		camera_drag_requested.emit(mouse_motion.relative)
		return true

	return false


func _is_camera_pan_modifier_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		return key_event.shift_pressed

	return Input.is_key_pressed(KEY_SHIFT)


func _update_held_move_repeat(delta: float) -> void:
	if input_locked:
		_clear_held_move_repeat()
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_clear_held_move_repeat()
		return

	var direction: Vector2i = _get_pressed_move_direction()
	if direction == Vector2i.ZERO:
		_clear_held_move_repeat()
		return

	if direction != _held_move_direction:
		_start_held_move_repeat(direction)
		return

	_move_repeat_timer -= delta
	if _move_repeat_timer > 0.0:
		return

	move_requested.emit(direction)
	_move_repeat_timer = MOVE_REPEAT_INTERVAL
	_move_repeat_ready = true


func _start_held_move_repeat(direction: Vector2i) -> void:
	_held_move_direction = direction
	_move_repeat_timer = MOVE_REPEAT_INTERVAL if _move_repeat_ready else MOVE_REPEAT_INITIAL_DELAY
	_move_repeat_ready = false


func _clear_held_move_repeat() -> void:
	_held_move_direction = Vector2i.ZERO
	_move_repeat_timer = 0.0
	_move_repeat_ready = false


func _get_pressed_move_direction() -> Vector2i:
	if Input.is_action_pressed(ACTION_MOVE_UP):
		return Vector2i.UP
	if Input.is_action_pressed(ACTION_MOVE_DOWN):
		return Vector2i.DOWN
	if Input.is_action_pressed(ACTION_MOVE_LEFT):
		return Vector2i.LEFT
	if Input.is_action_pressed(ACTION_MOVE_RIGHT):
		return Vector2i.RIGHT
	return Vector2i.ZERO


func _is_key_echo(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		return key_event.echo
	return false


func _register_key_action(action_name: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == physical_keycode:
			return

	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	InputMap.action_add_event(action_name, event)
