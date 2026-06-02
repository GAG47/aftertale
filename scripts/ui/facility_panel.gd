class_name FacilityPanel
extends Control

signal close_requested()
signal facility_action_requested(action_type: String, target: Dictionary)

const FILTER_ALL := "all"
const FILTER_CAN_CRAFT := "can_craft"
const FILTER_TOOLS := "tools"
const FILTER_FOOD := "food"

var _actor: CharacterEntity
var _facility_data: Dictionary = {}
var _panel: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _content_root: VBoxContainer
var _craft_filter: String = FILTER_ALL
var _craft_quantity: int = 1
var _selected_recipe_id: String = ""
var _craft_recipes: Array[Dictionary] = []
var _recipe_list: VBoxContainer
var _detail_box: VBoxContainer
var _filter_buttons: Dictionary = {}
var _shop_mode: String = "buy"
var _shop_quantity: int = 1
var _selected_trade_item_id: String = ""
var _shop_offers: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func open_for_facility(actor: CharacterEntity, facility_data: Dictionary) -> void:
	_actor = actor
	_facility_data = facility_data.duplicate(true)
	visible = true
	_craft_quantity = 1
	_selected_recipe_id = ""
	_shop_mode = "buy"
	_shop_quantity = 1
	_selected_trade_item_id = ""
	refresh()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	_clear_children(_content_root)
	var facility_type: String = str(_facility_data.get("facility_type", ""))
	_title_label.text = str(_facility_data.get("display_name", "交互对象"))

	match facility_type:
		"crafting":
			_subtitle_label.text = "制作"
			_refresh_crafting()
		"shop":
			_subtitle_label.text = "交易"
			_refresh_shop()
		_:
			_subtitle_label.text = ""
			_content_root.add_child(_make_empty_label("这个对象暂时没有可用功能。"))


func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.48)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.name = "FacilityWindow"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(920.0, 500.0)
	_panel.offset_left = -460.0
	_panel.offset_top = -250.0
	_panel.offset_right = 460.0
	_panel.offset_bottom = 250.0
	_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.055, 0.06, 0.055, 0.97), Color(0.78, 0.52, 0.24, 0.74), 6, 2))
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var title_icon: PanelContainer = PanelContainer.new()
	title_icon.custom_minimum_size = Vector2(44.0, 30.0)
	title_icon.add_theme_stylebox_override("panel", _make_panel_style(Color(0.16, 0.16, 0.14, 1.0), Color(0.68, 0.48, 0.25, 0.7), 3))
	header.add_child(title_icon)

	var icon_label: Label = Label.new()
	icon_label.text = "工"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_icon.add_child(icon_label)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.94, 0.82, 0.62))
	title_box.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.modulate = Color(0.74, 0.78, 0.70)
	title_box.add_child(_subtitle_label)

	var close_button: Button = Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(82.0, 32.0)
	close_button.pressed.connect(_request_close)
	header.add_child(close_button)

	var separator: HSeparator = HSeparator.new()
	root.add_child(separator)

	_content_root = VBoxContainer.new()
	_content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_root.add_theme_constant_override("separation", 8)
	root.add_child(_content_root)


func _refresh_crafting() -> void:
	if _actor == null or not is_instance_valid(_actor):
		_content_root.add_child(_make_empty_label("没有可制作的角色。"))
		return

	_build_craft_filters()

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_content_root.add_child(body)

	var left_panel: PanelContainer = _make_framed_panel(Vector2(360.0, 0.0))
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_panel)

	var left_margin: MarginContainer = _make_margin(10, 8, 10, 10)
	left_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_margin)

	var left_box: VBoxContainer = VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_box)

	var list_title: Label = _make_label("配方列表")
	list_title.add_theme_font_size_override("font_size", 17)
	left_box.add_child(list_title)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 250.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(scroll)

	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_recipe_list)

	var right_panel: PanelContainer = _make_framed_panel(Vector2(0.0, 0.0))
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_panel)

	var right_margin: MarginContainer = _make_margin(18, 16, 18, 16)
	right_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_margin)

	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 6)
	right_margin.add_child(_detail_box)

	_load_craft_recipes()
	_refresh_recipe_list()
	_refresh_recipe_detail()


