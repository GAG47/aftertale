extends Node

signal crop_planted(location_id: String, cell: Vector2i, crop_id: String)
signal crop_watered(location_id: String, cell: Vector2i, crop_id: String)
signal crop_harvested(location_id: String, cell: Vector2i, crop_id: String)
signal crop_changed(location_id: String, cell: Vector2i, crop_state: Dictionary)

const CROP_PATHS = [
	"res://data/crops/debug_crop.json",
]

var crop_definitions: Dictionary = {}
var crop_states: Dictionary = {}


func _ready() -> void:
	_load_crop_definitions()
	TimeManager.time_changed.connect(_on_time_changed)
	GameState.session_started.connect(_on_session_started)


func get_crop_definition(crop_id: String) -> Dictionary:
	if crop_id.is_empty() or not crop_definitions.has(crop_id):
		return {}

	var definition: Dictionary = crop_definitions[crop_id] as Dictionary
	return definition.duplicate(true)


func get_crop_at(location_id: String, cell: Vector2i) -> Dictionary:
	var location_crops: Dictionary = crop_states.get(location_id, {}) as Dictionary
	var crop_state: Dictionary = location_crops.get(_cell_key(cell), {}) as Dictionary
	return crop_state.duplicate(true)


func has_crop_at(location_id: String, cell: Vector2i) -> bool:
	return not get_crop_at(location_id, cell).is_empty()


