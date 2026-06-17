extends Node

signal shops_loaded(count: int)
signal currency_changed(character_id: String, amount: int)
signal trade_completed(character_id: String, shop_id: String, trade_type: String)

const SHOP_PATHS = [
	"res://data/shops/field_stall.json",
]

var shop_definitions: Dictionary = {}
var wallets: Dictionary = {}
var restocked_days: Dictionary = {}


func _ready() -> void:
	_load_shop_definitions()
	GameState.session_started.connect(_on_session_started)
	TimeManager.day_changed.connect(_on_day_changed)


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
		if shop_id.begins_with("generated_shop_") and shop_definitions.has("field_stall"):
			var generated_shop: Dictionary = (shop_definitions["field_stall"] as Dictionary).duplicate(true)
			generated_shop["id"] = shop_id
			generated_shop["display_name"] = "Generated Shop"
			return generated_shop
		return {}

	var shop: Dictionary = shop_definitions[shop_id] as Dictionary
	return shop.duplicate(true)


func get_default_shop_id() -> String:
	if shop_definitions.has("field_stall"):
		return "field_stall"

	for key in shop_definitions.keys():
		return str(key)

	return ""


func get_market_summary(actor: CharacterEntity, shop_id: String = "", vendor_id: String = "") -> Dictionary:
	var resolved_shop_id: String = shop_id
	if resolved_shop_id.is_empty():
		resolved_shop_id = get_default_shop_id()

	var shop: Dictionary = get_shop(resolved_shop_id)
	if shop.is_empty():
		return {
			"shop_id": resolved_shop_id,
			"display_name": "没有市场",
			"description": "",
			"currency": _actor_currency(actor),
			"vendor_id": "",
			"vendor_name": "",
			"vendor_currency": 0,
			"sell_offers": [],
			"buy_offers": [],
		}

	_restock_shop_for_current_day(shop)
	var vendor: CharacterEntity = _resolve_vendor(shop, vendor_id)
	var resolved_vendor_id: String = _resolve_vendor_id(shop, vendor_id)
	return {
		"shop_id": resolved_shop_id,
		"display_name": str(shop.get("display_name", resolved_shop_id)),
		"description": str(shop.get("description", "")),
		"currency": _actor_currency(actor),
		"vendor_id": resolved_vendor_id,
		"vendor_name": vendor.display_name if vendor != null else resolved_vendor_id,
		"vendor_currency": get_currency(resolved_vendor_id),
		"sell_offers": get_sell_offers(actor, resolved_shop_id, resolved_vendor_id),
		"buy_offers": get_buy_offers(actor, resolved_shop_id, resolved_vendor_id),
	}


func get_sell_offers(actor: CharacterEntity, shop_id: String = "", vendor_id: String = "") -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if actor == null or not is_instance_valid(actor) or actor.inventory == null:
		return offers

	var shop: Dictionary = _resolve_shop(shop_id)
	if shop.is_empty():
		return offers

	_restock_shop_for_current_day(shop)
	var vendor: CharacterEntity = _resolve_vendor(shop, vendor_id)
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

		var failure_reason: String = get_trade_failure(actor, str(shop.get("id", "")), "sell", item_id, 1, vendor_id)
		offers.append({
			"item_id": item_id,
			"display_name": stack.display_name,
			"description": str(stack.definition.get("description", "")),
			"item_type": str(stack.definition.get("item_type", "")),
			"quantity": stack.quantity,
			"price": price,
			"total_value": price * stack.quantity,
			"vendor_currency": get_currency(vendor.character_id) if vendor != null else 0,
			"can_sell": failure_reason.is_empty(),
			"failure_reason": failure_reason,
		})

	return offers


