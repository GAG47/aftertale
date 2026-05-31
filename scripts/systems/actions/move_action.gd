class_name MoveAction
extends GameAction


func _init() -> void:
	action_type = "MoveAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var direction: Vector2i = target.get("direction", Vector2i.ZERO) as Vector2i
	if direction == Vector2i.ZERO:
		return _failure("MoveAction requires a non-zero direction.")

	var location_root: Node = _get_location_root()
	if location_root == null or not location_root.has_method("get_location_grid"):
		return _failure("MoveAction requires a location root with a grid.")

	var grid: LocationGrid = location_root.get_location_grid() as LocationGrid
	if grid == null:
		return _failure("MoveAction requires an active location grid.")

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var direction: Vector2i = target.get("direction", Vector2i.ZERO) as Vector2i
	var location_root: Node = _get_location_root()
	var grid: LocationGrid = location_root.get_location_grid() as LocationGrid
	var from_cell: Vector2i = actor.grid_position
	var target_cell: Vector2i = from_cell + direction
	var previous_facing: String = actor.facing

	actor.face_direction(direction)

	if not grid.can_enter(target_cell):
		var blocked_result: ActionResult = _success()
		blocked_result.add_world_change({
			"type": "character_faced_blocked_cell",
			"character_id": actor.character_id,
			"from": from_cell,
			"target": target_cell,
			"previous_facing": previous_facing,
			"facing": actor.facing,
			"location_id": grid.location_id,
		})
		blocked_result.add_feedback("%s faced %s but could not move." % [actor.display_name, actor.facing])
		return blocked_result

	var moved: bool = grid.move_character(actor.character_id, from_cell, target_cell, actor.blocks_movement)
	if not moved:
		return _failure("MoveAction failed while updating grid occupancy.")

	actor.set_grid_position(target_cell)

	var result: ActionResult = _success()
	result.add_world_change({
		"type": "character_moved",
		"character_id": actor.character_id,
		"from": from_cell,
		"to": target_cell,
		"location_id": grid.location_id,
	})
	result.add_feedback("%s moved to %s." % [actor.display_name, target_cell])

	var exit_data: Dictionary = grid.get_exit_at(target_cell)
	if not exit_data.is_empty():
		result.add_world_change({
			"type": "location_exit_requested",
			"character_id": actor.character_id,
			"from_location_id": grid.location_id,
			"exit_id": str(exit_data.get("id", "")),
			"target_scene_path": str(exit_data.get("target_scene_path", "")),
			"target_entrance_id": str(exit_data.get("target_entrance_id", "")),
		})
		result.add_feedback("%s left through %s." % [actor.display_name, str(exit_data.get("id", "an exit"))])

		if location_root.has_method("request_exit_transition"):
			location_root.request_exit_transition(exit_data)

	return result


func _get_location_root() -> Node:
	var root_value: Variant = context.get("location_root", null)
	if typeof(root_value) != TYPE_OBJECT or not is_instance_valid(root_value):
		return null

	return root_value as Node
