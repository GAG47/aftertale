class_name TalkAction
extends GameAction


func _init() -> void:
	action_type = "TalkAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var speaker: CharacterEntity = _get_speaker()
	if speaker == null:
		return _failure("对话需要指定说话对象。")

	if not speaker.is_interactable:
		return _failure("%s 不能互动。" % speaker.display_name)

	if speaker.dialogue_source.is_empty():
		return _failure("%s 没有对话资源。" % speaker.display_name)

	var location_root: Node = _get_location_root()
	if location_root == null or not location_root.has_method("get_location_grid"):
		return _failure("对话需要有效的当前地点。")

	var distance: int = abs(actor.grid_position.x - speaker.grid_position.x) + abs(actor.grid_position.y - speaker.grid_position.y)
	if distance > 1:
		return _failure("%s 离得太远了。" % speaker.display_name)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var speaker: CharacterEntity = _get_speaker()
	return DialogueRunner.start_dialogue(actor, speaker, speaker.dialogue_source)


func _get_speaker() -> CharacterEntity:
	var speaker_value: Variant = target.get("speaker", null)
	if typeof(speaker_value) != TYPE_OBJECT or not is_instance_valid(speaker_value):
		return null

	return speaker_value as CharacterEntity


func _get_location_root() -> Node:
	var root_value: Variant = context.get("location_root", null)
	if typeof(root_value) != TYPE_OBJECT or not is_instance_valid(root_value):
		return null

	return root_value as Node
