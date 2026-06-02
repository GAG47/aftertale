extends Node

signal party_changed()
signal member_joined(character_id: String)
signal member_left(character_id: String)

const MAX_PARTY_SIZE := 5
const DEFAULT_LEADER_ID := "debug_player"

var leader_id: String = DEFAULT_LEADER_ID
var member_ids: Array[String] = [DEFAULT_LEADER_ID]
var member_summaries: Dictionary = {}
var member_sources: Dictionary = {}
var formation_slots: Dictionary = {}


func _ready() -> void:
	_ensure_leader()


func reset_party(new_leader_id: String = DEFAULT_LEADER_ID) -> void:
	leader_id = new_leader_id
	member_ids.clear()
	member_ids.append(leader_id)
	member_summaries.clear()
	member_sources.clear()
	formation_slots.clear()
	_assign_default_formations()
	party_changed.emit()


func can_recruit(character: CharacterEntity, recruiter: CharacterEntity = null) -> String:
	_ensure_leader()
	if character == null or not is_instance_valid(character):
		return "没有可邀请入队的角色。"

	var character_id: String = character.character_id
	if character_id.is_empty():
		return "这个角色缺少角色 ID。"
	if member_ids.has(character_id):
		return "%s 已经在队伍中。" % character.display_name
	if member_ids.size() >= MAX_PARTY_SIZE:
		return "当前队伍已满，无法邀请。"
	if recruiter != null and is_instance_valid(recruiter) and character_id == recruiter.character_id:
		return "不能邀请自己入队。"
	if character.character_kind == CharacterEntity.KIND_ENEMY:
		return "%s 现在不能加入队伍。" % character.display_name
	if not character.is_interactable:
		return "%s 现在不能加入队伍。" % character.display_name

	return ""


func recruit(character: CharacterEntity, recruiter: CharacterEntity = null) -> ActionResult:
	var failure: String = can_recruit(character, recruiter)
	var actor_id: String = recruiter.character_id if recruiter != null and is_instance_valid(recruiter) else leader_id
	if not failure.is_empty():
		return ActionResult.failed("RecruitCompanionAction", actor_id, failure, {
			"character_id": character.character_id if character != null and is_instance_valid(character) else "",
		})

	_ensure_leader()
	member_ids.append(character.character_id)
	member_summaries[character.character_id] = character.get_summary().duplicate(true)
	member_sources[character.character_id] = character.definition_source
	_assign_default_formations()
	GameState.save_character_runtime(character)

	var result: ActionResult = ActionResult.succeeded("RecruitCompanionAction", actor_id, {
		"character_id": character.character_id,
	})
	result.add_world_change({
		"type": "party_member_joined",
		"character_id": character.character_id,
		"display_name": character.display_name,
		"leader_id": leader_id,
	})
	result.add_feedback("%s 加入了队伍。" % character.display_name)
	member_joined.emit(character.character_id)
	party_changed.emit()
	return result


func remove_member(character_id: String) -> ActionResult:
	_ensure_leader()
	if character_id.is_empty():
		return ActionResult.failed("RemovePartyMember", leader_id, "离队需要角色 ID。")
	if character_id == leader_id:
		return ActionResult.failed("RemovePartyMember", leader_id, "队长不能离队。")
	if not member_ids.has(character_id):
		return ActionResult.failed("RemovePartyMember", leader_id, "该角色不在队伍中：%s" % character_id)

	_clear_player_equipment_overrides(character_id)

	_save_live_member_runtime(character_id)
	member_ids.erase(character_id)
	formation_slots.erase(character_id)
	_refresh_order_slots()
	var result: ActionResult = ActionResult.succeeded("RemovePartyMember", leader_id, {
		"character_id": character_id,
	})
	result.add_world_change({
		"type": "party_member_left",
		"character_id": character_id,
		"leader_id": leader_id,
	})
	result.add_feedback("%s 离开了当前队伍，玩家装备覆盖已解除，默认配置已恢复。" % _get_member_display_name(character_id))
	member_left.emit(character_id)
	party_changed.emit()
	return result


func can_reorder_member(character_id: String) -> bool:
	_ensure_leader()
	if character_id.is_empty() or character_id == leader_id:
		return false
	return member_ids.has(character_id)


func move_member_up(character_id: String) -> ActionResult:
	return move_member_to_index(character_id, get_member_order_index(character_id) - 1)


func move_member_down(character_id: String) -> ActionResult:
	return move_member_to_index(character_id, get_member_order_index(character_id) + 1)


