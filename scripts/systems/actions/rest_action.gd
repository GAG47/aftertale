class_name RestAction
extends GameAction


func _init() -> void:
	action_type = "RestAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var minutes: int = _resolve_minutes()
	if minutes <= 0:
		return _failure("休息时间必须大于 0。")

	var cost: int = max(0, int(target.get("cost", 0)))
	if cost > 0 and BusinessSystem.get_currency(actor.character_id) < cost:
		return _failure("需要 %d 金币。" % cost)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var minutes: int = _resolve_minutes()
	var cost: int = max(0, int(target.get("cost", 0)))
	var from_time: int = TimeManager.get_absolute_minutes()
	TimeManager.advance_minutes(minutes)
	var to_time: int = TimeManager.get_absolute_minutes()

	var result: ActionResult = _success()
	if cost > 0:
		BusinessSystem.add_currency(actor.character_id, -cost)
		result.add_world_change({
			"type": "rest_currency_spent",
			"actor_id": actor.character_id,
			"amount": cost,
		})

	var restored_entries: Array[Dictionary] = _restore_rest_targets()
	result.add_world_change({
		"type": "time_advanced",
		"actor_id": actor.character_id,
		"minutes": minutes,
		"from_absolute_minutes": from_time,
		"to_absolute_minutes": to_time,
		"day_period": TimeManager.day_period,
	})
	result.add_world_change({
		"type": "rest_completed",
		"actor_id": actor.character_id,
		"rest_type": str(target.get("rest_type", "wait")),
		"minutes": minutes,
		"cost": cost,
		"restored": restored_entries,
	})
	result.add_feedback(_build_feedback(minutes, cost, restored_entries))
	return result


func _resolve_minutes() -> int:
	var rest_type: String = str(target.get("rest_type", "wait"))
	if rest_type == "bed" or rest_type == "inn":
		var target_hour: int = clampi(int(target.get("target_hour", 6)), 0, 23)
		var target_minute: int = clampi(int(target.get("target_minute", 0)), 0, 59)
		var target_minute_of_day: int = target_hour * 60 + target_minute
		var next_day_target: int = TimeManager.day * TimeManager.MINUTES_PER_DAY + target_minute_of_day
		return max(1, next_day_target - TimeManager.get_absolute_minutes())

	return int(target.get("minutes", 60))


func _restore_rest_targets() -> Array[Dictionary]:
	var restored_entries: Array[Dictionary] = []
	var characters: Array[CharacterEntity] = _get_rest_characters()
	for character in characters:
		var before_hp: int = character.hp
		var restore_amount: int = _get_restore_amount(character)
		if restore_amount <= 0:
			continue

		character.set_combat_stats(character.hp + restore_amount, character.max_hp, false)
		var actual_restore: int = max(0, character.hp - before_hp)
		if actual_restore <= 0:
			continue

		GameState.save_character_runtime(character)
		PartySystem.refresh_member(character)
		restored_entries.append({
			"character_id": character.character_id,
			"display_name": character.display_name,
			"amount": actual_restore,
			"hp": character.hp,
			"max_hp": character.max_hp,
		})

	return restored_entries


func _get_rest_characters() -> Array[CharacterEntity]:
	var characters: Array[CharacterEntity] = []
	var target_scope: String = str(target.get("target_scope", "leader"))
	if target_scope != "party":
		characters.append(actor)
		return characters

	var location_root: Node = context.get("location_root", null) as Node
	var grid: LocationGrid = null
	if location_root != null and is_instance_valid(location_root) and location_root.has_method("get_location_grid"):
		grid = location_root.get_location_grid() as LocationGrid

	if grid != null:
		for member_id in PartySystem.get_member_ids():
			var character: CharacterEntity = grid.get_character_by_id(member_id)
			if character == null:
				continue
			characters.append(character)

	if characters.is_empty():
		characters.append(actor)

	return characters


func _get_restore_amount(character: CharacterEntity) -> int:
	if bool(target.get("full_restore", false)):
		return max(0, character.max_hp - character.hp)

	var fixed_amount: int = max(0, int(target.get("heal_amount", 0)))
	if fixed_amount > 0:
		return fixed_amount

	var ratio: float = max(0.0, float(target.get("heal_ratio", 0.0)))
	if ratio <= 0.0:
		return 0

	return max(1, int(ceil(float(character.max_hp) * ratio)))


func _build_feedback(minutes: int, cost: int, restored_entries: Array[Dictionary]) -> String:
	var rest_type: String = str(target.get("rest_type", "wait"))
	var label: String = _get_rest_label(rest_type)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s %s了 %d 分钟。" % [actor.display_name, label, minutes])
	if cost > 0:
		parts.append("花费 %d 金币。" % cost)
	if not restored_entries.is_empty():
		var restored_names: PackedStringArray = PackedStringArray()
		for entry in restored_entries:
			restored_names.append("%s +%d" % [str(entry.get("display_name", entry.get("character_id", ""))), int(entry.get("amount", 0))])
		parts.append("恢复：%s。" % "，".join(restored_names))
	return "".join(parts)


func _get_rest_label(rest_type: String) -> String:
	match rest_type:
		"bed":
			return "睡了一觉"
		"campfire":
			return "在篝火旁休息"
		"inn":
			return "在旅馆休息"
		_:
			return "休息"