func get_buy_offers(actor: CharacterEntity, shop_id: String = "", vendor_id: String = "") -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var shop: Dictionary = _resolve_shop(shop_id)
	if shop.is_empty():
		return offers

	_restock_shop_for_current_day(shop)
	var vendor: CharacterEntity = _resolve_vendor(shop, vendor_id)
	var buy_rows: Array = shop.get("buy_offers", []) as Array
	for offer_value in buy_rows:
		var offer: Dictionary = offer_value as Dictionary
		var item_definition: Dictionary = _load_offer_item_definition(offer)
		if item_definition.is_empty() and vendor != null:
			item_definition = _get_inventory_item_definition(vendor, str(offer.get("item_id", "")))
		if item_definition.is_empty():
			continue

		var item_id: String = str(item_definition.get("id", offer.get("item_id", "")))
		var price: int = max(1, int(offer.get("price", item_definition.get("base_value", 1))))
		var stock: int = vendor.inventory.count_item(item_id) if vendor != null and vendor.inventory != null else 0
		var failure_reason: String = get_trade_failure(actor, str(shop.get("id", "")), "buy", item_id, 1, vendor_id)
		offers.append({
			"item_id": item_id,
			"display_name": str(item_definition.get("display_name", item_id)),
			"description": str(item_definition.get("description", "")),
			"item_type": str(item_definition.get("item_type", "")),
			"price": price,
			"stock": stock,
			"owned_quantity": actor.inventory.count_item(item_id) if actor != null and actor.inventory != null else 0,
			"can_buy": failure_reason.is_empty(),
			"failure_reason": failure_reason,
		})

	return offers


func get_trade_failure(actor: CharacterEntity, shop_id: String, trade_type: String, item_id: String, quantity: int, vendor_id: String = "") -> String:
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

	var vendor: CharacterEntity = _resolve_vendor(shop, vendor_id)
	if vendor == null or not is_instance_valid(vendor) or vendor.inventory == null:
		return "商店没有可交易的 NPC 库存。"

	match trade_type:
		"sell":
			return _get_sell_failure(actor, vendor, shop, item_id, quantity)
		"buy":
			return _get_buy_failure(actor, vendor, shop, item_id, quantity)
		_:
			return "未知交易类型：%s" % trade_type


func execute_trade(actor: CharacterEntity, shop_id: String, trade_type: String, item_id: String, quantity: int, vendor_id: String = "") -> ActionResult:
	var resolved_shop: Dictionary = _resolve_shop(shop_id)
	var resolved_shop_id: String = str(resolved_shop.get("id", shop_id))
	var failed_requirement: String = get_trade_failure(actor, resolved_shop_id, trade_type, item_id, quantity, vendor_id)
	if not failed_requirement.is_empty():
		return ActionResult.failed("TradeAction", _actor_id(actor), failed_requirement, {
			"shop_id": resolved_shop_id,
			"vendor_id": _resolve_vendor_id(resolved_shop, vendor_id),
			"trade_type": trade_type,
			"item_id": item_id,
			"quantity": quantity,
		})

	var vendor: CharacterEntity = _resolve_vendor(resolved_shop, vendor_id)
	match trade_type:
		"sell":
			return _execute_sell(actor, vendor, resolved_shop, item_id, quantity)
		"buy":
			return _execute_buy(actor, vendor, resolved_shop, item_id, quantity)

	return ActionResult.failed("TradeAction", _actor_id(actor), "未知交易类型：%s" % trade_type, {})


