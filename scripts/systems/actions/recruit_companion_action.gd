class_name RecruitCompanionAction
extends GameAction


func _init() -> void:
	action_type = "RecruitCompanionAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var character: CharacterEntity = _resolve_target_character()
	var failure: String = PartySystem.can_recruit(character, actor)
	if not failure.is_empty():
		return _failure(failure)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	return PartySystem.recruit(_resolve_target_character(), actor)


func _resolve_target_character() -> CharacterEntity:
	var character_value: Variant = target.get("character", null)
	if typeof(character_value) == TYPE_OBJECT and is_instance_valid(character_value):
		return character_value as CharacterEntity

	var speaker_value: Variant = context.get("speaker", null)
	if typeof(speaker_value) == TYPE_OBJECT and is_instance_valid(speaker_value):
		return speaker_value as CharacterEntity

	var character_id: String = str(target.get("character_id", ""))
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
