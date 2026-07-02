class_name BuildingInteriorGenerator
extends RefCounted

const DEFAULT_TILE_SIZE := 32
const WIDTH := 10
const HEIGHT := 8

var _context: Dictionary = {}
var _generated: Dictionary = {}


func generate_location(source_data: Dictionary, context: Dictionary = {}) -> Dictionary:
	_context = context.duplicate(true)
	var building_instance: Dictionary = _context.get("building_instance", {}) as Dictionary
	var archetype_id := str(_context.get("archetype_id", building_instance.get("archetype_id", "residential")))
	var display_name := str(_context.get("display_name", building_instance.get("display_name", "Building")))
	var location_id := str(_context.get("location_id", source_data.get("id", "building_interior_template")))
	var entry_entrance_id := str(_context.get("entry_entrance_id", "entry"))
	var exit_anchor_id := str(_context.get("exit_anchor_id", "exit"))
	_generated = {
		"id": location_id,
		"display_name": "%s Interior" % display_name,
		"size": { "width": WIDTH, "height": HEIGHT },
		"tile_size": int(source_data.get("tile_size", DEFAULT_TILE_SIZE)),
		"tiles": [
			"xxxxxxxxxx",
			"xiiiiiiiix",
			"xiiiiiiiix",
			"xiiiiiiiix",
			"xiiiiiiiix",
			"xiiiiiiiix",
			"xiiiiiiiix",
			"xxxxxixxxx",
		],
		"terrain": _terrain_definitions(),
		"zones": [
			{
				"id": "interior_room",
				"type": "interior",
				"display_name": "%s Interior" % display_name,
				"bounds": { "x": 1, "y": 1, "w": 8, "h": 6 },
			},
		],
		"floor_overlays": [],
		"floor_decorations": [],
		"structures": [],
		"roofs": [],
		"entrances": [
			{ "id": entry_entrance_id, "grid_position": { "x": 5, "y": 6 }, "facing": str(_context.get("entry_facing", "up")) },
		],
		"anchors": [
			{ "id": entry_entrance_id, "kind": "entry", "grid_position": { "x": 5, "y": 6 }, "facing": str(_context.get("entry_facing", "up")) },
			{ "id": exit_anchor_id, "kind": "exit", "grid_position": { "x": 5, "y": 6 }, "facing": "down" },
			{ "id": "primary", "kind": _primary_anchor_kind(archetype_id), "grid_position": _primary_anchor_cell(archetype_id), "facing": _primary_anchor_facing(archetype_id) },
		],
		"exits": [],
		"shops": [{ "id": "field_stall" }],
		"objects": [],
		"characters": [
			{
				"id": "debug_player",
				"source": "res://data/characters/debug_player.json",
				"spawn_at_entrance": true,
				"facing": "up",
			},
		],
		"state": {
			"danger_level": 0,
			"owner_faction": "field_neutral",
			"generation": "building_interior",
			"building_instance_id": str(building_instance.get("id", "")),
			"exterior_location_id": str(_context.get("exterior_location_id", "")),
			"archetype_id": archetype_id,
		},
	}

	for character_value in (_context.get("characters", []) as Array):
		(_generated.get("characters", []) as Array).append((character_value as Dictionary).duplicate(true))
	_add_return_door()
	_apply_role_content(archetype_id)
	return _generated


func _terrain_definitions() -> Dictionary:
	return {
		"i": { "id": "interior_floor", "label": "Interior Floor", "walkable": true, "color": "#7b6145" },
		"x": { "id": "interior_wall", "label": "Interior Wall", "walkable": false, "blocks_sight": true, "color": "#4f4a42" },
	}


func _primary_anchor_kind(archetype_id: String) -> String:
	match archetype_id:
		"workshop":
			return "workbench"
		"shop":
			return "shop_counter"
		"tavern":
			return "meal"
		"storage_shed":
			return "storage"
		"guardhouse":
			return "guard_post"
		_:
			return "bed"


