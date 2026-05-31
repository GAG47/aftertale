extends Node

signal character_relation_changed(source_id: String, target_id: String, state: Dictionary)
signal faction_relation_changed(source_id: String, target_id: String, state: Dictionary)
signal relation_event(event: Dictionary)

const INITIAL_RELATIONS_PATH := "res://data/relations/initial_relations.json"
const MIN_SCORE := -100
const MAX_SCORE := 100
const MIN_HOSTILITY := 0
const MAX_HOSTILITY := 100

var character_relations: Dictionary = {}
var faction_relations: Dictionary = {}
var relation_events: Array[Dictionary] = []


func _ready() -> void:
	_load_initial_relations()
	ActionSystem.action_executed.connect(_on_action_executed)


func get_character_relation(source_id: String, target_id: String) -> Dictionary:
	return _get_relation(character_relations, source_id, target_id)


func get_faction_relation(source_id: String, target_id: String) -> Dictionary:
	return _get_relation(faction_relations, source_id, target_id)


func get_character_stance(source_id: String, target_id: String) -> String:
	return str(get_character_relation(source_id, target_id).get("stance", "neutral"))


func get_faction_stance(source_id: String, target_id: String) -> String:
	return str(get_faction_relation(source_id, target_id).get("stance", "neutral"))


func apply_character_delta(source_id: String, target_id: String, delta: Dictionary, reason: String, origin_action: String = "") -> Dictionary:
	if source_id.is_empty() or target_id.is_empty():
		return {}

	var relation: Dictionary = get_character_relation(source_id, target_id)
	var previous: Dictionary = relation.duplicate(true)
	_apply_delta_to_relation(relation, delta)
	character_relations[_relation_key(source_id, target_id)] = relation

	var event: Dictionary = _make_event("character", source_id, target_id, previous, relation, delta, reason, origin_action)
	_record_event(event)
	character_relation_changed.emit(source_id, target_id, relation.duplicate(true))
	return event


func apply_faction_delta(source_id: String, target_id: String, delta: Dictionary, reason: String, origin_action: String = "") -> Dictionary:
	if source_id.is_empty() or target_id.is_empty():
		return {}

	var relation: Dictionary = get_faction_relation(source_id, target_id)
	var previous: Dictionary = relation.duplicate(true)
	_apply_delta_to_relation(relation, delta)
	faction_relations[_relation_key(source_id, target_id)] = relation

	var event: Dictionary = _make_event("faction", source_id, target_id, previous, relation, delta, reason, origin_action)
	_record_event(event)
	faction_relation_changed.emit(source_id, target_id, relation.duplicate(true))
	return event


func get_summary_for_actor(actor_id: String, visible_characters: Array) -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for character_value in visible_characters:
		var character: Dictionary = character_value as Dictionary
		var character_id: String = str(character.get("id", ""))
		if character_id.is_empty() or character_id == actor_id:
			continue

		var relation: Dictionary = get_character_relation(character_id, actor_id)
		summary.append({
			"source_id": character_id,
			"target_id": actor_id,
			"affinity": int(relation.get("affinity", 0)),
			"trust": int(relation.get("trust", 0)),
			"hostility": int(relation.get("hostility", 0)),
			"stance": str(relation.get("stance", "neutral")),
		})

	return summary


func get_recent_events(limit: int = 5) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index: int = max(0, relation_events.size() - limit)
	for index in range(start_index, relation_events.size()):
		var event: Dictionary = relation_events[index] as Dictionary
		result.append(event.duplicate(true))

	return result


