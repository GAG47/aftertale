class_name GameAction
extends RefCounted

var action_type: String = "Action"
var actor: CharacterEntity
var actor_id: String = ""
var target: Dictionary = {}
var context: Dictionary = {}


func configure(action_actor: CharacterEntity, action_target: Dictionary = {}, action_context: Dictionary = {}) -> void:
	actor = action_actor
	if actor != null and is_instance_valid(actor):
		actor_id = actor.character_id
	target = action_target.duplicate(true)
	context = action_context.duplicate(true)


func check() -> ActionResult:
	if actor == null or not is_instance_valid(actor):
		return _failure("Action has no actor.")

	return _success()


func execute() -> ActionResult:
	return _failure("%s has no execution rule." % action_type)


func _success() -> ActionResult:
	return ActionResult.succeeded(action_type, actor_id, target)


func _failure(reason: String) -> ActionResult:
	return ActionResult.failed(action_type, actor_id, reason, target)