func _build_craft_filters() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content_root.add_child(row)
	_filter_buttons.clear()
	_add_filter_button(row, "全部", FILTER_ALL)
	_add_filter_button(row, "可制作", FILTER_CAN_CRAFT)
	_add_filter_button(row, "工具", FILTER_TOOLS)
	_add_filter_button(row, "食物", FILTER_FOOD)


func _add_filter_button(parent: HBoxContainer, text: String, filter_id: String) -> void:
	var button: Button = Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = _craft_filter == filter_id
	button.custom_minimum_size = Vector2(96.0, 30.0)
	button.pressed.connect(_on_filter_pressed.bind(filter_id))
	parent.add_child(button)
	_filter_buttons[filter_id] = button


func _load_craft_recipes() -> void:
	var recipe_filter: Array = _facility_data.get("recipe_ids", []) as Array
	var summaries: Array = CraftSystem.get_recipe_summaries(_actor, _craft_quantity) as Array
	_craft_recipes.clear()
	for recipe_value in summaries:
		var recipe: Dictionary = recipe_value as Dictionary
		var recipe_id: String = str(recipe.get("id", ""))
		if not recipe_filter.is_empty() and not recipe_filter.has(recipe_id):
			continue
		if not _recipe_passes_filter(recipe):
			continue
		_craft_recipes.append(recipe)

	if not _recipe_id_in_list(_selected_recipe_id, _craft_recipes):
		_selected_recipe_id = _pick_default_recipe_id(_craft_recipes)


func _refresh_recipe_list() -> void:
	_clear_children(_recipe_list)
	if _craft_recipes.is_empty():
		_recipe_list.add_child(_make_empty_label("这里没有符合筛选的配方。"))
		return

	for recipe in _craft_recipes:
		_recipe_list.add_child(_make_recipe_button(recipe))


func _make_recipe_button(recipe: Dictionary) -> Button:
	var recipe_id: String = str(recipe.get("id", ""))
	var can_craft: bool = bool(recipe.get("can_craft", false))
	var status: String = "可制作" if can_craft else "缺材料"
	var button: Button = Button.new()
	button.text = "%s  %s        %s" % [
		_get_recipe_icon_text(recipe),
		str(recipe.get("display_name", recipe_id)),
		status,
	]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.add_theme_color_override("font_color", Color(0.74, 0.95, 0.45) if can_craft else Color(0.95, 0.36, 0.34))
	if recipe_id == _selected_recipe_id:
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.18, 0.16, 0.10, 1.0), Color(0.94, 0.64, 0.20, 0.95), 4, 2))
	button.pressed.connect(_on_recipe_selected.bind(recipe_id))
	return button


func _refresh_recipe_detail() -> void:
	_clear_children(_detail_box)
	var recipe: Dictionary = _get_selected_recipe()
	if recipe.is_empty():
		_detail_box.add_child(_make_empty_label("请选择一个配方。"))
		return

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_detail_box.add_child(top)

	var icon_box: PanelContainer = _make_framed_panel(Vector2(58.0, 58.0))
	top.add_child(icon_box)
	var icon_label: Label = _make_label(_get_recipe_icon_text(recipe))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 24)
	icon_box.add_child(icon_label)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	var title_label: Label = _make_label(str(recipe.get("display_name", recipe.get("id", ""))))
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(0.94, 0.82, 0.62))
	title_box.add_child(title_label)
	var description_label: Label = _make_label(str(recipe.get("description", "")))
	description_label.modulate = Color(0.82, 0.78, 0.68)
	title_box.add_child(description_label)

	_detail_box.add_child(HSeparator.new())
	_add_output_section(recipe)
	_detail_box.add_child(HSeparator.new())
	_add_ingredient_section(recipe)

	_add_quantity_controls(recipe)
	_add_craft_button(recipe)