func get_location_crops(location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var location_crops: Dictionary = crop_states.get(location_id, {}) as Dictionary
	for crop_value in location_crops.values():
		var crop_state: Dictionary = crop_value as Dictionary
		result.append(crop_state.duplicate(true))

	return result


func get_seed_item_id(actor: CharacterEntity) -> String:
	if actor == null or not is_instance_valid(actor) or actor.inventory == null:
		return ""

	for crop_definition_value in crop_definitions.values():
		var crop_definition: Dictionary = crop_definition_value as Dictionary
		var seed_item_id: String = str(crop_definition.get("seed_item_id", ""))
		if not seed_item_id.is_empty() and actor.inventory.count_item(seed_item_id) > 0:
			return seed_item_id

	return ""


func get_plant_failure(actor: CharacterEntity, location_root: Node, cell: Vector2i, seed_item_id: String = "") -> String:
	if actor == null or not is_instance_valid(actor):
		return "Planting requires an actor."
	if actor.inventory == null:
		return "%s has no inventory." % actor.display_name
	if not _location_can_use_crops(location_root):
		return "Planting requires an active location."
	if not bool(location_root.is_cell_plantable(cell)):
		return "This cell cannot be planted."

	var location_id: String = str(location_root.get_location_grid().location_id)
	if has_crop_at(location_id, cell):
		return "There is already a crop here."

	var resolved_seed_item_id: String = seed_item_id
	if resolved_seed_item_id.is_empty():
		resolved_seed_item_id = get_seed_item_id(actor)
	if resolved_seed_item_id.is_empty():
		return "%s has no seeds." % actor.display_name

	var crop_definition: Dictionary = _get_crop_definition_for_seed(resolved_seed_item_id)
	if crop_definition.is_empty():
		return "No crop is known for %s." % resolved_seed_item_id

	if actor.inventory.count_item(resolved_seed_item_id) <= 0:
		return "%s does not have %s." % [actor.display_name, resolved_seed_item_id]

	return ""


func get_water_failure(actor: CharacterEntity, location_root: Node, cell: Vector2i) -> String:
	if actor == null or not is_instance_valid(actor):
		return "Watering requires an actor."
	if not _location_can_use_crops(location_root):
		return "Watering requires an active location."

	var location_id: String = str(location_root.get_location_grid().location_id)
	var crop_state: Dictionary = get_crop_at(location_id, cell)
	if crop_state.is_empty():
		return "There is no crop here."
	if bool(crop_state.get("watered", false)):
		return "%s is already watered." % str(crop_state.get("display_name", "The crop"))
	if bool(crop_state.get("mature", false)):
		return "%s is already mature." % str(crop_state.get("display_name", "The crop"))

	return ""


func get_harvest_failure(actor: CharacterEntity, location_root: Node, cell: Vector2i) -> String:
	if actor == null or not is_instance_valid(actor):
		return "Harvesting requires an actor."
	if actor.inventory == null:
		return "%s has no inventory." % actor.display_name
	if not _location_can_use_crops(location_root):
		return "Harvesting requires an active location."

	var location_id: String = str(location_root.get_location_grid().location_id)
	var crop_state: Dictionary = get_crop_at(location_id, cell)
	if crop_state.is_empty():
		return "There is no crop here."
	if not bool(crop_state.get("mature", false)):
		return "%s is not ready to harvest." % str(crop_state.get("display_name", "The crop"))

	var crop_definition: Dictionary = get_crop_definition(str(crop_state.get("crop_id", "")))
	var outputs: Array = crop_definition.get("harvest_outputs", []) as Array
	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var item_definition: Dictionary = _load_output_definition(output)
		if item_definition.is_empty():
			return "Harvest output could not be loaded."
		if not actor.inventory.can_add_item(item_definition, int(output.get("quantity", 1))):
			return "%s cannot carry the harvest." % actor.display_name

	return ""


func execute_plant(actor: CharacterEntity, location_root: Node, cell: Vector2i, seed_item_id: String = "") -> ActionResult:
	var failed_requirement: String = get_plant_failure(actor, location_root, cell, seed_item_id)
	if not failed_requirement.is_empty():
		return ActionResult.failed("PlantAction", _actor_id(actor), failed_requirement, { "cell": cell })

	var resolved_seed_item_id: String = seed_item_id
	if resolved_seed_item_id.is_empty():
		resolved_seed_item_id = get_seed_item_id(actor)
	var crop_definition: Dictionary = _get_crop_definition_for_seed(resolved_seed_item_id)
	var crop_id: String = str(crop_definition.get("id", ""))
	var location_id: String = str(location_root.get_location_grid().location_id)
	var planted_at: int = TimeManager.get_absolute_minutes()
	var crop_state: Dictionary = {
		"location_id": location_id,
		"cell": _cell_to_dictionary(cell),
		"crop_id": crop_id,
		"display_name": str(crop_definition.get("display_name", crop_id)),
		"seed_item_id": resolved_seed_item_id,
		"planted_at": planted_at,
		"watered": false,
		"watered_at": -1,
		"stage_id": _get_stage_id(crop_definition, 0),
		"stage_index": 0,
		"mature": false,
	}

	actor.inventory.remove_item(resolved_seed_item_id, 1)
	GameState.save_character_runtime(actor)
	_set_crop_state(location_id, cell, crop_state)
	_notify_location_crop_changed(location_root)

	var result: ActionResult = ActionResult.succeeded("PlantAction", actor.character_id, {
		"cell": cell,
		"seed_item_id": resolved_seed_item_id,
		"crop_id": crop_id,
	})
	result.add_world_change({
		"type": "crop_planted",
		"character_id": actor.character_id,
		"location_id": location_id,
		"cell": cell,
		"crop_id": crop_id,
		"seed_item_id": resolved_seed_item_id,
	})
	result.add_world_change({
		"type": "inventory_item_consumed",
		"character_id": actor.character_id,
		"item_id": resolved_seed_item_id,
		"quantity": 1,
	})
	result.add_feedback("%s planted %s." % [actor.display_name, str(crop_definition.get("display_name", crop_id))])
	crop_planted.emit(location_id, cell, crop_id)
	return result


func execute_water(actor: CharacterEntity, location_root: Node, cell: Vector2i) -> ActionResult:
	var failed_requirement: String = get_water_failure(actor, location_root, cell)
	if not failed_requirement.is_empty():
		return ActionResult.failed("WaterAction", _actor_id(actor), failed_requirement, { "cell": cell })

	var location_id: String = str(location_root.get_location_grid().location_id)
	var crop_state: Dictionary = get_crop_at(location_id, cell)
	crop_state["watered"] = true
	crop_state["watered_at"] = TimeManager.get_absolute_minutes()
	_update_single_crop_state(crop_state)
	_set_crop_state(location_id, cell, crop_state)
	_notify_location_crop_changed(location_root)

	var result: ActionResult = ActionResult.succeeded("WaterAction", actor.character_id, {
		"cell": cell,
		"crop_id": str(crop_state.get("crop_id", "")),
	})
	result.add_world_change({
		"type": "crop_watered",
		"character_id": actor.character_id,
		"location_id": location_id,
		"cell": cell,
		"crop_id": str(crop_state.get("crop_id", "")),
	})
	result.add_feedback("%s watered %s." % [actor.display_name, str(crop_state.get("display_name", "the crop"))])
	crop_watered.emit(location_id, cell, str(crop_state.get("crop_id", "")))
	return result


func execute_harvest(actor: CharacterEntity, location_root: Node, cell: Vector2i) -> ActionResult:
	var failed_requirement: String = get_harvest_failure(actor, location_root, cell)
	if not failed_requirement.is_empty():
		return ActionResult.failed("HarvestAction", _actor_id(actor), failed_requirement, { "cell": cell })

	var location_id: String = str(location_root.get_location_grid().location_id)
	var crop_state: Dictionary = get_crop_at(location_id, cell)
	var crop_id: String = str(crop_state.get("crop_id", ""))
	var crop_definition: Dictionary = get_crop_definition(crop_id)
	var outputs: Array = crop_definition.get("harvest_outputs", []) as Array
	var harvested_outputs: Array[Dictionary] = []
	for output_value in outputs:
		var output: Dictionary = output_value as Dictionary
		var item_definition: Dictionary = _load_output_definition(output)
		var quantity: int = int(output.get("quantity", 1))
		actor.inventory.add_item(item_definition, quantity)
		harvested_outputs.append({
			"item_id": str(item_definition.get("id", "")),
			"quantity": quantity,
		})

	GameState.save_character_runtime(actor)
	_remove_crop_state(location_id, cell)
	_notify_location_crop_changed(location_root)

	var result: ActionResult = ActionResult.succeeded("HarvestAction", actor.character_id, {
		"cell": cell,
		"crop_id": crop_id,
	})
	result.add_world_change({
		"type": "crop_harvested",
		"character_id": actor.character_id,
		"location_id": location_id,
		"cell": cell,
		"crop_id": crop_id,
		"outputs": harvested_outputs,
	})
	for output in harvested_outputs:
		result.add_world_change({
			"type": "harvest_output_added",
			"character_id": actor.character_id,
			"location_id": location_id,
			"crop_id": crop_id,
			"item_id": str(output.get("item_id", "")),
			"quantity": int(output.get("quantity", 1)),
		})
	result.add_feedback("%s harvested %s." % [actor.display_name, str(crop_definition.get("display_name", crop_id))])
	crop_harvested.emit(location_id, cell, crop_id)
	return result


func get_save_state() -> Dictionary:
	return {
		"crop_states": crop_states.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	crop_states = (state.get("crop_states", {}) as Dictionary).duplicate(true)
	_update_all_crops()


func _on_time_changed(_day: int, _hour: int, _minute: int) -> void:
	_update_all_crops()


func _on_session_started(_session_id: String) -> void:
	crop_states.clear()


func _load_crop_definitions() -> void:
	crop_definitions.clear()
	for crop_path in CROP_PATHS:
		var crop_definition: Dictionary = DefinitionLoader.load_crop(crop_path)
		var crop_id: String = str(crop_definition.get("id", ""))
		if crop_id.is_empty():
			continue
		crop_definitions[crop_id] = crop_definition


func _update_all_crops() -> void:
	for location_id_value in crop_states.keys():
		var location_id: String = str(location_id_value)
		var location_crops: Dictionary = crop_states[location_id] as Dictionary
		for cell_key_value in location_crops.keys():
			var cell_key: String = str(cell_key_value)
			var crop_state: Dictionary = location_crops[cell_key] as Dictionary
			if _update_single_crop_state(crop_state):
				location_crops[cell_key] = crop_state
				crop_changed.emit(location_id, _dictionary_to_cell(crop_state.get("cell", {}) as Dictionary), crop_state.duplicate(true))
		crop_states[location_id] = location_crops


func _update_single_crop_state(crop_state: Dictionary) -> bool:
	var crop_definition: Dictionary = get_crop_definition(str(crop_state.get("crop_id", "")))
	if crop_definition.is_empty():
		return false

	var start_minute: int = int(crop_state.get("planted_at", 0))
	if bool(crop_definition.get("requires_water", false)):
		if not bool(crop_state.get("watered", false)):
			start_minute = TimeManager.get_absolute_minutes()
		else:
			start_minute = int(crop_state.get("watered_at", crop_state.get("planted_at", 0)))

	var elapsed: int = max(0, TimeManager.get_absolute_minutes() - start_minute)
	var previous_stage_id: String = str(crop_state.get("stage_id", ""))
	var stage: Dictionary = _get_stage_for_elapsed(crop_definition, elapsed)
	crop_state["stage_id"] = str(stage.get("id", "seeded"))
	crop_state["stage_index"] = int(stage.get("index", 0))
	crop_state["mature"] = elapsed >= int(crop_definition.get("growth_minutes", 0))
	return previous_stage_id != str(crop_state.get("stage_id", ""))


func _get_stage_for_elapsed(crop_definition: Dictionary, elapsed_minutes: int) -> Dictionary:
	var result: Dictionary = {
		"id": "seeded",
		"index": 0,
	}
	var stages: Array = crop_definition.get("stages", []) as Array
	for index in range(stages.size()):
		var stage: Dictionary = stages[index] as Dictionary
		if elapsed_minutes >= int(stage.get("threshold", 0)):
			result = stage.duplicate(true)
			result["index"] = index

	return result


func _get_stage_id(crop_definition: Dictionary, elapsed_minutes: int) -> String:
	var stage: Dictionary = _get_stage_for_elapsed(crop_definition, elapsed_minutes)
	return str(stage.get("id", "seeded"))


func _get_crop_definition_for_seed(seed_item_id: String) -> Dictionary:
	for crop_definition_value in crop_definitions.values():
		var crop_definition: Dictionary = crop_definition_value as Dictionary
		if str(crop_definition.get("seed_item_id", "")) == seed_item_id:
			return crop_definition.duplicate(true)

	return {}


func _set_crop_state(location_id: String, cell: Vector2i, crop_state: Dictionary) -> void:
	var location_crops: Dictionary = crop_states.get(location_id, {}) as Dictionary
	location_crops[_cell_key(cell)] = crop_state.duplicate(true)
	crop_states[location_id] = location_crops
	crop_changed.emit(location_id, cell, crop_state.duplicate(true))


func _remove_crop_state(location_id: String, cell: Vector2i) -> void:
	var location_crops: Dictionary = crop_states.get(location_id, {}) as Dictionary
	location_crops.erase(_cell_key(cell))
	crop_states[location_id] = location_crops
	crop_changed.emit(location_id, cell, {})


func _location_can_use_crops(location_root: Node) -> bool:
	return location_root != null and is_instance_valid(location_root) and location_root.has_method("get_location_grid") and location_root.has_method("is_cell_plantable")


func _notify_location_crop_changed(location_root: Node) -> void:
	if location_root != null and is_instance_valid(location_root) and location_root.has_method("refresh_crop_markers"):
		location_root.refresh_crop_markers()


func _load_output_definition(output: Dictionary) -> Dictionary:
	return DefinitionLoader.load_item(str(output.get("source", "")))


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _cell_to_dictionary(cell: Vector2i) -> Dictionary:
	return {
		"x": cell.x,
		"y": cell.y,
	}


func _dictionary_to_cell(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))


func _actor_id(actor: CharacterEntity) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""

	return actor.character_id
