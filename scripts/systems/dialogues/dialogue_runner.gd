extends Node

signal dialogue_started(speaker_id: String, speaker_name: String)
signal dialogue_node_changed(state: Dictionary)
signal dialogue_ended(result: ActionResult)

var active: bool = false
var actor: CharacterEntity
var speaker: CharacterEntity
var dialogue_id: String = ""
var dialogue_data: Dictionary = {}
var current_node_id: String = ""
var last_result: ActionResult


func start_dialogue(action_actor: CharacterEntity, action_speaker: CharacterEntity, dialogue_source: String) -> ActionResult:
	if action_actor == null or not is_instance_valid(action_actor):
		return ActionResult.failed("TalkAction", "", "Dialogue requires an actor.")
	if action_speaker == null or not is_instance_valid(action_speaker):
		return ActionResult.failed("TalkAction", action_actor.character_id, "Dialogue requires a speaker.")

	var loaded_dialogue: Dictionary = _read_dialogue(dialogue_source)
	if loaded_dialogue.is_empty():
		return ActionResult.failed("TalkAction", action_actor.character_id, "Dialogue resource could not be loaded.")

	actor = action_actor
	speaker = action_speaker
	dialogue_data = loaded_dialogue
	dialogue_id = str(dialogue_data.get("id", ""))
	current_node_id = str(dialogue_data.get("start_node", ""))
	active = true

	GameState.set_mode(GameState.GameMode.DIALOGUE)

	var result: ActionResult = ActionResult.succeeded("TalkAction", actor.character_id, {
		"speaker_id": speaker.character_id,
		"dialogue_id": dialogue_id,
	})
	result.add_world_change({
		"type": "dialogue_started",
		"actor_id": actor.character_id,
		"speaker_id": speaker.character_id,
		"dialogue_id": dialogue_id,
	})
	result.add_feedback("Started dialogue with %s." % speaker.display_name)
	last_result = result

	dialogue_started.emit(speaker.character_id, speaker.display_name)
	dialogue_node_changed.emit(get_current_state())
	return result


func choose_option(option_id: String) -> ActionResult:
	if not active:
		return ActionResult.failed("DialogueOption", "", "No dialogue is active.")
	if not _has_dialogue_participants():
		var failed_result: ActionResult = ActionResult.failed("DialogueOption", _actor_id(), "Dialogue participants are no longer available.")
		_end_dialogue(failed_result)
		return failed_result

	var node: Dictionary = _get_current_node()
	var options: Array = _get_available_options(node)
	for option_value in options:
		var option: Dictionary = option_value as Dictionary
		if str(option.get("id", "")) != option_id:
			continue

		var result: ActionResult = ActionResult.succeeded("DialogueOption", actor.character_id, {
			"speaker_id": speaker.character_id,
			"dialogue_id": dialogue_id,
			"option_id": option_id,
		})
		result.add_world_change({
			"type": "dialogue_option_selected",
			"actor_id": actor.character_id,
			"speaker_id": speaker.character_id,
			"dialogue_id": dialogue_id,
			"option_id": option_id,
		})

		_apply_option_results(option, result)

		if bool(option.get("end", false)):
			result.add_feedback("Dialogue ended.")
			ActionSystem.publish_result(result)
			_end_dialogue(result)
			return result

		var next_node_id: String = str(option.get("next", ""))
		if next_node_id.is_empty():
			result.add_feedback("Dialogue ended.")
			ActionSystem.publish_result(result)
			_end_dialogue(result)
			return result

		current_node_id = next_node_id
		result.add_feedback("Selected: %s" % str(option.get("text", option_id)))
		last_result = result
		ActionSystem.publish_result(result)
		dialogue_node_changed.emit(get_current_state())
		return result

	return ActionResult.failed("DialogueOption", actor.character_id, "Dialogue option is not available: %s" % option_id)