func _add_output_section(recipe: Dictionary) -> void:
	_detail_box.add_child(_make_section_title("产出"))
	var output_details: Array = recipe.get("output_details", []) as Array
	for output_value in output_details:
		var output: Dictionary = output_value as Dictionary
		_detail_box.add_child(_make_item_line(
			str(output.get("display_name", output.get("item_id", ""))),
			"x%d" % int(output.get("quantity", 1)),
			Color(0.94, 0.86, 0.66),
			_get_item_icon_text(str(output.get("item_type", "")))
		))


func _add_ingredient_section(recipe: Dictionary) -> void:
	_detail_box.add_child(_make_section_title("材料"))
	var material_scroll: ScrollContainer = ScrollContainer.new()
	material_scroll.custom_minimum_size = Vector2(0.0, 74.0)
	material_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(material_scroll)

	var material_list: VBoxContainer = VBoxContainer.new()
	material_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_list.add_theme_constant_override("separation", 4)
	material_scroll.add_child(material_list)

	var ingredient_details: Array = recipe.get("ingredient_details", []) as Array
	for ingredient_value in ingredient_details:
		var ingredient: Dictionary = ingredient_value as Dictionary
		var has_enough: bool = bool(ingredient.get("has_enough", false))
		var count_text: String = "%d / %d" % [
			int(ingredient.get("owned", 0)),
			int(ingredient.get("required", 0)),
		]
		material_list.add_child(_make_item_line(
			str(ingredient.get("display_name", ingredient.get("item_id", ""))),
			count_text,
			Color(0.62, 0.88, 0.38) if has_enough else Color(0.95, 0.38, 0.34),
			"材"
		))


