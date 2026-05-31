class_name TradeAction
extends GameAction


func _init() -> void:
	action_type = "TradeAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var shop_id: String = str(target.get("shop_id", ""))
	var trade_type: String = str(target.get("trade_type", ""))
	var item_id: String = str(target.get("item_id", ""))
	var quantity: int = int(target.get("quantity", 1))
	var failed_requirement: String = BusinessSystem.get_trade_failure(actor, shop_id, trade_type, item_id, quantity)
	if not failed_requirement.is_empty():
		return _failure(failed_requirement)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	return BusinessSystem.execute_trade(
		actor,
		str(target.get("shop_id", "")),
		str(target.get("trade_type", "")),
		str(target.get("item_id", "")),
		int(target.get("quantity", 1))
	)