func move_member_to_index(character_id: String, target_index: int) -> ActionResult:
	_ensure_leader()
	if character_id.is_empty():
		return ActionResult.failed("ReorderPartyMember", leader_id, "调整队伍顺序需要角色 ID。")
	if character_id == leader_id:
		return ActionResult.failed("ReorderPartyMember", leader_id, "队长固定在队伍首位。")

	var current_index: int = member_ids.find(character_id)
	if current_index < 0:
		return ActionResult.failed("ReorderPartyMember", leader_id, "该角色不在队伍中：%s" % character_id)

	var clamped_index: int = clampi(target_index, 1, member_ids.size() - 1)
	if clamped_index == current_index:
		return ActionResult.succeeded("ReorderPartyMember", leader_id, {
			"character_id": character_id,
			"from_index": current_index,
			"to_index": current_index,
		})

	member_ids.remove_at(current_index)
	member_ids.insert(clamped_index, character_id)
	_refresh_order_slots()

	var result: ActionResult = ActionResult.succeeded("ReorderPartyMember", leader_id, {
		"character_id": character_id,
		"from_index": current_index,
		"to_index": clamped_index,
	})
	result.add_world_change({
		"type": "party_order_changed",
		"character_id": character_id,
		"leader_id": leader_id,
		"from_index": current_index,
		"to_index": clamped_index,
		"member_ids": member_ids.duplicate(),
	})
	result.add_feedback("%s 的队伍顺序已调整。" % _get_member_display_name(character_id))
	party_changed.emit()
	return result


func is_member(character_id: String) -> bool:
	_ensure_leader()
	return member_ids.has(character_id)


func get_member_order_index(character_id: String) -> int:
	_ensure_leader()
	return member_ids.find(character_id)


func get_member_order_rank(character_id: String) -> int:
	var index: int = get_member_order_index(character_id)
	return index if index >= 0 else 999


func get_member_ids() -> Array[String]:
	_ensure_leader()
	return member_ids.duplicate()


func get_companion_ids() -> Array[String]:
	_ensure_leader()
	var result: Array[String] = []
	for member_id in member_ids:
		if member_id == leader_id:
			continue
		result.append(member_id)
	return result


func get_member_source(character_id: String) -> String:
	return str(member_sources.get(character_id, ""))


