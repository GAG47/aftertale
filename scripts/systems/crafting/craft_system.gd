extends Node

signal recipes_loaded(count: int)
signal recipe_crafted(actor_id: String, recipe_id: String)

const RECIPE_PATHS = [
	"res://data/recipes/debug_tool.json",
	"res://data/recipes/packed_snack.json",
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


func get_recipe_summaries(actor: CharacterEntity) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for recipe in get_known_recipes():
		var recipe_id: String = str(recipe.get("id", ""))
		var failed_requirement: String = get_failed_requirement(actor, recipe_id)
		var summary: Dictionary = recipe.duplicate(true)
		summary["can_craft"] = failed_requirement.is_empty()
		summary["failure_reason"] = failed_requirement
		summary["ingredient_text"] = _format_stack_entries(recipe.get("ingredients", []) as Array, false)
		summary["output_text"] = _format_stack_entries(recipe.get("outputs", []) as Array, true)
		summaries.append(summary)

	return summaries


func get_failed_requirement(actor: CharacterEntity, recipe_id: String) -> String:
	if actor == null or not is_instance_valid(actor):
		return "Crafting requires an actor."
	if actor.inventory == null:
		return "%s has no inventory." % actor.display_name

	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return "Unknown recipe: %s" % recipe_id

	var ingredients: Array = recipe.get("ingredients", []) as Array
	if ingredients.is_empty():
		return "Recipe has no ingredients: %s" % recipe_id

	var outputs: Array = recipe.get("outputs", []) as Array
	if outputs.is_empty():
		return "Recipe has no outputs: %s" % recipe_id

	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		var item_id: String = str(ingredient.get("item_id", ""))
		var quantity: int = int(ingredient.get("quantity", 1))
		if item_id.is_empty() or quantity <= 0:
			return "Recipe has an invalid ingredient: %s" % recipe_id
		if actor.inventory.count_item(item_id) < quantity:
			return "Missing %d x %s." % [quantity, item_id]

	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var output_definition: Dictionary = _load_output_definition(output)
		if output_definition.is_empty():
			return "Recipe output could not be loaded: %s" % recipe_id

	if not _inventory_accepts_outputs_after_inputs(actor.inventory, ingredients, outputs):
		return "%s cannot carry the crafted items." % actor.display_name

	return ""


func execute_craft(actor: CharacterEntity, recipe_id: String) -> ActionResult:
	var failed_requirement: String = get_failed_requirement(actor, recipe_id)
	if not failed_requirement.is_empty():
		var actor_id: String = ""
		if actor != null and is_instance_valid(actor):
			actor_id = actor.character_id
		return ActionResult.failed("CraftAction", actor_id, failed_requirement, {
			"recipe_id": recipe_id,
		})

	var recipe: Dictionary = get_recipe(recipe_id)
	var ingredients: Array = recipe.get("ingredients", []) as Array
	var outputs: Array = recipe.get("outputs", []) as Array

	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		actor.inventory.remove_item(str(ingredient.get("item_id", "")), int(ingredient.get("quantity", 1)))

	var crafted_outputs: Array[Dictionary] = []
	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var output_definition: Dictionary = _load_output_definition(output)
		var quantity: int = int(output.get("quantity", 1))
		actor.inventory.add_item(output_definition, quantity)
		crafted_outputs.append({
			"item_id": str(output_definition.get("id", "")),
			"quantity": quantity,
		})

	GameState.save_character_runtime(actor)

	var result: ActionResult = ActionResult.succeeded("CraftAction", actor.character_id, {
		"recipe_id": recipe_id,
	})
	result.add_world_change({
		"type": "recipe_crafted",
		"character_id": actor.character_id,
		"recipe_id": recipe_id,
		"outputs": crafted_outputs,
	})
	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		result.add_world_change({
			"type": "crafting_ingredient_consumed",
			"character_id": actor.character_id,
			"recipe_id": recipe_id,
			"item_id": str(ingredient.get("item_id", "")),
			"quantity": int(ingredient.get("quantity", 1)),
		})
	for output in crafted_outputs:
		result.add_world_change({
			"type": "crafting_output_added",
			"character_id": actor.character_id,
			"recipe_id": recipe_id,
			"item_id": str(output.get("item_id", "")),
			"quantity": int(output.get("quantity", 1)),
		})
	result.add_feedback("%s crafted %s." % [actor.display_name, str(recipe.get("display_name", recipe_id))])
	recipe_crafted.emit(actor.character_id, recipe_id)
	return result


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


func _inventory_accepts_outputs_after_inputs(inventory: Inventory, ingredients: Array, outputs: Array) -> bool:
	var simulated_inventory: Inventory = Inventory.new()
	simulated_inventory.apply_runtime_state(inventory.get_runtime_state())

	for ingredient_value in ingredients:
		var ingredient: Dictionary = ingredient_value as Dictionary
		if not simulated_inventory.remove_item(str(ingredient.get("item_id", "")), int(ingredient.get("quantity", 1))):
			return false

	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var output_definition: Dictionary = _load_output_definition(output)
		var quantity: int = int(output.get("quantity", 1))
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
		parts.append("%d x %s" % [
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
