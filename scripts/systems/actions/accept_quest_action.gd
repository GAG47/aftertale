class_name AcceptQuestAction
extends GameAction


func _init() -> void:
	action_type = "AcceptQuestAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var quest_id: String = str(target.get("quest_id", ""))
	if quest_id.is_empty():
		return _failure("AcceptQuestAction requires a quest_id.")

	if not QuestSystem.quest_definitions.has(quest_id):
		return _failure("Unknown quest: %s" % quest_id)

	if QuestSystem.is_quest_active(quest_id):
		return _failure("Quest is already active: %s" % quest_id)

	if QuestSystem.is_quest_completed(quest_id):
		return _failure("Quest is already completed: %s" % quest_id)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var quest_id: String = str(target.get("quest_id", ""))
	return QuestSystem.accept_quest(quest_id, actor)
