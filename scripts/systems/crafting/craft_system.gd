extends Node

signal recipes_loaded(count: int)
signal recipe_crafted(actor_id: String, recipe_id: String)

const RECIPE_PATHS = [
	"res://data/recipes/debug_tool.json",
	"res://data/recipes/packed_snack.json",
	"res://data/recipes/material_scroll_test.json",
]

var recipe_definitions: Dictionary = {}


func _ready() -> void:
	_load_recipe_definitions()


func get_recipe(recipe_id: String) -> Dictionary:
	if recipe_id.is_empty() or not recipe_definitions.has(recipe_id):
		return {}

	var recipe: Dictionary = recipe_definitions[recipe_id] as Dictionary
	return recipe.duplicate(true)


func get_known_recipes() -> Array[Dictionary]:
	var recipes: Array[Dictionary] = []
	for recipe_value in recipe_definitions.values():
		var recipe: Dictionary = recipe_value as Dictionary
		recipes.append(recipe.duplicate(true))

	return recipes


func get_recipe_summaries(actor: CharacterEntity, craft_quantity: int = 1) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	var batch_quantity: int = max(1, craft_quantity)
	for recipe in get_known_recipes():
		var recipe_id: String = str(recipe.get("id", ""))
		var failed_requirement: String = get_failed_requirement(actor, recipe_id, batch_quantity)
		var summary: Dictionary = recipe.duplicate(true)
		summary["can_craft"] = failed_requirement.is_empty()
		summary["failure_reason"] = failed_requirement
		summary["ingredient_text"] = _format_stack_entries(recipe.get("ingredients", []) as Array, false)
		summary["output_text"] = _format_stack_entries(recipe.get("outputs", []) as Array, true)
		summary["craft_quantity"] = batch_quantity
		summary["ingredient_details"] = get_ingredient_details(actor, recipe_id, batch_quantity)
		summary["output_details"] = get_output_details(recipe_id, batch_quantity)
		summaries.append(summary)

	return summaries


func get_failed_requirement(actor: CharacterEntity, recipe_id: String, craft_quantity: int = 1) -> String:
	if actor == null or not is_instance_valid(actor):
		return "制作需要有效的角色。"
	if actor.inventory == null:
		return "%s 没有背包。" % actor.display_name

	var batch_quantity: int = max(1, craft_quantity)
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return "未知配方：%s" % recipe_id

	var ingredients: Array = recipe.get("ingredients", []) as Array
	if ingredients.is_empty():
		return "配方没有材料：%s" % recipe_id

	var outputs: Array = recipe.get("outputs", []) as Array
	if outputs.is_empty():
		return "配方没有产出：%s" % recipe_id

	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		var item_id: String = str(ingredient.get("item_id", ""))
		var quantity: int = int(ingredient.get("quantity", 1)) * batch_quantity
		if item_id.is_empty() or quantity <= 0:
			return "配方包含无效材料：%s" % recipe_id
		if actor.inventory.count_item(item_id) < quantity:
			return "缺少 %d 个 %s。" % [quantity, item_id]

	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var output_definition: Dictionary = _load_output_definition(output)
		if output_definition.is_empty():
			return "无法加载配方产出：%s" % recipe_id

	if not _inventory_accepts_outputs_after_inputs(actor.inventory, ingredients, outputs, batch_quantity):
		return "%s 装不下制作产物。" % actor.display_name

	return ""


func execute_craft(actor: CharacterEntity, recipe_id: String, craft_quantity: int = 1) -> ActionResult:
	var batch_quantity: int = max(1, craft_quantity)
	var failed_requirement: String = get_failed_requirement(actor, recipe_id, batch_quantity)
	if not failed_requirement.is_empty():
		var actor_id: String = ""
		if actor != null and is_instance_valid(actor):
			actor_id = actor.character_id
		return ActionResult.failed("CraftAction", actor_id, failed_requirement, {
			"recipe_id": recipe_id,
			"quantity": batch_quantity,
		})

	var recipe: Dictionary = get_recipe(recipe_id)
	var ingredients: Array = recipe.get("ingredients", []) as Array
	var outputs: Array = recipe.get("outputs", []) as Array

	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		actor.inventory.remove_item(str(ingredient.get("item_id", "")), int(ingredient.get("quantity", 1)) * batch_quantity)

	var crafted_outputs: Array[Dictionary] = []
	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var output_definition: Dictionary = _load_output_definition(output)
		var quantity: int = int(output.get("quantity", 1)) * batch_quantity
		actor.inventory.add_item(output_definition, quantity)
		crafted_outputs.append({
			"item_id": str(output_definition.get("id", "")),
			"display_name": str(output_definition.get("display_name", output_definition.get("id", ""))),
			"quantity": quantity,
		})

	GameState.save_character_runtime(actor)

	var result: ActionResult = ActionResult.succeeded("CraftAction", actor.character_id, {
		"recipe_id": recipe_id,
		"quantity": batch_quantity,
	})
	result.add_world_change({
		"type": "recipe_crafted",
		"character_id": actor.character_id,
		"recipe_id": recipe_id,
		"quantity": batch_quantity,
		"outputs": crafted_outputs,
	})
	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		result.add_world_change({
			"type": "crafting_ingredient_consumed",
			"character_id": actor.character_id,
			"recipe_id": recipe_id,
			"item_id": str(ingredient.get("item_id", "")),
			"quantity": int(ingredient.get("quantity", 1)) * batch_quantity,
		})
	for output in crafted_outputs:
		result.add_world_change({
			"type": "crafting_output_added",
			"character_id": actor.character_id,
			"recipe_id": recipe_id,
			"item_id": str(output.get("item_id", "")),
			"quantity": int(output.get("quantity", 1)),
		})
	result.add_feedback("%s 制作了 %s x%d。" % [actor.display_name, str(recipe.get("display_name", recipe_id)), batch_quantity])
	recipe_crafted.emit(actor.character_id, recipe_id)
	return result