func _primary_anchor_cell(archetype_id: String) -> Dictionary:
	match archetype_id:
		"tavern":
			return { "x": 6, "y": 4 }
		_:
			return { "x": 4, "y": 4 }


func _primary_anchor_facing(archetype_id: String) -> String:
	match archetype_id:
		"shop":
			return "down"
		"tavern":
			return "right"
		_:
			return "left"


func _add_return_door() -> void:
	var location_id := str(_context.get("location_id", ""))
	_add_object({
		"id": "interior_return_door",
		"display_name": "Door",
		"grid_position": { "x": 5, "y": 7 },
		"blocks_movement": true,
		"kind": "door",
		"is_inspectable": true,
		"is_usable": true,
		"facility_type": "scene_transition",
		"target_scene_path": "__return__",
		"target_entrance_id": "__return__",
		"world_exit_id": str(_context.get("world_leave_exit_id", "%s.leave" % location_id)),
		"inspect_text": "The door leads back outside.",
	})


func _apply_role_content(archetype_id: String) -> void:
	match archetype_id:
		"workshop":
			_add_structure("workbench", Vector2i(3, 3), { "blocks_movement": true })
			_add_object(_facility_object("interior_workbench", "Workbench", "workbench", Vector2i(4, 3), {
				"facility_type": "crafting",
				"recipe_ids": ["debug_tool", "packed_snack", "material_scroll_test"],
				"inspect_text": "A workbench inside the generated workshop interior.",
			}))
		"shop":
			_add_object(_facility_object("interior_shop_counter", "Shop Counter", "shop", Vector2i(4, 3), {
				"facility_type": "shop",
				"shop_id": "field_stall",
				"vendor_character_id": "debug_villager",
				"inspect_text": "A generated shop counter inside the building.",
			}))
			_add_structure("goods_crate", Vector2i(6, 3), { "blocks_movement": true })
		"tavern":
			_add_object(_facility_object("interior_tavern_counter", "Tavern Counter", "inn", Vector2i(4, 3), {
				"facility_type": "rest",
				"rest_type": "inn",
				"cost": 10,
				"target_hour": 6,
				"target_minute": 0,
				"full_restore": true,
				"inspect_text": "A generated tavern counter inside the building.",
			}))
			_add_structure("table_set", Vector2i(6, 3), { "blocks_movement": true })
		"storage_shed":
			_add_structure("material_crates", Vector2i(3, 3), { "blocks_movement": true })
			_add_structure("goods_crate", Vector2i(5, 3), { "blocks_movement": true })
		"guardhouse":
			_add_structure("weapon_rack", Vector2i(3, 3), { "blocks_movement": true })
			_add_structure("counter", Vector2i(5, 3), { "blocks_movement": true })
		_:
			_add_object(_facility_object("interior_bed", "Bed", "bed", Vector2i(3, 3), {
				"facility_type": "rest",
				"rest_type": "bed",
				"target_hour": 6,
				"target_minute": 0,
				"full_restore": true,
				"inspect_text": "A bed inside the generated home interior.",
			}))
			_add_structure("barrel", Vector2i(6, 3), { "blocks_movement": true })


func _facility_object(object_id: String, display_name: String, kind: String, cell: Vector2i, extra: Dictionary) -> Dictionary:
	var data := {
		"id": object_id,
		"display_name": display_name,
		"grid_position": _dict_cell(cell),
		"blocks_movement": true,
		"kind": kind,
		"is_inspectable": true,
		"is_usable": true,
	}
	data.merge(extra, true)
	return data


func _add_structure(structure_type: String, cell: Vector2i, extra: Dictionary = {}) -> void:
	var entry := {
		"type": structure_type,
		"grid_position": _dict_cell(cell),
	}
	entry.merge(extra, true)
	(_generated.get("structures", []) as Array).append(entry)


func _add_object(object_data: Dictionary) -> void:
	(_generated.get("objects", []) as Array).append(object_data)


func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }
