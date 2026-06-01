extends Node

signal shops_loaded(count: int)
signal currency_changed(character_id: String, amount: int)
signal trade_completed(character_id: String, shop_id: String, trade_type: String)

const SHOP_PATHS = [
	"res://data/shops/field_stall.json",
]

var shop_definitions: Dictionary = {}
var wallets: Dictionary = {}


func _ready() -> void:
	_load_shop_definitions()
	GameState.session_started.connect(_on_session_started)


func get_currency(character_id: String) -> int:
	if character_id.is_empty():
		return 0

	return int(wallets.get(character_id, 0))


func set_currency(character_id: String, amount: int) -> void:
	if character_id.is_empty():
		return

	wallets[character_id] = max(0, amount)
	currency_changed.emit(character_id, int(wallets[character_id]))


func add_currency(character_id: String, amount: int) -> void:
	if character_id.is_empty() or amount == 0:
		return

	set_currency(character_id, get_currency(character_id) + amount)


func get_shop(shop_id: String) -> Dictionary:
	if shop_id.is_empty() or not shop_definitions.has(shop_id):
		return {}

	var shop: Dictionary = shop_definitions[shop_id] as Dictionary
	return shop.duplicate(true)


func get_default_shop_id() -> String:
	if shop_definitions.has("field_stall"):
		return "field_stall"

	for key in shop_definitions.keys():
		return str(key)

	return ""


func get_market_summary(actor: CharacterEntity, shop_id: String = "") -> Dictionary:
	var resolved_shop_id: String = shop_id
	if resolved_shop_id.is_empty():
		resolved_shop_id = get_default_shop_id()

	var shop: Dictionary = get_shop(resolved_shop_id)
	if shop.is_empty():
		return {
			"shop_id": resolved_shop_id,
			"display_name": "没有市场",
			"currency": _actor_currency(actor),
			"sell_offers": [],
			"buy_offers": [],
		}

	return {
		"shop_id": resolved_shop_id,
		"display_name": str(shop.get("display_name", resolved_shop_id)),
		"description": str(shop.get("description", "")),
		"currency": _actor_currency(actor),
		"sell_offers": get_sell_offers(actor, resolved_shop_id),
		"buy_offers": get_buy_offers(actor, resolved_shop_id),
	}


func get_sell_offers(actor: CharacterEntity, shop_id: String = "") -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if actor == null or not is_instance_valid(actor) or actor.inventory == null:
		return offers

	var shop: Dictionary = _resolve_shop(shop_id)
	if shop.is_empty():
		return offers

	var accepted_prices: Dictionary = _get_sell_price_table(shop)
	for stack_value in actor.inventory.stacks:
		var stack: ItemStack = stack_value as ItemStack
		if stack == null:
			continue

		var item_id: String = stack.item_id
		if item_id.is_empty() or not accepted_prices.has(item_id):
			continue
		if not bool(stack.definition.get("sellable", true)):
			continue

		var price: int = int(accepted_prices[item_id])
		if price <= 0:
			continue

		offers.append({
			"item_id": item_id,
			"display_name": stack.display_name,
			"quantity": stack.quantity,
			"price": price,
			"total_value": price * stack.quantity,
			"can_sell": true,
			"failure_reason": "",
		})

	return offers


func get_buy_offers(actor: CharacterEntity, shop_id: String = "") -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var shop: Dictionary = _resolve_shop(shop_id)
	if shop.is_empty():
		return offers

	var buy_rows: Array = shop.get("buy_offers", []) as Array
	for offer_value in buy_rows:
		var offer: Dictionary = offer_value as Dictionary
		var item_definition: Dictionary = _load_offer_item_definition(offer)
		if item_definition.is_empty():
			continue

		var price: int = max(1, int(offer.get("price", item_definition.get("base_value", 1))))
		var failure_reason: String = get_trade_failure(actor, str(shop.get("id", "")), "buy", str(item_definition.get("id", "")), 1)
		offers.append({
			"item_id": str(item_definition.get("id", "")),
			"display_name": str(item_definition.get("display_name", item_definition.get("id", "Unknown Item"))),
			"description": str(item_definition.get("description", "")),
			"price": price,
			"can_buy": failure_reason.is_empty(),
			"failure_reason": failure_reason,
		})

	return offers


