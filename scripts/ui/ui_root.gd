class_name UIRoot
extends Control

signal return_title_requested()
signal new_game_requested()
signal quit_game_requested()

@onready var time_label: Label = $TopBar/TopBarMargin/StatusRow/TimeLabel
@onready var mode_label: Label = $TopBar/TopBarMargin/StatusRow/ModeLabel
@onready var scene_label: Label = $TopBar/TopBarMargin/StatusRow/SceneLabel
@onready var interaction_panel: PanelContainer = $InteractionPanel
@onready var interaction_label: Label = $InteractionPanel/MarginContainer/InteractionLabel
@onready var message_log_panel: MessageLogPanel = $MessageLogPanel
@onready var debug_panel: DebugPanel = $DebugPanel
@onready var game_menu_panel: GameMenuPanel = $GameMenuPanel
@onready var inventory_panel = $InventoryPanel
@onready var quest_panel = $QuestPanel
@onready var character_panel = $CharacterPanel
@onready var facility_panel = $FacilityPanel
@onready var battle_hud_panel: BattleHudPanel = $BattleHudPanel
@onready var dialogue_panel: DialoguePanel = $DialoguePanel

var _game_state: Node
var _scene_loader: Node
var _time_manager: Node
var _input_manager: Node
var _dialogue_runner: Node
var _mode_before_menu: int = GameState.GameMode.EXPLORATION


func bind_managers(game_state: Node, scene_loader: Node, time_manager: Node, input_manager: Node, action_system: Node, dialogue_runner: Node, quest_system: Node, relation_system: Node) -> void:
	_game_state = game_state
	_scene_loader = scene_loader
	_time_manager = time_manager
	_input_manager = input_manager
	_dialogue_runner = dialogue_runner

	_game_state.mode_changed.connect(_on_mode_changed)
	_game_state.scene_context_changed.connect(_on_scene_context_changed)
	_time_manager.time_changed.connect(_on_time_changed)
	action_system.action_executed.connect(_on_action_result)
	action_system.action_failed.connect(_on_action_result)
	_input_manager.inventory_toggle_requested.connect(_on_inventory_toggle_requested)
	_input_manager.quest_toggle_requested.connect(_on_quest_toggle_requested)
	_input_manager.character_toggle_requested.connect(_on_character_toggle_requested)
	_dialogue_runner.dialogue_node_changed.connect(_on_dialogue_node_changed)
	_dialogue_runner.dialogue_ended.connect(_on_dialogue_ended)
	BattleSystem.battle_started.connect(_on_battle_changed)
	BattleSystem.battle_turn_started.connect(_on_battle_turn_started)
	BattleSystem.battle_ended.connect(_on_battle_ended)
	BattleSystem.battle_state_changed.connect(_refresh_battle_hud)
	SaveManager.game_loaded.connect(_on_game_loaded)
	SaveManager.load_failed.connect(_on_load_failed)
	_scene_loader.scene_changed.connect(_on_scene_changed)
	dialogue_panel.option_selected.connect(_on_dialogue_option_selected)
	game_menu_panel.close_requested.connect(_on_game_menu_close_requested)
	game_menu_panel.return_title_requested.connect(_on_game_menu_return_title_requested)
	game_menu_panel.quit_game_requested.connect(_on_game_menu_quit_requested)
	game_menu_panel.new_game_requested.connect(_on_game_menu_new_game_requested)
	inventory_panel.close_requested.connect(_on_inventory_close_requested)
	inventory_panel.inventory_action_requested.connect(_on_inventory_action_requested)
	quest_panel.close_requested.connect(_on_quest_close_requested)
	character_panel.close_requested.connect(_on_character_close_requested)
	character_panel.character_action_requested.connect(_on_character_action_requested)
	facility_panel.close_requested.connect(_on_facility_close_requested)
	facility_panel.facility_action_requested.connect(_on_facility_action_requested)
	battle_hud_panel.wait_requested.connect(_on_battle_wait_requested)
	battle_hud_panel.flee_requested.connect(_on_battle_flee_requested)
	battle_hud_panel.skill_selected.connect(_on_battle_skill_selected)
	battle_hud_panel.move_selected.connect(_on_battle_move_selected)
	battle_hud_panel.turn_unit_selected.connect(_on_battle_turn_unit_selected)

	debug_panel.bind_managers(_game_state, _scene_loader, _time_manager, _input_manager, action_system, _dialogue_runner, quest_system, relation_system)
	game_menu_panel.bind_context(_scene_loader, quest_system)
	quest_panel.bind_context(quest_system)

	_refresh_static_labels()
	_on_time_changed(_time_manager.day, _time_manager.hour, _time_manager.minute)
	_refresh_interaction_prompt()
	message_log_panel.add_message("新的冒险开始了。")