func _add_quantity_controls(_recipe: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_detail_box.add_child(row)

	var label: Label = _make_label("制作数量")
	label.custom_minimum_size = Vector2(112.0, 28.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var minus_button: Button = Button.new()
	minus_button.text = "-"
	minus_button.custom_minimum_size = Vector2(40.0, 28.0)
	minus_button.disabled = _craft_quantity <= 1
	minus_button.pressed.connect(_on_quantity_changed.bind(-1))
	row.add_child(minus_button)

	var quantity_label: Label = _make_label(str(_craft_quantity))
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_label.custom_minimum_size = Vector2(76.0, 28.0)
	quantity_label.add_theme_stylebox_override("normal", _make_panel_style(Color(0.08, 0.08, 0.07, 1.0), Color(0.42, 0.34, 0.24, 0.8), 3))
	row.add_child(quantity_label)

	var plus_button: Button = Button.new()
	plus_button.text = "+"
	plus_button.custom_minimum_size = Vector2(40.0, 28.0)
	plus_button.disabled = _craft_quantity >= 99
	plus_button.pressed.connect(_on_quantity_changed.bind(1))
	row.add_child(plus_button)


func _add_craft_button(recipe: Dictionary) -> void:
	var button: Button = Button.new()
	button.text = "制作"
	button.custom_minimum_size = Vector2(220.0, 34.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.disabled = not bool(recipe.get("can_craft", false))
	button.pressed.connect(_on_craft_pressed.bind(str(recipe.get("id", ""))))
	_detail_box.add_child(button)


func _refresh_shop() -> void:
	if _actor == null or not is_instance_valid(_actor):
		_content_root.add_child(_make_empty_label("没有可交易的角色。"))
		return

	var shop_id: String = str(_facility_data.get("shop_id", ""))
	var vendor_id: String = _get_shop_vendor_id()
	var market: Dictionary = BusinessSystem.get_market_summary(_actor, shop_id, vendor_id)

	var intro_row: HBoxContainer = HBoxContainer.new()
	intro_row.add_theme_constant_override("separation", 12)
	_content_root.add_child(intro_row)

	var description_label: Label = _make_label(str(market.get("description", "")))
	description_label.modulate = Color(0.82, 0.80, 0.74)
	intro_row.add_child(description_label)

	var money_label: Label = _make_label("金币：%d" % int(market.get("currency", 0)))
	money_label.custom_minimum_size = Vector2(110.0, 0.0)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	intro_row.add_child(money_label)

	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	_content_root.add_child(tab_row)
	tab_row.add_child(_make_shop_mode_button("购买", "buy"))
	tab_row.add_child(_make_shop_mode_button("出售", "sell"))

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_content_root.add_child(body)

	var left_panel: PanelContainer = _make_framed_panel(Vector2(370.0, 0.0))
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_panel)

	var left_margin: MarginContainer = _make_margin(10, 8, 10, 10)
	left_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_margin)

	var left_box: VBoxContainer = VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_box)

	left_box.add_child(_make_section_title("商品列表"))

	var list_scroll: ScrollContainer = ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(list_scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	list_scroll.add_child(list)

	_shop_offers.clear()
	var raw_offers: Array = (market.get("buy_offers", []) if _shop_mode == "buy" else market.get("sell_offers", [])) as Array
	for offer_value in raw_offers:
		_shop_offers.append(offer_value as Dictionary)
	if not _shop_offer_id_in_list(_selected_trade_item_id, _shop_offers):
		_selected_trade_item_id = _pick_default_shop_offer_id(_shop_offers)
		_shop_quantity = 1

	if _shop_offers.is_empty():
		var empty_text: String = "摊位没有可购买的商品。" if _shop_mode == "buy" else "背包里没有这里收购的物品。"
		list.add_child(_make_empty_label(empty_text))
	else:
		for offer in _shop_offers:
			list.add_child(_make_shop_offer_button(offer))

	var right_panel: PanelContainer = _make_framed_panel(Vector2(0.0, 0.0))
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_panel)

	var right_margin: MarginContainer = _make_margin(18, 14, 18, 14)
	right_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_margin)

	var right_box: VBoxContainer = VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 8)
	right_margin.add_child(right_box)

	_refresh_shop_detail(right_box, str(market.get("shop_id", shop_id)), vendor_id, int(market.get("vendor_currency", 0)))


func _make_shop_mode_button(text: String, mode: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = _shop_mode == mode
	button.custom_minimum_size = Vector2(150.0, 34.0)
	button.pressed.connect(_on_shop_mode_pressed.bind(mode))
	return button


func _make_shop_offer_button(offer: Dictionary) -> Button:
	var item_id: String = str(offer.get("item_id", ""))
	var price: int = int(offer.get("price", 0))
	var status: String = ""
	if _shop_mode == "buy":
		status = "库存 %d" % int(offer.get("stock", 0))
	else:
		status = "持有 %d" % int(offer.get("quantity", 0))

	var button: Button = Button.new()
	button.text = "%s  %s        %dG  %s" % [
		_get_item_icon_text(str(offer.get("item_type", ""))),
		str(offer.get("display_name", item_id)),
		price,
		status,
	]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 52.0)
	if item_id == _selected_trade_item_id:
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.18, 0.16, 0.10, 1.0), Color(0.94, 0.64, 0.20, 0.95), 4, 2))
	if (_shop_mode == "buy" and int(offer.get("stock", 0)) <= 0) or (_shop_mode == "sell" and not bool(offer.get("can_sell", false))):
		button.add_theme_color_override("font_color", Color(0.95, 0.36, 0.34))
	button.pressed.connect(_on_shop_offer_selected.bind(item_id))
	return button