func get_save_state() -> Dictionary:
	return {
		"wallets": wallets.duplicate(true),
		"restocked_days": restocked_days.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	wallets = (state.get("wallets", {}) as Dictionary).duplicate(true)
	restocked_days = (state.get("restocked_days", {}) as Dictionary).duplicate(true)


func _execute_sell(actor: CharacterEntity, vendor: CharacterEntity, shop: Dictionary, item_id: String, quantity: int) -> ActionResult:
	var shop_id: String = str(shop.get("id", ""))
	var sell_price_table: Dictionary = _get_sell_price_table(shop)
	var unit_price: int = int(sell_price_table.get(item_id, 0))
	var payout: int = unit_price * quantity
	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	var item_definition: Dictionary = stack.definition.duplicate(true) if stack != null else {}
	var item_name: String = stack.display_name if stack != null else item_id

	actor.inventory.remove_item(item_id, quantity)
	vendor.inventory.add_item(item_definition, quantity)
	add_currency(actor.character_id, payout)
	add_currency(vendor.character_id, -payout)
	GameState.save_character_runtime(actor)
	GameState.save_character_runtime(vendor)

	var result: ActionResult = ActionResult.succeeded("TradeAction", actor.character_id, {
		"shop_id": shop_id,
		"vendor_id": vendor.character_id,
		"trade_type": "sell",
		"item_id": item_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"currency_delta": payout,
	})
	result.add_world_change({
		"type": "item_sold",
		"character_id": actor.character_id,
		"vendor_id": vendor.character_id,
		"shop_id": shop_id,
		"item_id": item_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"currency_delta": payout,
	})
	result.add_feedback("%s 出售了 %d 个 %s，获得 %d 金币。" % [actor.display_name, quantity, item_name, payout])
	trade_completed.emit(actor.character_id, shop_id, "sell")
	return result


func _execute_buy(actor: CharacterEntity, vendor: CharacterEntity, shop: Dictionary, item_id: String, quantity: int) -> ActionResult:
	var shop_id: String = str(shop.get("id", ""))
	var offer: Dictionary = _get_buy_offer(shop, item_id)
	var item_definition: Dictionary = _get_inventory_item_definition(vendor, item_id)
	if item_definition.is_empty():
		item_definition = _load_offer_item_definition(offer)

	var unit_price: int = max(1, int(offer.get("price", item_definition.get("base_value", 1))))
	var cost: int = unit_price * quantity
	var item_name: String = str(item_definition.get("display_name", item_id))

	vendor.inventory.remove_item(item_id, quantity)
	actor.inventory.add_item(item_definition, quantity)
	add_currency(actor.character_id, -cost)
	add_currency(vendor.character_id, cost)
	GameState.save_character_runtime(actor)
	GameState.save_character_runtime(vendor)

	var result: ActionResult = ActionResult.succeeded("TradeAction", actor.character_id, {
		"shop_id": shop_id,
		"vendor_id": vendor.character_id,
		"trade_type": "buy",
		"item_id": item_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"currency_delta": -cost,
	})
	result.add_world_change({
		"type": "item_bought",
		"character_id": actor.character_id,
		"vendor_id": vendor.character_id,
		"shop_id": shop_id,
		"item_id": item_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"currency_delta": -cost,
	})
	result.add_feedback("%s 购买了 %d 个 %s，花费 %d 金币。" % [actor.display_name, quantity, item_name, cost])
	trade_completed.emit(actor.character_id, shop_id, "buy")
	return result


func _get_sell_failure(actor: CharacterEntity, vendor: CharacterEntity, shop: Dictionary, item_id: String, quantity: int) -> String:
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

	var payout: int = int(sell_price_table[item_id]) * quantity
	if get_currency(vendor.character_id) < payout:
		return "%s 的金币不足。" % vendor.display_name
	if not vendor.inventory.can_add_item(stack.definition, quantity):
		return "%s 装不下这些物品。" % vendor.display_name

	return ""


func _get_buy_failure(actor: CharacterEntity, vendor: CharacterEntity, shop: Dictionary, item_id: String, quantity: int) -> String:
	var offer: Dictionary = _get_buy_offer(shop, item_id)
	if offer.is_empty():
		return "这家商店不出售 %s。" % item_id

	var item_definition: Dictionary = _get_inventory_item_definition(vendor, item_id)
	if item_definition.is_empty():
		item_definition = _load_offer_item_definition(offer)
	if item_definition.is_empty():
		return "无法加载商店物品：%s" % item_id

	if vendor.inventory.count_item(item_id) < quantity:
		return "库存不足。"

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


func _resolve_vendor(shop: Dictionary, vendor_id: String = "") -> CharacterEntity:
	var resolved_vendor_id: String = _resolve_vendor_id(shop, vendor_id)
	if resolved_vendor_id.is_empty():
		return null

	_ensure_vendor_wallet(shop, resolved_vendor_id)
	if SceneLoader.current_scene == null or not is_instance_valid(SceneLoader.current_scene):
		return null
	if not SceneLoader.current_scene.has_method("get_location_grid"):
		return null

	var grid: LocationGrid = SceneLoader.current_scene.get_location_grid() as LocationGrid
	if grid == null:
		return null

	return grid.get_character_by_id(resolved_vendor_id)


func _resolve_vendor_id(shop: Dictionary, vendor_id: String = "") -> String:
	if not vendor_id.is_empty():
		return vendor_id

	return str(shop.get("vendor_id", ""))


func _ensure_vendor_wallet(shop: Dictionary, vendor_id: String) -> void:
	if vendor_id.is_empty() or wallets.has(vendor_id):
		return

	set_currency(vendor_id, int(shop.get("vendor_currency", 0)))


func _get_inventory_item_definition(character: CharacterEntity, item_id: String) -> Dictionary:
	if character == null or not is_instance_valid(character) or character.inventory == null:
		return {}

	var stack: ItemStack = character.inventory.get_first_stack(item_id)
	if stack == null:
		return {}

	return stack.definition.duplicate(true)


func _restock_all_shops(day: int) -> void:
	for shop_key in shop_definitions.keys():
		var shop_id: String = str(shop_key)
		var shop: Dictionary = get_shop(shop_id)
		if shop.is_empty():
			continue
		if int(restocked_days.get(shop_id, 0)) >= day:
			continue

		_restock_shop(shop, day)


func _restock_shop_for_current_day(shop: Dictionary) -> void:
	var current_day: int = TimeManager.day
	if current_day <= 1:
		return

	var shop_id: String = str(shop.get("id", ""))
	if shop_id.is_empty() or int(restocked_days.get(shop_id, 0)) >= current_day:
		return

	_restock_shop(shop, current_day)


func _restock_shop(shop: Dictionary, day: int) -> void:
	var shop_id: String = str(shop.get("id", ""))
	var vendor_id: String = _resolve_vendor_id(shop)
	var vendor: CharacterEntity = _resolve_vendor(shop, vendor_id)
	if vendor == null or not is_instance_valid(vendor) or vendor.inventory == null:
		return

	_refill_vendor_wallet(shop, vendor_id)
	var changed_inventory: bool = false
	var buy_rows: Array = shop.get("buy_offers", []) as Array
	for offer_value in buy_rows:
		var offer: Dictionary = offer_value as Dictionary
		var target_stock: int = _get_offer_restock_quantity(offer)
		if target_stock <= 0:
			continue

		var item_definition: Dictionary = _load_offer_item_definition(offer)
		if item_definition.is_empty():
			item_definition = _get_inventory_item_definition(vendor, str(offer.get("item_id", "")))
		if item_definition.is_empty():
			continue

		var item_id: String = str(item_definition.get("id", offer.get("item_id", "")))
		var current_stock: int = vendor.inventory.count_item(item_id)
		var missing: int = target_stock - current_stock
		if missing <= 0:
			continue

		if vendor.inventory.add_item(item_definition, missing):
			changed_inventory = true

	if changed_inventory:
		GameState.save_character_runtime(vendor)
	restocked_days[shop_id] = day


func _refill_vendor_wallet(shop: Dictionary, vendor_id: String) -> void:
	var target_currency: int = int(shop.get("vendor_currency", 0))
	if target_currency <= 0:
		return
	if get_currency(vendor_id) < target_currency:
		set_currency(vendor_id, target_currency)


func _get_offer_restock_quantity(offer: Dictionary) -> int:
	if offer.has("restock_quantity"):
		return int(offer.get("restock_quantity", 0))
	if offer.has("daily_stock"):
		return int(offer.get("daily_stock", 0))
	if offer.has("stock"):
		return int(offer.get("stock", 0))
	return 0


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
	restocked_days.clear()


func _on_day_changed(day: int) -> void:
	_restock_all_shops(day)
