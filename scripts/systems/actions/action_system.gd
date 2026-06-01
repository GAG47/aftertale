extends Node

signal action_requested(action_type: String, actor_id: String)
signal action_checked(action_type: String, actor_id: String, result: ActionResult)
signal action_executed(action_type: String, actor_id: String, result: ActionResult)
signal action_failed(action_type: String, actor_id: String, result: ActionResult)

var last_result: ActionResult
var action_history: Array[Dictionary] = []


func submit(action: GameAction) -> ActionResult:
	if action == null:
		var null_result: ActionResult = ActionResult.failed("UnknownAction", "", "ActionSystem received a null action.")
		_record_result(null_result)
		action_failed.emit(null_result.action_type, null_result.actor_id, null_result)
		return null_result

	action_requested.emit(action.action_type, action.actor_id)

	var check_result: ActionResult = action.check()
	action_checked.emit(action.action_type, action.actor_id, check_result)
	if not check_result.success:
		_record_result(check_result)
		action_failed.emit(action.action_type, action.actor_id, check_result)
		return check_result

	var execution_result: ActionResult = action.execute()
	if execution_result.already_published:
		last_result = execution_result
		return execution_result

	_record_result(execution_result)
	if execution_result.success:
		action_executed.emit(action.action_type, action.actor_id, execution_result)
	else:
		action_failed.emit(action.action_type, action.actor_id, execution_result)

	return execution_result


func create_action(action_type: String, actor: CharacterEntity, target: Dictionary = {}, context: Dictionary = {}) -> GameAction:
	var action: GameAction
	match action_type:
		"MoveAction":
			action = MoveAction.new()
		"TalkAction":
			action = TalkAction.new()
		"InspectAction":
			action = InspectAction.new()
		"PickUpAction":
			action = PickUpAction.new()
		"UseItemAction":
			action = UseItemAction.new()
		"UseSkillAction":
			action = UseSkillAction.new()
		"EquipItemAction":
			action = EquipItemAction.new()
		"UnequipItemAction":
			action = UnequipItemAction.new()
		"PlantAction":
			action = PlantAction.new()
		"WaterAction":
			action = WaterAction.new()
		"HarvestAction":
			action = HarvestAction.new()
		"AttackAction":
			action = AttackAction.new()
		"TradeAction":
			action = TradeAction.new()
		"RestAction":
			action = RestAction.new()
		"CraftAction":
			action = CraftAction.new()
		"AcceptQuestAction":
			action = AcceptQuestAction.new()
		_:
			action = UnsupportedAction.new()
			action.action_type = action_type
			action.required_system = "a registered action rule"

	action.configure(actor, target, context)
	return action


func get_last_summary() -> Dictionary:
	if last_result == null:
		return {}

	return last_result.to_dictionary()


func publish_result(result: ActionResult) -> void:
	if result == null:
		return

	_record_result(result)
	if result.success:
		action_executed.emit(result.action_type, result.actor_id, result)
	else:
		action_failed.emit(result.action_type, result.actor_id, result)


func _record_result(result: ActionResult) -> void:
	last_result = result
	action_history.append(result.to_dictionary())
	if action_history.size() > 50:
		action_history.pop_front()