func toggle_debug_panel() -> void:
	set_debug_panel_visible(not debug_panel.visible)


func set_debug_panel_visible(value: bool) -> void:
	debug_panel.visible = value


func is_debug_panel_visible() -> bool:
	return debug_panel.visible


func is_game_menu_visible() -> bool:
	return game_menu_panel.visible


func is_title_screen_visible() -> bool:
	return game_menu_panel.is_title_screen()


func is_inventory_visible() -> bool:
	return inventory_panel.visible


func is_quest_visible() -> bool:
	return quest_panel.visible


func is_character_visible() -> bool:
	return character_panel.visible


func is_facility_visible() -> bool:
	return facility_panel.is_open()


func toggle_game_menu() -> void:
	if game_menu_panel.is_title_screen():
		return

	if game_menu_panel.visible:
		close_game_menu()
		return

	open_game_menu()


func open_game_menu() -> void:
	if game_menu_panel.is_title_screen():
		return

	if _game_state.current_mode != GameState.GameMode.EXPLORATION and _game_state.current_mode != GameState.GameMode.MENU:
		return

	if inventory_panel.visible:
		inventory_panel.close_panel()
	if quest_panel.visible:
		quest_panel.close_panel()
	if character_panel.visible:
		character_panel.close_panel()
	if facility_panel.visible:
		facility_panel.close_panel()
	_mode_before_menu = _game_state.current_mode
	_game_state.set_mode(GameState.GameMode.MENU)
	game_menu_panel.open_menu()
	message_log_panel.add_message("打开菜单。")


func close_game_menu() -> void:
	if not game_menu_panel.visible:
		return
	if game_menu_panel.is_title_screen():
		return

	game_menu_panel.close_menu()
	var restore_mode: int = _mode_before_menu
	if restore_mode == GameState.GameMode.MENU:
		restore_mode = GameState.GameMode.EXPLORATION
	_game_state.set_mode(restore_mode)
	message_log_panel.add_message("关闭菜单。")


func open_title_screen() -> void:
	clear_transient_ui()
	_mode_before_menu = GameState.GameMode.EXPLORATION
	_game_state.set_mode(GameState.GameMode.MENU)
	game_menu_panel.open_title_menu()
	message_log_panel.add_message("返回标题。")


func toggle_inventory() -> void:
	if inventory_panel.visible:
		close_inventory()
		return

	open_inventory()


func open_inventory() -> void:
	if _game_state.current_mode != GameState.GameMode.EXPLORATION and _game_state.current_mode != GameState.GameMode.MENU:
		return

	var actor: CharacterEntity = _get_controlled_character()
	if actor == null:
		return

	if game_menu_panel.visible:
		game_menu_panel.close_menu()
	if quest_panel.visible:
		quest_panel.close_panel()
	if character_panel.visible:
		character_panel.close_panel()
	if facility_panel.visible:
		facility_panel.close_panel()
	_mode_before_menu = _game_state.current_mode
	_game_state.set_mode(GameState.GameMode.MENU)
	inventory_panel.open_for_actor(actor)
	message_log_panel.add_message("打开背包。")