func get_save_state() -> Dictionary:
	return {
		"character_relations": character_relations.duplicate(true),
		"faction_relations": faction_relations.duplicate(true),
		"relation_events": relation_events.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	character_relations = (state.get("character_relations", {}) as Dictionary).duplicate(true)
	faction_relations = (state.get("faction_relations", {}) as Dictionary).duplicate(true)
	relation_events.clear()
	var saved_events: Array = state.get("relation_events", []) as Array
	for event_value in saved_events:
		var event: Dictionary = event_value as Dictionary
		relation_events.append(event.duplicate(true))


func character_metric_at_least(source_id: String, target_id: String, metric: String, value: int) -> bool:
	var relation: Dictionary = get_character_relation(source_id, target_id)
	return int(relation.get(metric, 0)) >= value


func character_metric_below(source_id: String, target_id: String, metric: String, value: int) -> bool:
	var relation: Dictionary = get_character_relation(source_id, target_id)
	return int(relation.get(metric, 0)) < value


func faction_metric_at_least(source_id: String, target_id: String, metric: String, value: int) -> bool:
	var relation: Dictionary = get_faction_relation(source_id, target_id)
	return int(relation.get(metric, 0)) >= value


func faction_metric_below(source_id: String, target_id: String, metric: String, value: int) -> bool:
	var relation: Dictionary = get_faction_relation(source_id, target_id)
	return int(relation.get(metric, 0)) < value


func allows_trade(source_id: String, target_id: String) -> bool:
	var relation: Dictionary = get_character_relation(source_id, target_id)
	return str(relation.get("stance", "neutral")) != "hostile"


func get_trade_price_modifier(source_id: String, target_id: String) -> float:
	var relation: Dictionary = get_character_relation(source_id, target_id)
	var affinity: int = int(relation.get("affinity", 0))
	var hostility: int = int(relation.get("hostility", 0))
	return clampf(1.0 - float(affinity) * 0.002 + float(hostility) * 0.005, 0.75, 1.5)


func allows_hostile_action(source_id: String, target_id: String) -> bool:
	var relation: Dictionary = get_character_relation(source_id, target_id)
	var stance: String = str(relation.get("stance", "neutral"))
	return stance == "hostile" or int(relation.get("hostility", 0)) >= 70


func _on_action_executed(action_type: String, _actor_id: String, result: ActionResult) -> void:
	if result == null or not result.success:
		return

	var produced_events: Array[Dictionary] = []
	for change_value in result.world_changes:
		var change: Dictionary = change_value as Dictionary
		if str(change.get("type", "")) != "relation_delta":
			continue

		var scope: String = str(change.get("scope", "character"))
		var source_id: String = str(change.get("source_id", ""))
		var target_id: String = str(change.get("target_id", ""))
		var delta: Dictionary = change.get("delta", {}) as Dictionary
		var reason: String = str(change.get("reason", action_type))
		var event: Dictionary = {}
		match scope:
			"character":
				event = apply_character_delta(source_id, target_id, delta, reason, action_type)
			"faction":
				event = apply_faction_delta(source_id, target_id, delta, reason, action_type)
			_:
				event = {}

		if not event.is_empty():
			produced_events.append(event)

	if produced_events.is_empty():
		return

	var relation_result: ActionResult = ActionResult.succeeded("RelationEvent", result.actor_id, {
		"source_action": action_type,
	})
	for event_value in produced_events:
		var event: Dictionary = event_value as Dictionary
		var current_relation: Dictionary = event.get("current", {}) as Dictionary
		relation_result.add_world_change({
			"type": "relation_changed",
			"scope": str(event.get("scope", "")),
			"source_id": str(event.get("source_id", "")),
			"target_id": str(event.get("target_id", "")),
			"stance": str(current_relation.get("stance", "neutral")),
		})
		relation_result.add_feedback(_event_feedback(event))

	ActionSystem.publish_result(relation_result)


func _load_initial_relations() -> void:
	var data: Dictionary = _read_json(INITIAL_RELATIONS_PATH)
	if data.is_empty():
		return

	var character_rows: Array = data.get("character_relations", []) as Array
	for relation_value in character_rows:
		var relation_data: Dictionary = relation_value as Dictionary
		var source_id: String = str(relation_data.get("source_id", ""))
		var target_id: String = str(relation_data.get("target_id", ""))
		if source_id.is_empty() or target_id.is_empty():
			continue

		character_relations[_relation_key(source_id, target_id)] = _normalize_relation(relation_data)

	var faction_rows: Array = data.get("faction_relations", []) as Array
	for relation_value in faction_rows:
		var relation_data: Dictionary = relation_value as Dictionary
		var source_id: String = str(relation_data.get("source_id", ""))
		var target_id: String = str(relation_data.get("target_id", ""))
		if source_id.is_empty() or target_id.is_empty():
			continue

		faction_relations[_relation_key(source_id, target_id)] = _normalize_relation(relation_data)


func _get_relation(store: Dictionary, source_id: String, target_id: String) -> Dictionary:
	var key: String = _relation_key(source_id, target_id)
	if store.has(key):
		var relation: Dictionary = store[key] as Dictionary
		return relation.duplicate(true)

	return _default_relation(source_id, target_id)


func _default_relation(source_id: String, target_id: String) -> Dictionary:
	return {
		"source_id": source_id,
		"target_id": target_id,
		"affinity": 0,
		"trust": 0,
		"hostility": 0,
		"stance": "neutral",
	}


func _normalize_relation(data: Dictionary) -> Dictionary:
	var relation: Dictionary = _default_relation(str(data.get("source_id", "")), str(data.get("target_id", "")))
	relation["affinity"] = clampi(int(data.get("affinity", 0)), MIN_SCORE, MAX_SCORE)
	relation["trust"] = clampi(int(data.get("trust", 0)), MIN_SCORE, MAX_SCORE)
	relation["hostility"] = clampi(int(data.get("hostility", 0)), MIN_HOSTILITY, MAX_HOSTILITY)
	relation["stance"] = _derive_stance(relation)
	return relation


func _apply_delta_to_relation(relation: Dictionary, delta: Dictionary) -> void:
	relation["affinity"] = clampi(int(relation.get("affinity", 0)) + int(delta.get("affinity", 0)), MIN_SCORE, MAX_SCORE)
	relation["trust"] = clampi(int(relation.get("trust", 0)) + int(delta.get("trust", 0)), MIN_SCORE, MAX_SCORE)
	relation["hostility"] = clampi(int(relation.get("hostility", 0)) + int(delta.get("hostility", 0)), MIN_HOSTILITY, MAX_HOSTILITY)
	relation["stance"] = _derive_stance(relation)


func _derive_stance(relation: Dictionary) -> String:
	var affinity: int = int(relation.get("affinity", 0))
	var trust: int = int(relation.get("trust", 0))
	var hostility: int = int(relation.get("hostility", 0))
	if hostility >= 70:
		return "hostile"
	if hostility >= 30 or affinity <= -25:
		return "wary"
	if affinity >= 25 and trust >= 10 and hostility <= 10:
		return "friendly"
	return "neutral"


func _make_event(scope: String, source_id: String, target_id: String, previous: Dictionary, current: Dictionary, delta: Dictionary, reason: String, origin_action: String) -> Dictionary:
	return {
		"scope": scope,
		"source_id": source_id,
		"target_id": target_id,
		"previous": previous,
		"current": current.duplicate(true),
		"delta": delta.duplicate(true),
		"reason": reason,
		"origin_action": origin_action,
		"time": TimeManager.get_time_label(),
	}


func _record_event(event: Dictionary) -> void:
	relation_events.append(event.duplicate(true))
	if relation_events.size() > 50:
		relation_events.pop_front()
	relation_event.emit(event.duplicate(true))


func _event_feedback(event: Dictionary) -> String:
	var current: Dictionary = event.get("current", {}) as Dictionary
	return "%s relation %s -> %s is now %s." % [
		str(event.get("scope", "character")).capitalize(),
		str(event.get("source_id", "")),
		str(event.get("target_id", "")),
		str(current.get("stance", "neutral")),
	]


func _relation_key(source_id: String, target_id: String) -> String:
	return "%s->%s" % [source_id, target_id]


func _read_json(resource_path: String) -> Dictionary:
	return DefinitionLoader.load_relation_data(resource_path)