func _refresh_shop_detail(parent: VBoxContainer, shop_id: String, vendor_id: String, vendor_currency: int) -> void:
	var offer: Dictionary = _get_selected_shop_offer()
	if offer.is_empty():
		parent.add_child(_make_empty_label("请选择一个商品。"))
		return

	var item_id: String = str(offer.get("item_id", ""))
	var unit_price: int = int(offer.get("price", 0))
	var total_price: int = unit_price * _shop_quantity
	var failure_reason: String = BusinessSystem.get_trade_failure(_actor, shop_id, _shop_mode, item_id, _shop_quantity, vendor_id)
	var can_trade: bool = failure_reason.is_empty()

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.custom_minimum_size = Vector2(0.0, 82.0)
	parent.add_child(top)

	var icon_box: PanelContainer = _make_framed_panel(Vector2(64.0, 64.0))
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(icon_box)
	var icon_label: Label = _make_label(_get_item_icon_text(str(offer.get("item_type", ""))))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 24)
	icon_box.add_child(icon_label)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)

	var title_label: Label = _make_label(str(offer.get("display_name", item_id)))
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(0.94, 0.82, 0.62))
	title_box.add_child(title_label)

	var description_label: Label = _make_label(str(offer.get("description", "")))
	description_label.modulate = Color(0.82, 0.78, 0.68)
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var description_scroll: ScrollContainer = ScrollContainer.new()
	description_scroll.custom_minimum_size = Vector2(0.0, 42.0)
	description_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	description_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	description_scroll.add_child(description_label)
	title_box.add_child(description_scroll)

	parent.add_child(HSeparator.new())
	var details: VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 4)
	parent.add_child(details)

	details.add_child(_make_shop_detail_line("类型", _format_item_type(str(offer.get("item_type", ""))), Color(0.86, 0.82, 0.72)))
	if _shop_mode == "buy":
		details.add_child(_make_shop_detail_line("购买价格", "%d 金币" % unit_price, Color(0.95, 0.82, 0.48)))
		details.add_child(_make_shop_detail_line("持有数量", "%d" % int(offer.get("owned_quantity", 0)), Color(0.86, 0.82, 0.72)))
		details.add_child(_make_shop_detail_line("库存", "%d" % int(offer.get("stock", 0)), Color(0.62, 0.88, 0.38) if int(offer.get("stock", 0)) > 0 else Color(0.95, 0.38, 0.34)))
	else:
		details.add_child(_make_shop_detail_line("出售价格", "%d 金币" % unit_price, Color(0.95, 0.82, 0.48)))
		details.add_child(_make_shop_detail_line("持有数量", "%d" % int(offer.get("quantity", 0)), Color(0.86, 0.82, 0.72)))
		details.add_child(_make_shop_detail_line("对方金币", "%d" % vendor_currency, Color(0.62, 0.88, 0.38) if vendor_currency >= total_price else Color(0.95, 0.38, 0.34)))

	if not failure_reason.is_empty():
		var failure_label: Label = _make_label(failure_reason)
		failure_label.add_theme_color_override("font_color", Color(0.95, 0.38, 0.34))
		details.add_child(failure_label)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	parent.add_child(bottom)

	var quantity_label: Label = _make_label("数量")
	quantity_label.custom_minimum_size = Vector2(58.0, 30.0)
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(quantity_label)

	var minus_button: Button = Button.new()
	minus_button.text = "-"
	minus_button.custom_minimum_size = Vector2(40.0, 30.0)
	minus_button.disabled = _shop_quantity <= 1
	minus_button.pressed.connect(_on_shop_quantity_changed.bind(-1))
	bottom.add_child(minus_button)

	var quantity_value: Label = _make_label(str(_shop_quantity))
	quantity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_value.custom_minimum_size = Vector2(84.0, 30.0)
	quantity_value.add_theme_stylebox_override("normal", _make_panel_style(Color(0.08, 0.08, 0.07, 1.0), Color(0.42, 0.34, 0.24, 0.8), 3))
	bottom.add_child(quantity_value)

	var plus_button: Button = Button.new()
	plus_button.text = "+"
	plus_button.custom_minimum_size = Vector2(40.0, 30.0)
	plus_button.disabled = _shop_quantity >= _get_shop_quantity_limit(offer)
	plus_button.pressed.connect(_on_shop_quantity_changed.bind(1))
	bottom.add_child(plus_button)

	var total_label: Label = _make_label("总价：%d 金币" % total_price)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	bottom.add_child(total_label)

	var action_button: Button = Button.new()
	action_button.text = "购买" if _shop_mode == "buy" else "出售"
	action_button.custom_minimum_size = Vector2(120.0, 34.0)
	action_button.disabled = not can_trade
	action_button.pressed.connect(_on_shop_trade_pressed.bind(shop_id, vendor_id, item_id))
	bottom.add_child(action_button)