func close_inventory() -> void:
	if not inventory_panel.visible:
		return

	inventory_panel.close_panel()
	var restore_mode: int = _mode_before_menu
	if restore_mode == GameState.GameMode.MENU:
		restore_mode = GameState.GameMode.EXPLORATION
	_game_state.set_mode(restore_mode)
	message_log_panel.add_message("关闭背包。")


func toggle_quest_panel() -> void:
	if quest_panel.visible:
		close_quest_panel()
		return

	open_quest_panel()


func open_quest_panel() -> void:
	if _game_state.current_mode != GameState.GameMode.EXPLORATION and _game_state.current_mode != GameState.GameMode.MENU:
		return

	if game_menu_panel.visible:
		game_menu_panel.close_menu()
	if inventory_panel.visible:
		inventory_panel.close_panel()
	if character_panel.visible:
		character_panel.close_panel()
	if facility_panel.visible:
		facility_panel.close_panel()
	_mode_before_menu = _game_state.current_mode
	_game_state.set_mode(GameState.GameMode.MENU)
	quest_panel.open_panel()
	message_log_panel.add_message("打开任务。")


func close_quest_panel() -> void:
	if not quest_panel.visible:
		return

	quest_panel.close_panel()
	var restore_mode: int = _mode_before_menu
	if restore_mode == GameState.GameMode.MENU:
		restore_mode = GameState.GameMode.EXPLORATION
	_game_state.set_mode(restore_mode)
	message_log_panel.add_message("关闭任务。")


func toggle_character_panel() -> void:
	if character_panel.visible:
		close_character_panel()
		return

	open_character_panel()


func open_character_panel() -> void:
	if _game_state.current_mode != GameState.GameMode.EXPLORATION and _game_state.current_mode != GameState.GameMode.MENU:
		return

	var actor: CharacterEntity = _get_controlled_character()
	if actor == null:
		return

	if game_menu_panel.visible:
		game_menu_panel.close_menu()
	if inventory_panel.visible:
		inventory_panel.close_panel()
	if quest_panel.visible:
		quest_panel.close_panel()
	if facility_panel.visible:
		facility_panel.close_panel()
	_mode_before_menu = _game_state.current_mode
	_game_state.set_mode(GameState.GameMode.MENU)
	character_panel.open_for_actor(actor)
	message_log_panel.add_message("打开角色。")


func close_character_panel() -> void:
	if not character_panel.visible:
		return

	character_panel.close_panel()
	var restore_mode: int = _mode_before_menu
	if restore_mode == GameState.GameMode.MENU:
		restore_mode = GameState.GameMode.EXPLORATION
	_game_state.set_mode(restore_mode)
	message_log_panel.add_message("关闭角色。")


func open_facility(facility_data: Dictionary) -> void:
	if _game_state.current_mode != GameState.GameMode.EXPLORATION and _game_state.current_mode != GameState.GameMode.MENU:
		return

	var actor: CharacterEntity = _get_controlled_character()
	if actor == null:
		return

	if game_menu_panel.visible:
		game_menu_panel.close_menu()
	if inventory_panel.visible:
		inventory_panel.close_panel()
	if quest_panel.visible:
		quest_panel.close_panel()
	if character_panel.visible:
		character_panel.close_panel()
	_mode_before_menu = _game_state.current_mode
	_game_state.set_mode(GameState.GameMode.MENU)
	facility_panel.open_for_facility(actor, facility_data)
	message_log_panel.add_message("打开%s。" % str(facility_data.get("display_name", "交互对象")))


func close_facility() -> void:
	if not facility_panel.is_open():
		return

	facility_panel.close_panel()
	var restore_mode: int = _mode_before_menu
	if restore_mode == GameState.GameMode.MENU:
		restore_mode = GameState.GameMode.EXPLORATION
	_game_state.set_mode(restore_mode)
	message_log_panel.add_message("关闭交互。")


func clear_transient_ui() -> void:
	game_menu_panel.close_menu()
	inventory_panel.close_panel()
	quest_panel.close_panel()
	character_panel.close_panel()
	facility_panel.close_panel()
	dialogue_panel.hide_panel()
	battle_hud_panel.hide_panel()
	message_log_panel.visible = true
	_mode_before_menu = GameState.GameMode.EXPLORATION
	_input_manager.set_input_locked(false)