func cancel_dialogue() -> ActionResult:
	if not active:
		return ActionResult.failed("DialogueCancel", "", "No dialogue is active.")

	var result: ActionResult = ActionResult.succeeded("DialogueCancel", _actor_id(), {
		"speaker_id": _speaker_id(),
		"dialogue_id": dialogue_id,
	})
	result.add_world_change({
		"type": "dialogue_cancelled",
		"actor_id": _actor_id(),
		"speaker_id": _speaker_id(),
		"dialogue_id": dialogue_id,
	})
	result.add_feedback("Dialogue cancelled.")
	_end_dialogue(result)
	return result


func get_current_state() -> Dictionary:
	if not active or not _has_dialogue_participants():
		return {}

	QuestSystem.refresh_actor_objectives(actor)
	var node: Dictionary = _get_current_node()
	return {
		"dialogue_id": dialogue_id,
		"node_id": current_node_id,
		"speaker_id": _speaker_id(),
		"speaker_name": speaker.display_name if _has_speaker() else "",
		"text": str(node.get("text", "")),
		"options": _get_available_options(node),
	}


func get_last_summary() -> Dictionary:
	if last_result == null:
		return {}

	return last_result.to_dictionary()


func clear_dialogue_state() -> void:
	active = false
	actor = null
	speaker = null
	dialogue_id = ""
	dialogue_data = {}
	current_node_id = ""


func _end_dialogue(result: ActionResult) -> void:
	active = false
	last_result = result
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	dialogue_ended.emit(result)

	actor = null
	speaker = null
	dialogue_id = ""
	dialogue_data = {}
	current_node_id = ""


func _get_current_node() -> Dictionary:
	var nodes: Dictionary = dialogue_data.get("nodes", {}) as Dictionary
	return nodes.get(current_node_id, {}) as Dictionary


func _get_available_options(node: Dictionary) -> Array:
	if _has_actor():
		QuestSystem.refresh_actor_objectives(actor)

	var available: Array = []
	var options: Array = node.get("options", []) as Array
	for option_value in options:
		var option: Dictionary = option_value as Dictionary
		if _conditions_met(option.get("conditions", []) as Array):
			available.append(option.duplicate(true))

	return available


func _conditions_met(conditions: Array) -> bool:
	for condition_value in conditions:
		var condition: Dictionary = condition_value as Dictionary
		if not _condition_met(condition):
			return false

	return true


func _condition_met(condition: Dictionary) -> bool:
	var condition_type: String = str(condition.get("type", ""))
	match condition_type:
		"has_flag":
			return GameState.has_flag(str(condition.get("key", "")))
		"not_flag":
			return not GameState.has_flag(str(condition.get("key", "")))
		"has_item":
			if not _has_actor() or actor.inventory == null:
				return false
			return actor.inventory.count_item(str(condition.get("item_id", ""))) >= int(condition.get("quantity", 1))
		"character_kind":
			return _has_actor() and actor.character_kind == str(condition.get("value", ""))
		"faction_id":
			return _has_actor() and actor.faction_id == str(condition.get("value", ""))
		"quest_active":
			return QuestSystem.is_quest_active(str(condition.get("quest_id", "")))
		"quest_completed":
			return QuestSystem.is_quest_completed(str(condition.get("quest_id", "")))
		"not_quest_active":
			return not QuestSystem.is_quest_active(str(condition.get("quest_id", "")))
		"not_quest_completed":
			return not QuestSystem.is_quest_completed(str(condition.get("quest_id", "")))
		"relation_at_least":
			return RelationSystem.character_metric_at_least(
				_resolve_character_id(str(condition.get("source", "speaker"))),
				_resolve_character_id(str(condition.get("target", "actor"))),
				str(condition.get("metric", "affinity")),
				int(condition.get("value", 0))
			)
		"relation_below":
			return RelationSystem.character_metric_below(
				_resolve_character_id(str(condition.get("source", "speaker"))),
				_resolve_character_id(str(condition.get("target", "actor"))),
				str(condition.get("metric", "affinity")),
				int(condition.get("value", 0))
			)
		"relation_stance":
			return RelationSystem.get_character_stance(
				_resolve_character_id(str(condition.get("source", "speaker"))),
				_resolve_character_id(str(condition.get("target", "actor")))
			) == str(condition.get("value", "neutral"))
		"faction_relation_at_least":
			return RelationSystem.faction_metric_at_least(
				_resolve_faction_id(str(condition.get("source", "speaker"))),
				_resolve_faction_id(str(condition.get("target", "actor"))),
				str(condition.get("metric", "affinity")),
				int(condition.get("value", 0))
			)
		"faction_relation_below":
			return RelationSystem.faction_metric_below(
				_resolve_faction_id(str(condition.get("source", "speaker"))),
				_resolve_faction_id(str(condition.get("target", "actor"))),
				str(condition.get("metric", "affinity")),
				int(condition.get("value", 0))
			)
		"faction_stance":
			return RelationSystem.get_faction_stance(
				_resolve_faction_id(str(condition.get("source", "speaker"))),
				_resolve_faction_id(str(condition.get("target", "actor")))
			) == str(condition.get("value", "neutral"))
		_:
			return true