func _make_recipe_button_style(selected: bool) -> StyleBoxFlat:
	if selected:
		return _make_panel_style(Color(0.18, 0.16, 0.10, 1.0), Color(0.94, 0.64, 0.20, 0.95), 4, 2)
	return _make_panel_style(Color(0.10, 0.11, 0.10, 1.0), Color(0.25, 0.24, 0.20, 0.95), 4, 1)


func _make_item_line(title: String, right_text: String, right_color: Color, icon_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0.0, 30.0)

	var icon: PanelContainer = _make_framed_panel(Vector2(30.0, 30.0))
	row.add_child(icon)
	var icon_label: Label = _make_label(icon_text)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_child(icon_label)

	var name_label: Label = _make_label(title)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var count_label: Label = _make_label(right_text)
	count_label.custom_minimum_size = Vector2(92.0, 0.0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_color", right_color)
	row.add_child(count_label)
	return row


func _make_shop_detail_line(title: String, right_text: String, right_color: Color) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0.0, 28.0)

	var title_label: Label = _make_label(title)
	title_label.custom_minimum_size = Vector2(120.0, 0.0)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_label)

	var value_label: Label = _make_label(right_text)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_color_override("font_color", right_color)
	row.add_child(value_label)
	return row


func _make_section_title(text: String) -> Label:
	var label: Label = _make_label(text)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.38))
	return label


func _make_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _make_empty_label(text: String) -> Label:
	var label: Label = _make_label(text)
	label.modulate = Color(0.78, 0.78, 0.78)
	return label


func _make_section(title: String, detail: String) -> VBoxContainer:
	var section: VBoxContainer = VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.custom_minimum_size = Vector2(0.0, 64.0)
	section.add_theme_constant_override("separation", 4)

	var title_label: Label = _make_label(title)
	title_label.add_theme_font_size_override("font_size", 16)
	section.add_child(title_label)

	if not detail.is_empty():
		var detail_label: Label = _make_label(detail)
		detail_label.modulate = Color(0.82, 0.82, 0.82)
		section.add_child(detail_label)

	var separator: HSeparator = HSeparator.new()
	section.add_child(separator)
	return section


func _make_framed_panel(min_size: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.075, 0.08, 0.075, 0.96), Color(0.40, 0.32, 0.20, 0.78), 4))
	return panel