func _refresh_static_labels() -> void:
	if _game_state == null:
		return

	mode_label.text = "模式：%s" % _game_state.get_mode_label()
	scene_label.text = "场景：%s" % _game_state.current_scene_id


func _on_time_changed(day: int, hour: int, minute: int) -> void:
	time_label.text = "第 %d 天 %02d:%02d %s" % [day, hour, minute, _time_manager.get_day_period_label()]


func _on_mode_changed(_previous_mode: int, new_mode: int) -> void:
	mode_label.text = "模式：%s" % _game_state.get_mode_label(new_mode)
	message_log_panel.visible = new_mode != GameState.GameMode.COMBAT
	_refresh_interaction_prompt()


func _on_scene_context_changed(scene_id: String, _location_id: String) -> void:
	scene_label.text = "场景：%s" % scene_id
	if not scene_id.is_empty() and scene_id != "boot":
		message_log_panel.add_message("进入场景：%s。" % scene_id)
	_refresh_interaction_prompt()


func _on_scene_changed(_scene_path: String, scene_root: Node) -> void:
	if scene_root != null and scene_root.has_signal("facility_requested"):
		var callback := Callable(self, "_on_facility_requested")
		if not scene_root.is_connected("facility_requested", callback):
			scene_root.connect("facility_requested", callback)
	_refresh_interaction_prompt()


func _on_dialogue_node_changed(state: Dictionary) -> void:
	dialogue_panel.show_state(state)


func _on_dialogue_ended(_result: ActionResult) -> void:
	dialogue_panel.hide_panel()
	_refresh_interaction_prompt()


func _on_dialogue_option_selected(option_id: String) -> void:
	_dialogue_runner.choose_option(option_id)


func _on_inventory_toggle_requested() -> void:
	toggle_inventory()


func _on_quest_toggle_requested() -> void:
	toggle_quest_panel()


func _on_character_toggle_requested() -> void:
	toggle_character_panel()


func _on_game_menu_close_requested() -> void:
	close_game_menu()


func _on_game_menu_return_title_requested() -> void:
	return_title_requested.emit()


func _on_game_menu_quit_requested() -> void:
	quit_game_requested.emit()


func _on_game_menu_new_game_requested() -> void:
	new_game_requested.emit()


func _on_inventory_close_requested() -> void:
	close_inventory()


func _on_quest_close_requested() -> void:
	close_quest_panel()


func _on_character_close_requested() -> void:
	close_character_panel()


func _on_facility_close_requested() -> void:
	close_facility()


func _on_inventory_action_requested(action_type: String, target: Dictionary) -> void:
	var actor: CharacterEntity = _get_controlled_character()
	if actor == null:
		return

	var action: GameAction = ActionSystem.create_action(action_type, actor, target, {
		"source": "inventory",
	})
	ActionSystem.submit(action)
	inventory_panel.open_for_actor(actor)


func _on_character_action_requested(action_type: String, target: Dictionary) -> void:
	var actor: CharacterEntity = _get_controlled_character()
	if actor == null:
		return

	var action: GameAction = ActionSystem.create_action(action_type, actor, target, {
		"source": "character",
	})
	ActionSystem.submit(action)
	character_panel.refresh()


func _on_facility_requested(facility_data: Dictionary) -> void:
	open_facility(facility_data)


func _on_facility_action_requested(action_type: String, target: Dictionary) -> void:
	var actor: CharacterEntity = _get_controlled_character()
	if actor == null:
		return

	var action: GameAction = ActionSystem.create_action(action_type, actor, target, {
		"source": "facility",
	})
	ActionSystem.submit(action)
	facility_panel.refresh()


func _on_game_loaded(_save_path: String) -> void:
	clear_transient_ui()
	_refresh_static_labels()
	_on_time_changed(_time_manager.day, _time_manager.hour, _time_manager.minute)