func get_trade_failure(actor: CharacterEntity, shop_id: String, trade_type: String, item_id: String, quantity: int) -> String:
	if actor == null or not is_instance_valid(actor):
		return "交易需要有效的角色。"
	if actor.inventory == null:
		return "%s 没有背包。" % actor.display_name

	var shop: Dictionary = _resolve_shop(shop_id)
	if shop.is_empty():
		return "未知商店。"

	if item_id.is_empty():
		return "交易需要指定物品。"
	if quantity <= 0:
		return "交易数量必须大于 0。"

	match trade_type:
		"sell":
			return _get_sell_failure(actor, shop, item_id, quantity)
		"buy":
			return _get_buy_failure(actor, shop, item_id, quantity)
		_:
			return "未知交易类型：%s" % trade_type


func execute_trade(actor: CharacterEntity, shop_id: String, trade_type: String, item_id: String, quantity: int) -> ActionResult:
	var resolved_shop: Dictionary = _resolve_shop(shop_id)
	var resolved_shop_id: String = str(resolved_shop.get("id", shop_id))
	var failed_requirement: String = get_trade_failure(actor, resolved_shop_id, trade_type, item_id, quantity)
	if not failed_requirement.is_empty():
		return ActionResult.failed("TradeAction", _actor_id(actor), failed_requirement, {
			"shop_id": resolved_shop_id,
			"trade_type": trade_type,
			"item_id": item_id,
			"quantity": quantity,
		})

	match trade_type:
		"sell":
			return _execute_sell(actor, resolved_shop, item_id, quantity)
		"buy":
			return _execute_buy(actor, resolved_shop, item_id, quantity)

	return ActionResult.failed("TradeAction", _actor_id(actor), "未知交易类型：%s" % trade_type, {})


