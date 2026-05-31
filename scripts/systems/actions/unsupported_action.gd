class_name UnsupportedAction
extends GameAction

var required_system: String = ""


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	return _failure("%s requires %s, which is not implemented yet." % [action_type, required_system])