func _on_load_failed(_save_path: String, reason: String) -> void:
	message_log_panel.add_message(reason)


func _on_action_result(_action_type: String, _actor_id: String, result: ActionResult) -> void:
	_refresh_battle_hud()
	_refresh_interaction_prompt()
	if inventory_panel.visible:
		var actor: CharacterEntity = _get_controlled_character()
		if actor != null:
			inventory_panel.open_for_actor(actor)
	if quest_panel.visible:
		quest_panel.refresh()
	if character_panel.visible:
		character_panel.refresh()
	if facility_panel.is_open():
		facility_panel.refresh()
	if not _should_show_result(result):
		return

	message_log_panel.add_result(result)


func _on_battle_changed(_battle_id: String) -> void:
	_refresh_battle_hud()


func _on_battle_turn_started(_character_id: String, _round_number: int) -> void:
	_refresh_battle_hud()


func _on_battle_ended(_battle_id: String, _result_status: String) -> void:
	_refresh_battle_hud()
	_refresh_interaction_prompt()


func _on_battle_wait_requested() -> void:
	BattleSystem.wait_current_unit()
	_refresh_battle_hud()


func _on_battle_flee_requested() -> void:
	BattleSystem.flee_current_unit()
	_refresh_battle_hud()


func _on_battle_skill_selected(skill_id: String) -> void:
	if not BattleSystem.is_player_turn():
		return

	if not BattleSystem.select_skill_for_current_unit(skill_id):
		return

	var skill: Dictionary = SkillSystem.get_skill(skill_id)
	if str(skill.get("target_type", "")) == "self":
		var preview: Dictionary = BattleSystem.get_player_tactical_preview()
		BattleSystem.request_use_skill_current_unit(skill_id, preview.get("current_cell", Vector2i.ZERO) as Vector2i)

	_refresh_battle_hud()


func _on_battle_move_selected() -> void:
	if not BattleSystem.is_player_turn():
		return

	BattleSystem.select_tactical_mode(BattleSystem.TACTICAL_MODE_MOVE)
	_refresh_battle_hud()


func _on_battle_turn_unit_selected(character_id: String) -> void:
	if BattleSystem.select_player_turn_unit(character_id):
		_refresh_battle_hud()


func _refresh_battle_hud() -> void:
	if not BattleSystem.is_active():
		battle_hud_panel.hide_panel()
		return

	battle_hud_panel.show_battle_summary(
		BattleSystem.get_summary(),
		BattleSystem.is_player_turn(),
		BattleSystem.get_current_unit_skill_summaries(),
		BattleSystem.get_selected_skill_id(),
		BattleSystem.get_tactical_mode(),
		BattleSystem.consume_reopen_skill_menu_requested()
	)


func _refresh_interaction_prompt() -> void:
	if interaction_panel == null or interaction_label == null:
		return

	if _game_state == null or _game_state.current_mode != GameState.GameMode.EXPLORATION:
		interaction_panel.visible = false
		return

	var prompt: String = ""
	if _scene_loader != null and _scene_loader.current_scene != null and is_instance_valid(_scene_loader.current_scene):
		if _scene_loader.current_scene.has_method("get_interaction_prompt"):
			prompt = str(_scene_loader.current_scene.get_interaction_prompt())

	if prompt.is_empty():
		prompt = "WASD/方向键移动  E/Enter 互动  B 背包  J 任务  C 角色  R 等待"

	interaction_label.text = prompt
	interaction_panel.visible = true


func _get_controlled_character() -> CharacterEntity:
	if _scene_loader == null or _scene_loader.current_scene == null or not is_instance_valid(_scene_loader.current_scene):
		return null
	if not _scene_loader.current_scene.has_method("get_controlled_character"):
		return null
	return _scene_loader.current_scene.get_controlled_character() as CharacterEntity


func _should_show_result(result: ActionResult) -> bool:
	if result == null:
		return false

	if not result.success:
		return true

	match result.action_type:
		"MoveAction", "BattleMove", "BattleTurnStart", "ScheduleUpdate":
			return false
		_:
			return true