func get_ingredient_details(actor: CharacterEntity, recipe_id: String, craft_quantity: int = 1) -> Array[Dictionary]:
	var details: Array[Dictionary] = []
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return details

	var batch_quantity: int = max(1, craft_quantity)
	var ingredients: Array = recipe.get("ingredients", []) as Array
	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		var item_id: String = str(ingredient.get("item_id", ""))
		var required: int = max(1, int(ingredient.get("quantity", 1))) * batch_quantity
		var owned: int = 0
		var display_name: String = item_id
		if actor != null and is_instance_valid(actor) and actor.inventory != null:
			owned = actor.inventory.count_item(item_id)
			var stack: ItemStack = actor.inventory.get_first_stack(item_id)
			if stack != null:
				display_name = stack.display_name
		details.append({
			"item_id": item_id,
			"display_name": display_name,
			"required": required,
			"owned": owned,
			"has_enough": owned >= required,
		})

	return details


func get_output_details(recipe_id: String, craft_quantity: int = 1) -> Array[Dictionary]:
	var details: Array[Dictionary] = []
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return details

	var batch_quantity: int = max(1, craft_quantity)
	var outputs: Array = recipe.get("outputs", []) as Array
	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var output_definition: Dictionary = _load_output_definition(output)
		if output_definition.is_empty():
			continue
		details.append({
			"item_id": str(output_definition.get("id", "")),
			"display_name": str(output_definition.get("display_name", output_definition.get("id", ""))),
			"quantity": max(1, int(output.get("quantity", 1))) * batch_quantity,
			"item_type": str(output_definition.get("item_type", "")),
			"description": str(output_definition.get("description", "")),
		})

	return details


func _load_recipe_definitions() -> void:
	recipe_definitions.clear()
	for recipe_path in RECIPE_PATHS:
		var recipe: Dictionary = DefinitionLoader.load_recipe(recipe_path)
		if recipe.is_empty():
			continue

		var recipe_id: String = str(recipe.get("id", ""))
		if recipe_id.is_empty():
			push_error("CraftSystem recipe has no id: %s" % recipe_path)
			continue

		recipe_definitions[recipe_id] = recipe

	recipes_loaded.emit(recipe_definitions.size())


func _load_output_definition(output: Dictionary) -> Dictionary:
	var source_path: String = str(output.get("source", ""))
	if source_path.is_empty():
		return {}

	return DefinitionLoader.load_item(source_path)


func _inventory_accepts_outputs_after_inputs(inventory: Inventory, ingredients: Array, outputs: Array, craft_quantity: int = 1) -> bool:
	var simulated_inventory: Inventory = Inventory.new()
	simulated_inventory.apply_runtime_state(inventory.get_runtime_state())
	var batch_quantity: int = max(1, craft_quantity)

	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		if not simulated_inventory.remove_item(str(ingredient.get("item_id", "")), int(ingredient.get("quantity", 1)) * batch_quantity):
			return false

	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var output_definition: Dictionary = _load_output_definition(output)
		var quantity: int = int(output.get("quantity", 1)) * batch_quantity
		if output_definition.is_empty() or not simulated_inventory.add_item(output_definition, quantity):
			return false

	return true


func _format_stack_entries(entries: Array, use_source: bool) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry_value in entries:
		var entry: Dictionary = entry_value as Dictionary
		var item_label: String = str(entry.get("item_id", ""))
		if use_source:
			var definition: Dictionary = _load_output_definition(entry)
			item_label = str(definition.get("display_name", definition.get("id", "unknown")))
		parts.append("%d 个 %s" % [
			int(entry.get("quantity", 1)),
			item_label,
		])

	return _join_strings(parts, ", ")


func _join_strings(values: PackedStringArray, separator: String) -> String:
	var result: String = ""
	for index in range(values.size()):
		if index > 0:
			result += separator
		result += values[index]

	return result