func get_save_state() -> Dictionary:
	return {
		"wallets": wallets.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	wallets = (state.get("wallets", {}) as Dictionary).duplicate(true)


func _execute_sell(actor: CharacterEntity, shop: Dictionary, item_id: String, quantity: int) -> ActionResult:
	var shop_id: String = str(shop.get("id", ""))
	var sell_price_table: Dictionary = _get_sell_price_table(shop)
	var unit_price: int = int(sell_price_table.get(item_id, 0))
	var payout: int = unit_price * quantity
	var item_name: String = _get_inventory_item_name(actor, item_id)

	actor.inventory.remove_item(item_id, quantity)
	GameState.save_character_runtime(actor)
	add_currency(actor.character_id, payout)

	var result: ActionResult = ActionResult.succeeded("TradeAction", actor.character_id, {
		"shop_id": shop_id,
		"trade_type": "sell",
		"item_id": item_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"currency_delta": payout,
	})
	result.add_world_change({
		"type": "item_sold",
		"character_id": actor.character_id,
		"shop_id": shop_id,
		"item_id": item_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"currency_delta": payout,
	})
	result.add_feedback("%s 出售了 %d 个 %s，获得 %d 金币。" % [actor.display_name, quantity, item_name, payout])
	trade_completed.emit(actor.character_id, shop_id, "sell")
	return result


func _execute_buy(actor: CharacterEntity, shop: Dictionary, item_id: String, quantity: int) -> ActionResult:
	var shop_id: String = str(shop.get("id", ""))
	var offer: Dictionary = _get_buy_offer(shop, item_id)
	var item_definition: Dictionary = _load_offer_item_definition(offer)
	var unit_price: int = max(1, int(offer.get("price", item_definition.get("base_value", 1))))
	var cost: int = unit_price * quantity
	var item_name: String = str(item_definition.get("display_name", item_id))

	add_currency(actor.character_id, -cost)
	actor.inventory.add_item(item_definition, quantity)
	GameState.save_character_runtime(actor)

	var result: ActionResult = ActionResult.succeeded("TradeAction", actor.character_id, {
		"shop_id": shop_id,
		"trade_type": "buy",
		"item_id": item_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"currency_delta": -cost,
	})
	result.add_world_change({
		"type": "item_bought",
		"character_id": actor.character_id,
		"shop_id": shop_id,
		"item_id": item_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"currency_delta": -cost,
	})
	result.add_feedback("%s 购买了 %d 个 %s，花费 %d 金币。" % [actor.display_name, quantity, item_name, cost])
	trade_completed.emit(actor.character_id, shop_id, "buy")
	return result


func _get_sell_failure(actor: CharacterEntity, shop: Dictionary, item_id: String, quantity: int) -> String:
	var sell_price_table: Dictionary = _get_sell_price_table(shop)
	if not sell_price_table.has(item_id):
		return "这家商店不收购 %s。" % item_id
	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	if stack == null:
		return "%s 没有足够的 %s。" % [actor.display_name, item_id]
	if not bool(stack.definition.get("sellable", true)):
		return "%s 不能出售。" % stack.display_name
	if actor.inventory.count_item(item_id) < quantity:
		return "%s 没有足够的 %s。" % [actor.display_name, item_id]

	return ""


func _get_buy_failure(actor: CharacterEntity, shop: Dictionary, item_id: String, quantity: int) -> String:
	var offer: Dictionary = _get_buy_offer(shop, item_id)
	if offer.is_empty():
		return "这家商店不出售 %s。" % item_id

	var item_definition: Dictionary = _load_offer_item_definition(offer)
	if item_definition.is_empty():
		return "无法加载商店物品：%s" % item_id

	var unit_price: int = max(1, int(offer.get("price", item_definition.get("base_value", 1))))
	var cost: int = unit_price * quantity
	if get_currency(actor.character_id) < cost:
		return "需要 %d 金币。" % cost
	if not actor.inventory.can_add_item(item_definition, quantity):
		return "%s 装不下这次购买的物品。" % actor.display_name

	return ""


func _get_sell_price_table(shop: Dictionary) -> Dictionary:
	var table: Dictionary = {}
	var sell_rows: Array = shop.get("sell_offers", []) as Array
	for offer_value in sell_rows:
		var offer: Dictionary = offer_value as Dictionary
		var item_id: String = str(offer.get("item_id", ""))
		var price: int = int(offer.get("price", 0))
		if item_id.is_empty() or price <= 0:
			continue
		table[item_id] = price

	return table


func _get_buy_offer(shop: Dictionary, item_id: String) -> Dictionary:
	var buy_rows: Array = shop.get("buy_offers", []) as Array
	for offer_value in buy_rows:
		var offer: Dictionary = offer_value as Dictionary
		var offer_item_id: String = str(offer.get("item_id", ""))
		if offer_item_id == item_id:
			return offer.duplicate(true)

	return {}


func _load_offer_item_definition(offer: Dictionary) -> Dictionary:
	var source_path: String = str(offer.get("source", ""))
	if source_path.is_empty():
		return {}

	return DefinitionLoader.load_item(source_path)


func _resolve_shop(shop_id: String) -> Dictionary:
	var resolved_shop_id: String = shop_id
	if resolved_shop_id.is_empty():
		resolved_shop_id = get_default_shop_id()

	return get_shop(resolved_shop_id)


func _get_inventory_item_name(actor: CharacterEntity, item_id: String) -> String:
	if actor == null or not is_instance_valid(actor) or actor.inventory == null:
		return item_id

	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	if stack == null:
		return item_id

	return stack.display_name


func _actor_currency(actor: CharacterEntity) -> int:
	if actor == null or not is_instance_valid(actor):
		return 0

	return get_currency(actor.character_id)


func _actor_id(actor: CharacterEntity) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""

	return actor.character_id


func _load_shop_definitions() -> void:
	shop_definitions.clear()
	for shop_path in SHOP_PATHS:
		var shop: Dictionary = DefinitionLoader.load_shop(shop_path)
		if shop.is_empty():
			continue

		var shop_id: String = str(shop.get("id", ""))
		if shop_id.is_empty():
			push_error("BusinessSystem shop has no id: %s" % shop_path)
			continue

		shop_definitions[shop_id] = shop

	shops_loaded.emit(shop_definitions.size())


func _on_session_started(_session_id: String) -> void:
	wallets.clear()