func _apply_option_results(option: Dictionary, result: ActionResult) -> void:
	var results: Array = option.get("results", []) as Array
	for entry_value in results:
		var entry: Dictionary = entry_value as Dictionary
		var result_type: String = str(entry.get("type", ""))
		match result_type:
			"set_flag":
				var key: String = str(entry.get("key", ""))
				var value: bool = bool(entry.get("value", true))
				if not key.is_empty():
					GameState.set_flag(key, value)
					result.add_world_change({
						"type": "flag_set",
						"key": key,
						"value": value,
						"source": "dialogue",
					})
			"request_action":
				var action_type: String = str(entry.get("action_type", ""))
				var target: Dictionary = entry.duplicate(true)
				target.erase("type")
				target.erase("action_type")
				var action: GameAction = ActionSystem.create_action(action_type, actor, target, {
					"source": "dialogue",
					"speaker": speaker,
					"dialogue_id": dialogue_id,
				}) as GameAction
				var action_result: ActionResult = ActionSystem.submit(action) as ActionResult
				result.add_world_change({
					"type": "dialogue_requested_action",
					"action_type": action_type,
					"success": action_result.success,
				})
				for change in action_result.world_changes:
					result.add_world_change(change)
				for feedback in action_result.feedback:
					result.add_feedback(str(feedback))
			"relation_delta":
				var relation_scope: String = str(entry.get("scope", "character"))
				var relation_source_id: String = _resolve_character_id(str(entry.get("source", "speaker")))
				var relation_target_id: String = _resolve_character_id(str(entry.get("target", "actor")))
				if relation_scope == "faction":
					relation_source_id = _resolve_faction_id(str(entry.get("source", "speaker")))
					relation_target_id = _resolve_faction_id(str(entry.get("target", "actor")))
				result.add_world_change({
					"type": "relation_delta",
					"scope": relation_scope,
					"source_id": relation_source_id,
					"target_id": relation_target_id,
					"delta": (entry.get("delta", {}) as Dictionary).duplicate(true),
					"reason": str(entry.get("reason", "dialogue")),
				})
			_:
				result.add_world_change({
					"type": "dialogue_result_unhandled",
					"result": entry.duplicate(true),
				})


func _read_dialogue(resource_path: String) -> Dictionary:
	return DefinitionLoader.load_dialogue(resource_path)


func _resolve_character_id(value: String) -> String:
	match value:
		"actor":
			return _actor_id()
		"speaker":
			return _speaker_id()
		_:
			return value


func _resolve_faction_id(value: String) -> String:
	match value:
		"actor":
			return actor.faction_id if _has_actor() else ""
		"speaker":
			return speaker.faction_id if _has_speaker() else ""
		_:
			return value


func _has_dialogue_participants() -> bool:
	return _has_actor() and _has_speaker()


func _has_actor() -> bool:
	return actor != null and is_instance_valid(actor)


func _has_speaker() -> bool:
	return speaker != null and is_instance_valid(speaker)


func _actor_id() -> String:
	return actor.character_id if _has_actor() else ""


func _speaker_id() -> String:
	return speaker.character_id if _has_speaker() else ""
