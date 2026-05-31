class_name BattleUnitState
extends RefCounted

const TEAM_PLAYER := "player"
const TEAM_ENEMY := "enemy"

var character: CharacterEntity
var character_id: String = ""
var display_name: String = ""
var team: String = TEAM_ENEMY
var speed: int = 1
var max_hp: int = 1
var hp: int = 1
var max_action_points: int = 2
var action_points: int = 2
var defeated: bool = false
var fled: bool = false
var skills: Array[String] = []
var status_effects: Dictionary = {}
var skill_cooldowns: Dictionary = {}


static func from_character(source_character: CharacterEntity, team_id: String) -> BattleUnitState:
	var unit: BattleUnitState = BattleUnitState.new()
	unit.character = source_character
	unit.character_id = source_character.character_id
	unit.display_name = source_character.display_name
	unit.team = team_id
	unit.speed = unit._read_speed(source_character)
	unit.max_hp = max(1, int(source_character.attributes.get("max_hp", int(source_character.attributes.get("vitality", 1)) * 4)))
	unit.hp = clampi(int(source_character.attributes.get("hp", unit.max_hp)), 0, unit.max_hp)
	unit.max_action_points = max(1, int(source_character.attributes.get("action_points", 2)))
	unit.action_points = unit.max_action_points
	unit.skills.clear()
	for skill_id in source_character.skills:
		if str(skill_id).is_empty():
			continue
		unit.skills.append(str(skill_id))
	if unit.skills.is_empty():
		unit.skills.append("basic_attack")
	unit.defeated = unit.hp <= 0
	return unit


func refresh_turn() -> void:
	clear_statuses_expiring("turn_start")
	_tick_skill_cooldowns()
	action_points = max_action_points


func spend_action_points(amount: int) -> bool:
	if amount <= 0:
		return true

	if action_points < amount:
		return false

	action_points -= amount
	return true


func apply_damage(amount: int) -> int:
	var actual_damage: int = max(0, amount)
	hp = max(0, hp - actual_damage)
	defeated = hp <= 0
	if _has_character():
		character.set_combat_stats(hp, max_hp, defeated)
		GameState.save_character_runtime(character)
	return actual_damage


func apply_heal(amount: int) -> int:
	if defeated:
		return 0

	var before_hp: int = hp
	hp = min(max_hp, hp + max(0, amount))
	var actual_heal: int = hp - before_hp
	if _has_character():
		character.set_combat_stats(hp, max_hp, defeated)
		GameState.save_character_runtime(character)
	return actual_heal


func add_status_effect(status_data: Dictionary) -> void:
	var status_id: String = str(status_data.get("status_id", status_data.get("id", "")))
	if status_id.is_empty():
		return

	var stored_status: Dictionary = status_data.duplicate(true)
	stored_status["id"] = status_id
	status_effects[status_id] = stored_status


func clear_statuses_expiring(expire_rule: String) -> void:
	for status_id_value in status_effects.keys().duplicate():
		var status_id: String = str(status_id_value)
		var status_data: Dictionary = status_effects[status_id] as Dictionary
		if str(status_data.get("expires", "")) == expire_rule:
			status_effects.erase(status_id)


func get_defense_bonus() -> int:
	var total: int = 0
	for status_value in status_effects.values():
		var status_data: Dictionary = status_value as Dictionary
		total += int(status_data.get("defense_bonus", 0))

	return total


func set_skill_cooldown(skill_id: String, turns: int) -> void:
	if skill_id.is_empty() or turns <= 0:
		return

	skill_cooldowns[skill_id] = turns


func get_skill_cooldown(skill_id: String) -> int:
	return max(0, int(skill_cooldowns.get(skill_id, 0)))


func has_status_effect(status_id: String) -> bool:
	return status_effects.has(status_id)


func get_summary() -> Dictionary:
	var has_character: bool = _has_character()
	return {
		"character_id": character_id,
		"display_name": display_name,
		"team": team,
		"speed": speed,
		"hp": hp,
		"max_hp": max_hp,
		"action_points": action_points,
		"max_action_points": max_action_points,
		"defeated": defeated,
		"fled": fled,
		"grid_position": character.grid_position if has_character else Vector2i.ZERO,
		"facing": character.facing if has_character else "",
		"skills": skills,
		"status_effects": status_effects.duplicate(true),
		"skill_cooldowns": skill_cooldowns.duplicate(true),
		"status_text": _get_status_text(),
	}


func is_active() -> bool:
	return not defeated and not fled and _has_character()


func _read_speed(source_character: CharacterEntity) -> int:
	if source_character.attributes.has("speed"):
		return max(1, int(source_character.attributes.get("speed", 1)))

	return max(1, int(source_character.attributes.get("agility", 1)))


func _has_character() -> bool:
	return character != null and is_instance_valid(character)


func _get_status_text() -> String:
	var labels: PackedStringArray = PackedStringArray()
	for status_value in status_effects.values():
		var status_data: Dictionary = status_value as Dictionary
		labels.append(str(status_data.get("display_name", status_data.get("id", ""))))

	var result: String = ""
	for index in range(labels.size()):
		if index > 0:
			result += ", "
		result += labels[index]

	return result


func _tick_skill_cooldowns() -> void:
	for skill_id_value in skill_cooldowns.keys().duplicate():
		var skill_id: String = str(skill_id_value)
		var remaining: int = int(skill_cooldowns.get(skill_id, 0)) - 1
		if remaining <= 0:
			skill_cooldowns.erase(skill_id)
		else:
			skill_cooldowns[skill_id] = remaining
