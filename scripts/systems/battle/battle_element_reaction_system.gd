class_name BattleElementReactionSystem
extends RefCounted

const BattleTileStateScript := preload("res://scripts/systems/battle/battle_tile_state.gd")
const MAX_LIGHTNING_SPREAD_DISTANCE := 2
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.DOWN,
]
const STATE_DEFINITIONS := {
	"burning": {
		"duration_rounds": 2,
		"tags": ["danger", "fire"],
	},
	"wet": {
		"duration_rounds": 3,
		"tags": ["water", "conductive"],
	},
	"frozen": {
		"duration_rounds": 2,
		"tags": ["ice", "slippery"],
	},
	"electrified": {
		"duration_rounds": 1,
		"tags": ["danger", "lightning", "conductive"],
	},
}


static func apply_element(effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	var battle_state: BattleState = context.get("battle_state") as BattleState
	if battle_state == null or result == null:
		return

	var element: String = str(effect.get("element", ""))
	var intensity: int = max(1, int(effect.get("intensity", 1)))
	for cell in _get_affected_cells(context):
		_resolve_cell(element, intensity, cell, context, result)


static func _resolve_cell(element: String, intensity: int, cell: Vector2i, context: Dictionary, result: ActionResult) -> void:
	var battle_state: BattleState = context.get("battle_state") as BattleState
	var current_state = battle_state.get_tile_state_at(cell)
	var current_state_id: String = current_state.id if current_state != null else ""

	match element:
		"fire":
			_resolve_fire(cell, current_state_id, intensity, context, result)
		"water":
			_resolve_water(cell, current_state_id, intensity, context, result)
		"ice":
			_resolve_ice(cell, current_state_id, intensity, context, result)
		"lightning":
			_resolve_lightning(cell, current_state_id, intensity, context, result)


static func _resolve_fire(cell: Vector2i, current_state_id: String, intensity: int, context: Dictionary, result: ActionResult) -> void:
	match current_state_id:
		"wet":
			_remove_state(cell, "wet", "evaporated", context, result)
			_record_reaction("fire_evaporates_wet", "fire", cell, "wet", "", context, result, "Fire evaporated the wet surface.")
		"frozen":
			_replace_state(cell, "frozen", "wet", intensity, "melted", context, result)
			_record_reaction("fire_melts_frozen", "fire", cell, "frozen", "wet", context, result, "Fire melted the frozen surface into water.")
		"burning":
			_apply_state(cell, "burning", intensity, context, result)
			_record_reaction("fire_refreshes_burning", "fire", cell, "burning", "burning", context, result, "The burning surface intensified.")
		_:
			_replace_state(cell, current_state_id, "burning", intensity, "ignited", context, result)
			_record_reaction("fire_ignites_surface", "fire", cell, current_state_id, "burning", context, result, "The ground caught fire.")


static func _resolve_water(cell: Vector2i, current_state_id: String, intensity: int, context: Dictionary, result: ActionResult) -> void:
	match current_state_id:
		"burning":
			_replace_state(cell, "burning", "wet", intensity, "extinguished", context, result)
			_record_reaction("water_extinguishes_fire", "water", cell, "burning", "wet", context, result, "Water extinguished the fire and left the ground wet.")
		"electrified":
			_apply_state(cell, "electrified", intensity, context, result)
			_record_reaction("water_refreshes_electrified", "water", cell, "electrified", "electrified", context, result, "Water sustained the electrified surface.")
		"frozen":
			_record_reaction("water_on_frozen", "water", cell, "frozen", "frozen", context, result, "Water could not displace the frozen surface.")
		_:
			_replace_state(cell, current_state_id, "wet", intensity, "soaked", context, result)
			_record_reaction("water_creates_wet", "water", cell, current_state_id, "wet", context, result, "The ground became wet.")


static func _resolve_ice(cell: Vector2i, current_state_id: String, intensity: int, context: Dictionary, result: ActionResult) -> void:
	match current_state_id:
		"wet":
			_replace_state(cell, "wet", "frozen", intensity, "frozen", context, result)
			_record_reaction("ice_freezes_wet", "ice", cell, "wet", "frozen", context, result, "Ice froze the wet surface.")
		"burning":
			_remove_state(cell, "burning", "quenched_by_ice", context, result)
			_record_reaction("ice_quenches_fire", "ice", cell, "burning", "", context, result, "Ice quenched the burning surface.")
		"frozen":
			_apply_state(cell, "frozen", intensity, context, result)
			_record_reaction("ice_refreshes_frozen", "ice", cell, "frozen", "frozen", context, result, "The frozen surface was reinforced.")
		_:
			_record_reaction("ice_no_surface_reaction", "ice", cell, current_state_id, current_state_id, context, result, "Ice found no water to freeze.")


static func _resolve_lightning(cell: Vector2i, current_state_id: String, intensity: int, context: Dictionary, result: ActionResult) -> void:
	match current_state_id:
		"wet":
			_replace_state(cell, "wet", "electrified", intensity, "electrified", context, result)
			_record_reaction("lightning_electrifies_wet", "lightning", cell, "wet", "electrified", context, result, "Lightning electrified the wet surface.")
			_spread_lightning_from(cell, intensity, context, result)
		"electrified":
			_apply_state(cell, "electrified", intensity, context, result)
			_record_reaction("lightning_refreshes_electrified", "lightning", cell, "electrified", "electrified", context, result, "The electrified surface intensified.")
			_spread_lightning_from(cell, intensity, context, result)
		_:
			_record_reaction("lightning_no_surface_reaction", "lightning", cell, current_state_id, current_state_id, context, result, "Lightning struck without creating a surface.")


static func _spread_lightning_from(origin: Vector2i, intensity: int, context: Dictionary, result: ActionResult) -> void:
	var battle_state: BattleState = context.get("battle_state") as BattleState
	var visited: Dictionary = { battle_state.cell_key(origin): true }
	var queue: Array[Dictionary] = [{ "cell": origin, "distance": 0 }]

	while not queue.is_empty():
		var entry: Dictionary = queue.pop_front() as Dictionary
		var current_cell: Vector2i = entry.get("cell", origin) as Vector2i
		var distance: int = int(entry.get("distance", 0))
		if distance >= MAX_LIGHTNING_SPREAD_DISTANCE:
			continue

		for direction in CARDINAL_DIRECTIONS:
			var next_cell: Vector2i = current_cell + direction
			var key: String = battle_state.cell_key(next_cell)
			if visited.has(key):
				continue
			visited[key] = true
			if battle_state.grid == null or not battle_state.grid.in_bounds(next_cell):
				continue

			var next_state = battle_state.get_tile_state_at(next_cell)
			if next_state == null or next_state.id != "wet":
				continue

			_replace_state(next_cell, "wet", "electrified", intensity, "lightning_spread", context, result)
			_record_reaction(
				"lightning_spreads_through_wet",
				"lightning",
				next_cell,
				"wet",
				"electrified",
				context,
				result,
				"Lightning spread through connected wet ground."
			)
			queue.append({ "cell": next_cell, "distance": distance + 1 })


static func _replace_state(
	cell: Vector2i,
	previous_state_id: String,
	next_state_id: String,
	intensity: int,
	reason: String,
	context: Dictionary,
	result: ActionResult
) -> void:
	if not previous_state_id.is_empty() and previous_state_id != next_state_id:
		_remove_state(cell, previous_state_id, reason, context, result)
	if not next_state_id.is_empty():
		_apply_state(cell, next_state_id, intensity, context, result)


static func _apply_state(cell: Vector2i, state_id: String, intensity: int, context: Dictionary, result: ActionResult) -> void:
	var battle_state: BattleState = context.get("battle_state") as BattleState
	var definition: Dictionary = STATE_DEFINITIONS.get(state_id, {}) as Dictionary
	var state_effect: Dictionary = {
		"state_id": state_id,
		"layer": "surface",
		"duration_rounds": int(definition.get("duration_rounds", 1)),
		"intensity": intensity,
		"tags": (definition.get("tags", []) as Array).duplicate(),
	}
	var tile_state = BattleTileStateScript.from_effect(state_effect, cell, context)
	battle_state.apply_tile_state(tile_state, result)


static func _remove_state(cell: Vector2i, state_id: String, reason: String, context: Dictionary, result: ActionResult) -> void:
	var battle_state: BattleState = context.get("battle_state") as BattleState
	battle_state.remove_tile_state(cell, state_id, result, reason)


static func _record_reaction(
	reaction_id: String,
	element: String,
	cell: Vector2i,
	previous_state_id: String,
	result_state_id: String,
	context: Dictionary,
	result: ActionResult,
	feedback: String
) -> void:
	var battle_state: BattleState = context.get("battle_state") as BattleState
	var caster: BattleUnitState = context.get("caster") as BattleUnitState
	var skill: Dictionary = context.get("skill", {}) as Dictionary
	battle_state.record_reaction({
		"reaction_id": reaction_id,
		"element": element,
		"cell": cell,
		"previous_state_id": previous_state_id,
		"result_state_id": result_state_id,
		"source_character_id": caster.character_id if caster != null else "",
		"source_skill_id": str(skill.get("id", "")),
		"round": battle_state.round_number,
		"turn_index": battle_state.turn_index,
		"feedback": feedback,
	}, result)


static func _get_affected_cells(context: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var affected_cells: Array = context.get("affected_cells", []) as Array
	for cell_value in affected_cells:
		var cell: Vector2i = cell_value as Vector2i
		if not result.has(cell):
			result.append(cell)
	if result.is_empty():
		result.append(context.get("target_cell", Vector2i.ZERO) as Vector2i)
	return result
