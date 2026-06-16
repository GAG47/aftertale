extends RefCounted

const TileSceneCompilerScript := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")

var _root: Node


func run(root: Node) -> bool:
	_root = root
	DefinitionLoader.clear_cache()
	var first := DefinitionLoader.load_resolved_location("res://data/locations/generated_settlement.json")
	DefinitionLoader.clear_cache()
	var second := DefinitionLoader.load_resolved_location("res://data/locations/generated_settlement.json")
	if first.is_empty() or second.is_empty():
		return _fail("v63 compiled settlement location must load")
	if JSON.stringify(first.get("generation_summary", {})) != JSON.stringify(second.get("generation_summary", {})):
		return _fail("v63 compiled settlement must be deterministic for a fixed seed")

	if not _compiled_location_is_valid(first):
		return false
	if not _compiled_scene_instantiates(first):
		return false

	print("v63 settlement scene compiler smoke test passed")
	return true


func _compiled_location_is_valid(location_data: Dictionary) -> bool:
	var compiler: RefCounted = TileSceneCompilerScript.new()
	var errors: Array[String] = compiler.validate_compiled_location(location_data)
	if not errors.is_empty():
		return _fail("v63 compiled location contract failed: %s" % ", ".join(errors))

	var grid := LocationGrid.from_dictionary(location_data)
	if grid.location_id != "generated_settlement":
		return _fail("v63 compiled location id mismatch")
	if grid.width <= 0 or grid.height <= 0:
		return _fail("v63 compiled grid must have dimensions")

	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	if str(summary.get("type", "")) != "settlement_blueprint_v63":
		return _fail("v63 generation summary must identify settlement compiler output")
	if int(summary.get("road_count", 0)) < 2:
		return _fail("v63 compiler must preserve roads")
	if int(summary.get("plot_count", 0)) < 4:
		return _fail("v63 compiler must preserve plots")
	if int(summary.get("building_count", 0)) < 3:
		return _fail("v63 compiler must preserve buildings")
	if not _uses_settlement_plot_terrain(location_data):
		return _fail("v63 compiler must use settlement plot terrain instead of farm/field terrain for generated plots")
	if _has_field_plot_terrain(location_data):
		return _fail("v63 generated settlement must not expose farm field terrain for settlement plots")
	if not _road_tiles_are_visible(location_data):
		return _fail("v63 compiler must preserve visible road tiles after plot compilation")

	if (location_data.get("roofs", []) as Array).is_empty():
		return _fail("v63 compiler must create visible building roofs")
	if (location_data.get("collision_overrides", []) as Array).is_empty():
		return _fail("v63 compiler must create building collision")
	if not _has_debug_source_overlay(location_data):
		return _fail("v63 compiler must create debug overlays with blueprint source ids")
	if not _has_player_spawn(location_data):
		return _fail("v63 compiled scene must include player spawn data")
	return true


func _compiled_scene_instantiates(location_data: Dictionary) -> bool:
	var scene := load("res://scenes/locations/generated_settlement.tscn") as PackedScene
	if scene == null:
		return _fail("v63 generated settlement scene must load")
	var instance := scene.instantiate()
	_root.add_child(instance)
	if not instance.has_method("get_location_grid"):
		_cleanup_instance(instance)
		return _fail("v63 generated settlement scene must expose LocationRoot grid")
	var grid: LocationGrid = instance.get_location_grid() as LocationGrid
	if grid == null or not grid.is_valid():
		_cleanup_instance(instance)
		return _fail("v63 generated settlement scene must initialize a valid LocationGrid")
	var summary: Dictionary = instance.get_location_summary() if instance.has_method("get_location_summary") else {}
	if str(summary.get("id", "")) != str(location_data.get("id", "")):
		_cleanup_instance(instance)
		return _fail("v63 generated scene summary must match compiled location")
	if int(summary.get("character_count", 0)) < 1:
		_cleanup_instance(instance)
		return _fail("v63 generated scene must spawn the player")
	_cleanup_instance(instance)
	return true


func _cleanup_instance(instance: Node) -> void:
	if instance == null:
		return
	if instance.get_parent() != null:
		instance.get_parent().remove_child(instance)
	instance.queue_free()


func _has_debug_source_overlay(location_data: Dictionary) -> bool:
	for overlay_value in (location_data.get("floor_overlays", []) as Array):
		var overlay: Dictionary = overlay_value as Dictionary
		if str(overlay.get("presentation_layer", "")) == "debug" and not str(overlay.get("source_blueprint_id", "")).is_empty():
			return true
	return false


func _has_player_spawn(location_data: Dictionary) -> bool:
	for character_value in (location_data.get("characters", []) as Array):
		var character: Dictionary = character_value as Dictionary
		if str(character.get("id", "")) == "debug_player" and bool(character.get("spawn_at_entrance", false)):
			return true
	return false


func _uses_settlement_plot_terrain(location_data: Dictionary) -> bool:
	var terrain: Dictionary = location_data.get("terrain", {}) as Dictionary
	for terrain_value in terrain.values():
		var terrain_row: Dictionary = terrain_value as Dictionary
		if str(terrain_row.get("id", "")) == "settlement_plot":
			return true
	return false


func _has_field_plot_terrain(location_data: Dictionary) -> bool:
	var terrain: Dictionary = location_data.get("terrain", {}) as Dictionary
	for terrain_value in terrain.values():
		var terrain_row: Dictionary = terrain_value as Dictionary
		if str(terrain_row.get("id", "")) == "field_plot":
			return true
	return false


func _road_tiles_are_visible(location_data: Dictionary) -> bool:
	var road_count := 0
	for row_value in (location_data.get("tiles", []) as Array):
		var row := str(row_value)
		for index in range(row.length()):
			if row.substr(index, 1) == "p":
				road_count += 1
	return road_count > 0


func _fail(message: String) -> bool:
	push_error(message)
	return false
