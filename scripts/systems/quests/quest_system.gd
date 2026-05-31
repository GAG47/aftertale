extends Node

signal quest_accepted(quest_id: String)
signal quest_objective_completed(quest_id: String, objective_id: String)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String, reason: String)

const QUEST_DEFINITION_PATHS := [
	"res://data/quests/debug_apple_request.json",
]

var quest_definitions: Dictionary = {}
var quest_states: Dictionary = {}
var quest_owners: Dictionary = {}


func _ready() -> void:
	_load_quest_definitions()
	ActionSystem.action_executed.connect(_on_action_executed)


func accept_quest(quest_id: String, actor: CharacterEntity) -> ActionResult:
	if quest_id.is_empty():
		return ActionResult.failed("AcceptQuestAction", _actor_id(actor), "AcceptQuestAction requires a quest_id.")

	if not _is_live_actor(actor):
		return ActionResult.failed("AcceptQuestAction", "", "AcceptQuestAction requires an actor.")

	if not quest_definitions.has(quest_id):
		return ActionResult.failed("AcceptQuestAction", actor.character_id, "Unknown quest: %s" % quest_id)

	if quest_states.has(quest_id):
		var existing_state: QuestState = quest_states[quest_id] as QuestState
		if existing_state.status == QuestState.STATUS_ACTIVE:
			return ActionResult.failed("AcceptQuestAction", actor.character_id, "Quest is already active: %s" % quest_id)
		if existing_state.status == QuestState.STATUS_COMPLETED:
			return ActionResult.failed("AcceptQuestAction", actor.character_id, "Quest is already completed: %s" % quest_id)

	var definition: Dictionary = quest_definitions[quest_id] as Dictionary
	var failed_requirement: String = _get_failed_requirement(definition, actor)
	if not failed_requirement.is_empty():
		return ActionResult.failed("AcceptQuestAction", actor.character_id, failed_requirement)

	var state: QuestState = QuestState.from_definition(definition)
	state.activate()
	quest_states[quest_id] = state
	quest_owners[quest_id] = actor.character_id
	_check_all_objectives_for_state(state, actor, null)

	var result: ActionResult = ActionResult.succeeded("AcceptQuestAction", actor.character_id, {
		"quest_id": quest_id,
	})
	result.add_world_change({
		"type": "quest_accepted",
		"quest_id": quest_id,
		"actor_id": actor.character_id,
	})
	result.add_feedback("Accepted quest: %s." % state.display_name)

	quest_accepted.emit(quest_id)
	return result


func fail_quest(quest_id: String, reason: String) -> ActionResult:
	if not quest_states.has(quest_id):
		return ActionResult.failed("QuestFail", "", "Cannot fail unknown quest: %s" % quest_id)

	var state: QuestState = quest_states[quest_id] as QuestState
	if state.status != QuestState.STATUS_ACTIVE:
		return ActionResult.failed("QuestFail", "", "Quest is not active: %s" % quest_id)

	state.fail(reason)
	quest_failed.emit(quest_id, reason)

	var result: ActionResult = ActionResult.succeeded("QuestFail", "", { "quest_id": quest_id })
	result.add_world_change({
		"type": "quest_failed",
		"quest_id": quest_id,
		"reason": reason,
	})
	result.add_feedback("Quest failed: %s." % state.display_name)
	return result


func get_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for state_value in quest_states.values():
		var state: QuestState = state_value as QuestState
		summary.append(state.to_dictionary())

	return summary


func is_quest_active(quest_id: String) -> bool:
	if not quest_states.has(quest_id):
		return false

	var state: QuestState = quest_states[quest_id] as QuestState
	return state.status == QuestState.STATUS_ACTIVE


func is_quest_completed(quest_id: String) -> bool:
	if not quest_states.has(quest_id):
		return false

	var state: QuestState = quest_states[quest_id] as QuestState
	return state.status == QuestState.STATUS_COMPLETED


