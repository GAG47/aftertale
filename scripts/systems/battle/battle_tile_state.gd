class_name BattleTileState
extends RefCounted

const DEFAULT_LAYER := "surface"

var id: String = ""
var cell: Vector2i = Vector2i.ZERO
var layer: String = DEFAULT_LAYER
var remaining_rounds: int = 0
var intensity: int = 1
var source_character_id: String = ""
var source_skill_id: String = ""
var created_round: int = 0
var created_turn: int = 0
var tags: Array[String] = []


static func from_effect(effect: Dictionary, target_cell: Vector2i, context: Dictionary):
	var state := BattleTileState.new()
	var battle_state: BattleState = context.get("battle_state") as BattleState
	var caster: BattleUnitState = context.get("caster") as BattleUnitState
	var skill: Dictionary = context.get("skill", {}) as Dictionary

	state.id = str(effect.get("state_id", effect.get("id", "")))
	state.cell = target_cell
	state.layer = str(effect.get("layer", DEFAULT_LAYER))
	if state.layer.is_empty():
		state.layer = DEFAULT_LAYER
	state.remaining_rounds = max(0, int(effect.get("duration_rounds", 0)))
	state.intensity = max(1, int(effect.get("intensity", 1)))
	state.source_character_id = caster.character_id if caster != null else str(effect.get("source_character_id", ""))
	state.source_skill_id = str(skill.get("id", effect.get("source_skill_id", "")))
	if battle_state != null:
		state.created_round = battle_state.round_number
		state.created_turn = battle_state.turn_index

	var raw_tags: Array = effect.get("tags", []) as Array
	for tag_value in raw_tags:
		var tag: String = str(tag_value)
		if not tag.is_empty():
			state.tags.append(tag)

	return state


func merge_same_state(other) -> bool:
	if other == null:
		return false

	intensity = max(intensity, other.intensity)
	if other.remaining_rounds <= remaining_rounds:
		return false

	remaining_rounds = other.remaining_rounds
	source_character_id = other.source_character_id
	source_skill_id = other.source_skill_id
	created_round = other.created_round
	created_turn = other.created_turn
	tags = other.tags.duplicate()
	return true


func tick_round() -> bool:
	remaining_rounds -= 1
	return remaining_rounds < 0


func get_summary() -> Dictionary:
	return {
		"id": id,
		"state_id": id,
		"cell": cell,
		"layer": layer,
		"remaining_rounds": remaining_rounds,
		"intensity": intensity,
		"source_character_id": source_character_id,
		"source_skill_id": source_skill_id,
		"created_round": created_round,
		"created_turn": created_turn,
		"tags": tags.duplicate(),
		"display_id": id,
	}
