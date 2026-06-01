class_name RestAction
extends GameAction


func _init() -> void:
	action_type = "RestAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var minutes: int = int(target.get("minutes", 60))
	if minutes <= 0:
		return _failure("休息时间必须大于 0。")

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var minutes: int = int(target.get("minutes", 60))
	var from_time: int = TimeManager.get_absolute_minutes()
	TimeManager.advance_minutes(minutes)
	var to_time: int = TimeManager.get_absolute_minutes()

	var result: ActionResult = _success()
	result.add_world_change({
		"type": "time_advanced",
		"actor_id": actor.character_id,
		"minutes": minutes,
		"from_absolute_minutes": from_time,
		"to_absolute_minutes": to_time,
		"day_period": TimeManager.day_period,
	})
	result.add_feedback("%s 休息了 %d 分钟。" % [actor.display_name, minutes])
	return result
