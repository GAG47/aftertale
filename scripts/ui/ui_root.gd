class_name UIRoot
extends Control

@onready var time_label: Label = $TopBar/TopBarMargin/StatusRow/TimeLabel
@onready var mode_label: Label = $TopBar/TopBarMargin/StatusRow/ModeLabel
@onready var scene_label: Label = $TopBar/TopBarMargin/StatusRow/SceneLabel
@onready var interaction_panel: PanelContainer = $InteractionPanel
@onready var interaction_label: Label = $InteractionPanel/MarginContainer/InteractionLabel
@onready var message_log_panel: MessageLogPanel = $MessageLogPanel
@onready var debug_panel: DebugPanel = $DebugPanel
@onready var game_menu_panel: GameMenuPanel = $GameMenuPanel
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
	_input_manager.menu_toggle_requested.connect(_on_menu_toggle_requested)
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
	battle_hud_panel.wait_requested.connect(_on_battle_wait_requested)
	battle_hud_panel.flee_requested.connect(_on_battle_flee_requested)
	battle_hud_panel.skill_selected.connect(_on_battle_skill_selected)

	debug_panel.bind_managers(_game_state, _scene_loader, _time_manager, _input_manager, action_system, _dialogue_runner, quest_system, relation_system)
	game_menu_panel.bind_context(_scene_loader, quest_system)

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


func toggle_game_menu() -> void:
	if game_menu_panel.visible:
		close_game_menu()
		return

	open_game_menu()


func open_game_menu() -> void:
	if _game_state.current_mode != GameState.GameMode.EXPLORATION and _game_state.current_mode != GameState.GameMode.MENU:
		return

	_mode_before_menu = _game_state.current_mode
	_game_state.set_mode(GameState.GameMode.MENU)
	game_menu_panel.open_menu()
	message_log_panel.add_message("打开菜单。")


func close_game_menu() -> void:
	if not game_menu_panel.visible:
		return

	game_menu_panel.close_menu()
	var restore_mode: int = _mode_before_menu
	if restore_mode == GameState.GameMode.MENU:
		restore_mode = GameState.GameMode.EXPLORATION
	_game_state.set_mode(restore_mode)
	message_log_panel.add_message("关闭菜单。")


func clear_transient_ui() -> void:
	game_menu_panel.close_menu()
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


func _on_scene_changed(_scene_path: String, _scene_root: Node) -> void:
	_refresh_interaction_prompt()


func _on_dialogue_node_changed(state: Dictionary) -> void:
	dialogue_panel.show_state(state)


func _on_dialogue_ended(_result: ActionResult) -> void:
	dialogue_panel.hide_panel()
	_refresh_interaction_prompt()


func _on_dialogue_option_selected(option_id: String) -> void:
	_dialogue_runner.choose_option(option_id)


func _on_menu_toggle_requested() -> void:
	toggle_game_menu()


func _on_game_menu_close_requested() -> void:
	close_game_menu()


func _on_game_loaded(_save_path: String) -> void:
	clear_transient_ui()
	_refresh_static_labels()
	_on_time_changed(_time_manager.day, _time_manager.hour, _time_manager.minute)


func _on_load_failed(_save_path: String, reason: String) -> void:
	message_log_panel.add_message(reason)


func _on_action_result(_action_type: String, _actor_id: String, result: ActionResult) -> void:
	_refresh_battle_hud()
	_refresh_interaction_prompt()
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


func _refresh_battle_hud() -> void:
	if not BattleSystem.is_active():
		battle_hud_panel.hide_panel()
		return

	battle_hud_panel.show_battle_summary(
		BattleSystem.get_summary(),
		BattleSystem.is_player_turn(),
		BattleSystem.get_current_unit_skill_summaries(),
		BattleSystem.get_selected_skill_id()
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
		prompt = "WASD/方向键移动  E/Enter 互动  Tab/I 菜单  R 等待"

	interaction_label.text = prompt
	interaction_panel.visible = true


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
