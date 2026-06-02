extends Node

signal move_requested(direction: Vector2i)
signal primary_action_requested()
signal rest_requested()
signal cancel_requested()
signal inventory_toggle_requested()
signal quest_toggle_requested()
signal character_toggle_requested()
signal debug_toggle_requested()
signal save_requested()
signal load_requested()

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
const ACTION_DEBUG_TOGGLE := "debug_toggle"
const ACTION_SAVE := "save_game"
const ACTION_LOAD := "load_game"

var input_locked: bool = false


func _ready() -> void:
	_register_default_actions()


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
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
		move_requested.emit(direction)
		get_viewport().set_input_as_handled()


func set_input_locked(value: bool) -> void:
	input_locked = value


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
	_register_key_action(ACTION_CANCEL, KEY_ESCAPE)
	_register_key_action(ACTION_DEBUG_TOGGLE, KEY_F3)
	_register_key_action(ACTION_SAVE, KEY_F5)
	_register_key_action(ACTION_LOAD, KEY_F9)


func _register_key_action(action_name: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == physical_keycode:
			return

	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	InputMap.action_add_event(action_name, event)