func get_formation_offset(character_id: String, leader_facing: String = CharacterEntity.FACING_DOWN) -> Vector2i:
	_assign_default_formations()
	var slot_index: int = int(formation_slots.get(character_id, 0))
	if slot_index <= 0:
		return Vector2i.ZERO

	var base_offsets: Array[Vector2i] = [
		Vector2i(0, 1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
		Vector2i(0, 2),
	]
	var local_offset: Vector2i = base_offsets[(slot_index - 1) % base_offsets.size()]
	return _rotate_offset_for_facing(local_offset, leader_facing)


func get_party_summary() -> Array[Dictionary]:
	_ensure_leader()
	_refresh_live_member_summaries()
	var result: Array[Dictionary] = []
	for member_id in member_ids:
		var summary: Dictionary = member_summaries.get(member_id, {}) as Dictionary
		if summary.is_empty():
			summary = _build_missing_summary(member_id)
		summary = summary.duplicate(true)
		summary["party_member_id"] = member_id
		summary["is_party_leader"] = member_id == leader_id
		summary["party_order"] = get_member_order_rank(member_id)
		summary["follow_order"] = get_member_order_rank(member_id)
		summary["battle_priority"] = get_member_order_rank(member_id)
		result.append(summary)
	return result


func get_member_summary(character_id: String) -> Dictionary:
	_refresh_live_member_summaries()
	if member_summaries.has(character_id):
		return (member_summaries.get(character_id, {}) as Dictionary).duplicate(true)
	return _build_missing_summary(character_id)


func get_battle_members(location_root: Node, initiator: CharacterEntity = null) -> Array[CharacterEntity]:
	_ensure_leader()
	var result: Array[CharacterEntity] = []
	var grid: LocationGrid = _get_grid_from_location(location_root)
	if grid == null:
		return result

	var initiator_id: String = initiator.character_id if initiator != null and is_instance_valid(initiator) else ""
	if not initiator_id.is_empty() and member_ids.has(initiator_id):
		var live_initiator: CharacterEntity = grid.get_character_by_id(initiator_id)
		if live_initiator != null:
			result.append(live_initiator)
			refresh_member(live_initiator)

	for member_id in member_ids:
		if member_id == initiator_id:
			continue
		var character: CharacterEntity = grid.get_character_by_id(member_id)
		if character == null:
			continue
		result.append(character)
		refresh_member(character)

	return result


func refresh_member(character: CharacterEntity) -> void:
	if character == null or not is_instance_valid(character):
		return
	if not is_member(character.character_id):
		return
	member_summaries[character.character_id] = character.get_summary().duplicate(true)


func get_save_state() -> Dictionary:
	_ensure_leader()
	_refresh_live_member_summaries()
	return {
		"leader_id": leader_id,
		"member_ids": member_ids.duplicate(),
		"member_summaries": member_summaries.duplicate(true),
		"member_sources": member_sources.duplicate(true),
		"formation_slots": formation_slots.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	leader_id = str(state.get("leader_id", DEFAULT_LEADER_ID))
	member_ids.clear()
	var saved_member_ids: Array = state.get("member_ids", [leader_id]) as Array
	for value in saved_member_ids:
		var member_id: String = str(value)
		if member_id.is_empty() or member_ids.has(member_id):
			continue
		member_ids.append(member_id)
	member_summaries = (state.get("member_summaries", {}) as Dictionary).duplicate(true)
	member_sources = (state.get("member_sources", {}) as Dictionary).duplicate(true)
	formation_slots = (state.get("formation_slots", {}) as Dictionary).duplicate(true)
	_ensure_leader()
	_refresh_order_slots()
	party_changed.emit()


func _ensure_leader() -> void:
	if leader_id.is_empty():
		leader_id = DEFAULT_LEADER_ID
	if not member_ids.has(leader_id):
		member_ids.insert(0, leader_id)
	if not formation_slots.has(leader_id):
		formation_slots[leader_id] = 0


func _refresh_live_member_summaries() -> void:
	if SceneLoader.current_scene == null or not is_instance_valid(SceneLoader.current_scene):
		return
	if not SceneLoader.current_scene.has_method("get_location_grid"):
		return
	var grid: LocationGrid = SceneLoader.current_scene.get_location_grid() as LocationGrid
	if grid == null:
		return

	for member_id in member_ids:
		var character: CharacterEntity = grid.get_character_by_id(member_id)
		if character != null:
			member_summaries[member_id] = character.get_summary().duplicate(true)
			if not character.definition_source.is_empty():
				member_sources[member_id] = character.definition_source


func _save_live_member_runtime(character_id: String) -> void:
	var character: CharacterEntity = _get_live_member(character_id)
	if character == null:
		return
	refresh_member(character)
	GameState.save_character_runtime(character)


func _clear_player_equipment_overrides(character_id: String) -> void:
	var character: CharacterEntity = _get_live_member(character_id)
	if character == null or character.equipment_slots == null:
		return

	var items: Array[Dictionary] = character.equipment_slots.get_player_override_items()
	if items.is_empty():
		return

	character.equipment_slots.take_player_override_items()

	refresh_member(character)


func _get_live_member(character_id: String) -> CharacterEntity:
	if character_id.is_empty():
		return null
	if SceneLoader.current_scene == null or not is_instance_valid(SceneLoader.current_scene):
		return null
	if not SceneLoader.current_scene.has_method("get_location_grid"):
		return null
	var grid: LocationGrid = SceneLoader.current_scene.get_location_grid() as LocationGrid
	if grid == null:
		return null
	return grid.get_character_by_id(character_id)


func _get_grid_from_location(location_root: Node) -> LocationGrid:
	if location_root == null or not is_instance_valid(location_root):
		return null
	if not location_root.has_method("get_location_grid"):
		return null
	return location_root.get_location_grid() as LocationGrid


func _assign_default_formations() -> void:
	if leader_id.is_empty():
		leader_id = DEFAULT_LEADER_ID
	if not member_ids.has(leader_id):
		member_ids.insert(0, leader_id)
	_refresh_order_slots()


func _refresh_order_slots() -> void:
	formation_slots.clear()
	var slot_index: int = 1
	for member_id in member_ids:
		if member_id == leader_id:
			formation_slots[member_id] = 0
			continue
		formation_slots[member_id] = slot_index
		slot_index += 1


func _rotate_offset_for_facing(offset: Vector2i, facing: String) -> Vector2i:
	match facing:
		CharacterEntity.FACING_UP:
			return Vector2i(offset.x, offset.y)
		CharacterEntity.FACING_DOWN:
			return Vector2i(-offset.x, -offset.y)
		CharacterEntity.FACING_LEFT:
			return Vector2i(offset.y, -offset.x)
		CharacterEntity.FACING_RIGHT:
			return Vector2i(-offset.y, offset.x)
		_:
			return offset


func _build_missing_summary(character_id: String) -> Dictionary:
	return {
		"id": character_id,
		"display_name": character_id,
		"kind": "companion" if character_id != leader_id else "player",
		"attributes": { "level": 1 },
		"effective_attributes": { "level": 1 },
		"identity": {},
		"skills": [],
		"equipment_slots": {},
		"hp": 0,
		"max_hp": 1,
	}


func _get_member_display_name(character_id: String) -> String:
	var summary: Dictionary = member_summaries.get(character_id, {}) as Dictionary
	return str(summary.get("display_name", character_id))