func get_save_state() -> Dictionary:
	var saved_states: Dictionary = {}
	for quest_id in quest_states.keys():
		var state: QuestState = quest_states[quest_id] as QuestState
		saved_states[str(quest_id)] = state.to_dictionary()

	return {
		"quest_states": saved_states,
		"quest_owners": quest_owners.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	quest_states.clear()
	quest_owners = (state.get("quest_owners", {}) as Dictionary).duplicate(true)

	var saved_states: Dictionary = state.get("quest_states", {}) as Dictionary
	for quest_id_value in saved_states.keys():
		var quest_id: String = str(quest_id_value)
		if not quest_definitions.has(quest_id):
			continue

		var quest_definition: Dictionary = quest_definitions[quest_id] as Dictionary
		var quest_state: QuestState = QuestState.from_definition(quest_definition)
		quest_state.apply_save_state(saved_states[quest_id] as Dictionary)
		quest_states[quest_id] = quest_state


func process_action_result(result: ActionResult) -> void:
	if result == null or not result.success:
		return

	for quest_id in quest_states.keys():
		var state: QuestState = quest_states[quest_id] as QuestState
		if state.status != QuestState.STATUS_ACTIVE:
			continue

		var owner: CharacterEntity = _resolve_quest_owner(str(quest_id))
		_check_all_objectives_for_state(state, owner, result)
		if state.is_all_objectives_completed():
			_complete_quest(state, owner)


func refresh_actor_objectives(actor: CharacterEntity) -> void:
	if not _is_live_actor(actor):
		return

	for quest_id in quest_states.keys():
		var state: QuestState = quest_states[quest_id] as QuestState
		if state.status != QuestState.STATUS_ACTIVE:
			continue
		if _get_quest_owner_id(str(quest_id)) != actor.character_id:
			continue

		_check_all_objectives_for_state(state, actor, null)
		if state.is_all_objectives_completed():
			_complete_quest(state, actor)


func _on_action_executed(_action_type: String, _actor_id: String, result: ActionResult) -> void:
	process_action_result(result)


func _check_all_objectives_for_state(state: QuestState, owner: CharacterEntity, result: ActionResult) -> void:
	var definition: Dictionary = quest_definitions[state.quest_id] as Dictionary
	var objective_rows: Array = definition.get("objectives", []) as Array
	for objective_value in objective_rows:
		var objective: Dictionary = objective_value as Dictionary
		var objective_id: String = str(objective.get("id", ""))
		if objective_id.is_empty():
			continue

		var current_state: Dictionary = state.objectives.get(objective_id, {}) as Dictionary
		if bool(current_state.get("completed", false)):
			continue

		if _objective_met(objective, owner, result):
			if state.mark_objective_completed(objective_id):
				quest_objective_completed.emit(state.quest_id, objective_id)
				_publish_objective_completed(state, objective_id, owner)


func _objective_met(objective: Dictionary, owner: CharacterEntity, result: ActionResult) -> bool:
	var objective_type: String = str(objective.get("type", ""))
	match objective_type:
		"has_item":
			if not _is_live_actor(owner) or owner.inventory == null:
				return false
			return owner.inventory.count_item(str(objective.get("item_id", ""))) >= int(objective.get("quantity", 1))
		"item_picked_up":
			return _result_has_change(result, {
				"type": "item_picked_up",
				"item_id": str(objective.get("item_id", "")),
			})
		"dialogue_option_selected":
			return _result_has_change(result, {
				"type": "dialogue_option_selected",
				"dialogue_id": str(objective.get("dialogue_id", "")),
				"option_id": str(objective.get("option_id", "")),
			})
		"flag_set":
			return _result_has_change(result, {
				"type": "flag_set",
				"key": str(objective.get("key", "")),
			})
		_:
			return false


func _get_failed_requirement(definition: Dictionary, actor: CharacterEntity) -> String:
	var requirements: Array = definition.get("requirements", []) as Array
	for requirement_value in requirements:
		var requirement: Dictionary = requirement_value as Dictionary
		if not _requirement_met(requirement, definition, actor):
			return str(requirement.get("failure_text", "Quest requirements are not met."))

	return ""


func _requirement_met(requirement: Dictionary, definition: Dictionary, actor: CharacterEntity) -> bool:
	var requirement_type: String = str(requirement.get("type", ""))
	match requirement_type:
		"relation_at_least":
			return RelationSystem.character_metric_at_least(
				_resolve_requirement_character_id(str(requirement.get("source", "source")), definition, actor),
				_resolve_requirement_character_id(str(requirement.get("target", "actor")), definition, actor),
				str(requirement.get("metric", "affinity")),
				int(requirement.get("value", 0))
			)
		"relation_below":
			return RelationSystem.character_metric_below(
				_resolve_requirement_character_id(str(requirement.get("source", "source")), definition, actor),
				_resolve_requirement_character_id(str(requirement.get("target", "actor")), definition, actor),
				str(requirement.get("metric", "affinity")),
				int(requirement.get("value", 0))
			)
		"relation_stance":
			return RelationSystem.get_character_stance(
				_resolve_requirement_character_id(str(requirement.get("source", "source")), definition, actor),
				_resolve_requirement_character_id(str(requirement.get("target", "actor")), definition, actor)
			) == str(requirement.get("value", "neutral"))
		"faction_relation_at_least":
			return RelationSystem.faction_metric_at_least(
				_resolve_requirement_faction_id(str(requirement.get("source", "actor")), actor),
				_resolve_requirement_faction_id(str(requirement.get("target", "actor")), actor),
				str(requirement.get("metric", "affinity")),
				int(requirement.get("value", 0))
			)
		"faction_relation_below":
			return RelationSystem.faction_metric_below(
				_resolve_requirement_faction_id(str(requirement.get("source", "actor")), actor),
				_resolve_requirement_faction_id(str(requirement.get("target", "actor")), actor),
				str(requirement.get("metric", "affinity")),
				int(requirement.get("value", 0))
			)
		"faction_stance":
			return RelationSystem.get_faction_stance(
				_resolve_requirement_faction_id(str(requirement.get("source", "actor")), actor),
				_resolve_requirement_faction_id(str(requirement.get("target", "actor")), actor)
			) == str(requirement.get("value", "neutral"))
		_:
			return true


func _resolve_requirement_character_id(value: String, definition: Dictionary, actor: CharacterEntity) -> String:
	match value:
		"actor":
			return _actor_id(actor)
		"source":
			var source: Dictionary = definition.get("source", {}) as Dictionary
			return str(source.get("id", ""))
		_:
			return value


func _resolve_requirement_faction_id(value: String, actor: CharacterEntity) -> String:
	match value:
		"actor":
			return actor.faction_id if _is_live_actor(actor) else ""
		_:
			return value


func _result_has_change(result: ActionResult, expected: Dictionary) -> bool:
	if result == null:
		return false

	for change in result.world_changes:
		var matches: bool = true
		for key in expected.keys():
			if not change.has(key) or change[key] != expected[key]:
				matches = false
				break

		if matches:
			return true

	return false


func _complete_quest(state: QuestState, owner: CharacterEntity) -> void:
	if state.status != QuestState.STATUS_ACTIVE:
		return

	state.complete()
	var reward_changes: Array[Dictionary] = _apply_rewards(state, owner)
	quest_completed.emit(state.quest_id)

	var result: ActionResult = ActionResult.succeeded("QuestCompleted", _actor_id(owner), {
		"quest_id": state.quest_id,
	})
	result.add_world_change({
		"type": "quest_completed",
		"quest_id": state.quest_id,
		"actor_id": _actor_id(owner),
	})
	for change in reward_changes:
		result.add_world_change(change)
	result.add_feedback("Quest completed: %s." % state.display_name)
	ActionSystem.publish_result(result)


func _apply_rewards(state: QuestState, owner: CharacterEntity) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var definition: Dictionary = quest_definitions[state.quest_id] as Dictionary
	var rewards: Array = definition.get("rewards", []) as Array
	for reward_value in rewards:
		var reward: Dictionary = reward_value as Dictionary
		var reward_type: String = str(reward.get("type", ""))
		match reward_type:
			"item":
				if not _is_live_actor(owner) or owner.inventory == null:
					continue
				var item_definition: Dictionary = DefinitionLoader.load_item(str(reward.get("source", "")))
				if item_definition.is_empty():
					continue
				var quantity: int = int(reward.get("quantity", 1))
				if owner.inventory.add_item(item_definition, quantity):
					GameState.save_character_runtime(owner)
					changes.append({
						"type": "quest_reward_item",
						"quest_id": state.quest_id,
						"actor_id": owner.character_id,
						"item_id": str(item_definition.get("id", "")),
						"quantity": quantity,
					})
			"flag":
				var key: String = str(reward.get("key", ""))
				if not key.is_empty():
					var value: bool = bool(reward.get("value", true))
					GameState.set_flag(key, value)
					changes.append({
						"type": "quest_reward_flag",
						"quest_id": state.quest_id,
						"key": key,
						"value": value,
					})
			"relation":
				var source_id: String = str(reward.get("source_id", ""))
				var target_id: String = str(reward.get("target_id", ""))
				if bool(reward.get("target_actor", false)) and _is_live_actor(owner):
					target_id = owner.character_id

				if not source_id.is_empty() and not target_id.is_empty():
					changes.append({
						"type": "relation_delta",
						"scope": str(reward.get("scope", "character")),
						"source_id": source_id,
						"target_id": target_id,
						"delta": (reward.get("delta", {}) as Dictionary).duplicate(true),
						"reason": str(reward.get("reason", state.quest_id)),
						"quest_id": state.quest_id,
					})

	return changes


func _publish_objective_completed(state: QuestState, objective_id: String, owner: CharacterEntity) -> void:
	var result: ActionResult = ActionResult.succeeded("QuestObjectiveCompleted", _actor_id(owner), {
		"quest_id": state.quest_id,
		"objective_id": objective_id,
	})
	result.add_world_change({
		"type": "quest_objective_completed",
		"quest_id": state.quest_id,
		"objective_id": objective_id,
		"actor_id": _actor_id(owner),
	})
	result.add_feedback("Quest objective completed: %s." % objective_id)
	ActionSystem.publish_result(result)


func _load_quest_definitions() -> void:
	for path in QUEST_DEFINITION_PATHS:
		var definition: Dictionary = DefinitionLoader.load_quest(path)
		if definition.is_empty():
			continue

		var quest_id: String = str(definition.get("id", ""))
		if not quest_id.is_empty():
			quest_definitions[quest_id] = definition


func _actor_id(actor: CharacterEntity) -> String:
	if not _is_live_actor(actor):
		return ""

	return actor.character_id


func _resolve_quest_owner(quest_id: String) -> CharacterEntity:
	var owner_id: String = _get_quest_owner_id(quest_id)
	if owner_id.is_empty():
		return null

	if SceneLoader.current_scene == null or not is_instance_valid(SceneLoader.current_scene):
		return null

	if not SceneLoader.current_scene.has_method("get_location_grid"):
		return null

	var grid: LocationGrid = SceneLoader.current_scene.get_location_grid() as LocationGrid
	if grid == null:
		return null

	return grid.get_character_by_id(owner_id)


func _get_quest_owner_id(quest_id: String) -> String:
	if not quest_owners.has(quest_id):
		return ""

	var owner_value: Variant = quest_owners[quest_id]
	if typeof(owner_value) == TYPE_STRING:
		return str(owner_value)

	if typeof(owner_value) == TYPE_OBJECT and is_instance_valid(owner_value):
		var owner: CharacterEntity = owner_value as CharacterEntity
		return owner.character_id if owner != null else ""

	return ""


func _is_live_actor(actor: CharacterEntity) -> bool:
	return actor != null and is_instance_valid(actor)