func _make_margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func _make_panel_style(bg_color: Color, border_color: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _recipe_passes_filter(recipe: Dictionary) -> bool:
	match _craft_filter:
		FILTER_CAN_CRAFT:
			return bool(recipe.get("can_craft", false))
		FILTER_TOOLS:
			return _is_tool_category(recipe)
		FILTER_FOOD:
			return _is_food_category(recipe)
		_:
			return true


func _is_tool_category(recipe: Dictionary) -> bool:
	var category: String = str(recipe.get("category", ""))
	return category == "tool" or category == "tools" or category == "equipment"


func _is_food_category(recipe: Dictionary) -> bool:
	var category: String = str(recipe.get("category", ""))
	return category == "food" or category == "foods" or category == "consumable" or category == "consumables"


func _get_recipe_icon_text(recipe: Dictionary) -> String:
	if _is_tool_category(recipe):
		return "工"
	if _is_food_category(recipe):
		return "食"
	return "物"


func _get_item_icon_text(item_type: String) -> String:
	match item_type:
		"tool":
			return "工"
		"consumable", "food":
			return "食"
		"material":
			return "材"
		"seed":
			return "种"
		"equipment":
			return "装"
		_:
			return "物"


func _recipe_id_in_list(recipe_id: String, recipes: Array[Dictionary]) -> bool:
	if recipe_id.is_empty():
		return false
	for recipe in recipes:
		if str(recipe.get("id", "")) == recipe_id:
			return true
	return false


func _pick_default_recipe_id(recipes: Array[Dictionary]) -> String:
	for recipe in recipes:
		if bool(recipe.get("can_craft", false)):
			return str(recipe.get("id", ""))
	if not recipes.is_empty():
		return str(recipes[0].get("id", ""))
	return ""


func _get_selected_recipe() -> Dictionary:
	for recipe in _craft_recipes:
		if str(recipe.get("id", "")) == _selected_recipe_id:
			return recipe
	return {}


func _get_selected_shop_offer() -> Dictionary:
	for offer in _shop_offers:
		if str(offer.get("item_id", "")) == _selected_trade_item_id:
			return offer
	return {}


func _shop_offer_id_in_list(item_id: String, offers: Array[Dictionary]) -> bool:
	if item_id.is_empty():
		return false
	for offer in offers:
		if str(offer.get("item_id", "")) == item_id:
			return true
	return false


func _pick_default_shop_offer_id(offers: Array[Dictionary]) -> String:
	if offers.is_empty():
		return ""
	return str(offers[0].get("item_id", ""))


func _get_shop_quantity_limit(offer: Dictionary) -> int:
	if _shop_mode == "buy":
		return max(1, int(offer.get("stock", 0)))
	return max(1, int(offer.get("quantity", 0)))


func _get_shop_vendor_id() -> String:
	return str(_facility_data.get("vendor_character_id", _facility_data.get("vendor_id", "")))


func _format_item_type(item_type: String) -> String:
	match item_type:
		"tool":
			return "工具"
		"consumable", "food":
			return "食物"
		"material":
			return "材料"
		"seed":
			return "种子"
		"equipment":
			return "装备"
		_:
			return item_type if not item_type.is_empty() else "物品"


func _on_filter_pressed(filter_id: String) -> void:
	_craft_filter = filter_id
	refresh()


func _on_recipe_selected(recipe_id: String) -> void:
	_selected_recipe_id = recipe_id
	refresh()


func _on_quantity_changed(delta: int) -> void:
	_craft_quantity = clampi(_craft_quantity + delta, 1, 99)
	refresh()


func _on_craft_pressed(recipe_id: String) -> void:
	_on_action_pressed("CraftAction", {
		"recipe_id": recipe_id,
		"quantity": _craft_quantity,
	})


func _on_shop_mode_pressed(mode: String) -> void:
	_shop_mode = mode
	_shop_quantity = 1
	_selected_trade_item_id = ""
	refresh()


func _on_shop_offer_selected(item_id: String) -> void:
	_selected_trade_item_id = item_id
	_shop_quantity = 1
	refresh()


func _on_shop_quantity_changed(delta: int) -> void:
	var offer: Dictionary = _get_selected_shop_offer()
	_shop_quantity = clampi(_shop_quantity + delta, 1, _get_shop_quantity_limit(offer))
	refresh()


func _on_shop_trade_pressed(shop_id: String, vendor_id: String, item_id: String) -> void:
	_on_action_pressed("TradeAction", {
		"shop_id": shop_id,
		"vendor_id": vendor_id,
		"trade_type": _shop_mode,
		"item_id": item_id,
		"quantity": _shop_quantity,
	})


func _on_action_pressed(action_type: String, target: Dictionary) -> void:
	facility_action_requested.emit(action_type, target.duplicate(true))


func _request_close() -> void:
	close_requested.emit()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()
