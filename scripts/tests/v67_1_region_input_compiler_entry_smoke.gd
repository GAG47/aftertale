extends Node

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")

const DEFAULT_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const MAIN_SCRIPT_PATH := "res://scripts/core/main.gd"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_default_region_input_valid():
		return
	if not _assert_compile_entry_exposes_v67_2_boundary():
		return
	if not _assert_invalid_inputs_fail():
		return
	if not _assert_main_path_no_longer_uses_old_world_generator():
		return
	if not _assert_old_fixture_file_removed_from_main_data():
		return
	print("v67.1 RegionInput compiler entry smoke test passed")
	get_tree().quit(0)


func _assert_default_region_input_valid() -> bool:
	var data := _load_json(DEFAULT_REGION_INPUT_PATH)
	if data.is_empty():
		_fail("v67.1 default RegionInput is missing: %s" % DEFAULT_REGION_INPUT_PATH)
		return false
	var region_input: RefCounted = RegionInputScript.new()
	var errors: Array[String] = region_input.configure(data)
	if not errors.is_empty():
		_fail("v67.1 default RegionInput failed schema validation: %s" % str(errors))
		return false
	if str(data.get("region_id", "")).contains(str(data.get("display_name", ""))):
		_fail("v67.1 region_id must not be derived from display_name")
		return false
	return true


func _assert_compile_entry_exposes_v67_2_boundary() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_to_location_graph_result(_load_json(DEFAULT_REGION_INPUT_PATH))
	if bool(result.get("success", false)):
		_fail("v67.1 compiler must not pretend to produce a Location Graph before v67.2")
		return false
	var errors_text := str(result.get("errors", []))
	if not errors_text.contains("v67.2 semantic role expansion is not implemented"):
		_fail("v67.1 compiler did not expose the v67.2 boundary: %s" % errors_text)
		return false
	if str(result.get("stage", "")) != "semantic_roles_to_location_graph":
		_fail("v67.1 compiler failed at the wrong stage: %s" % str(result.get("stage", "")))
		return false
	return true


func _assert_invalid_inputs_fail() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var missing_type: Dictionary = _load_json(DEFAULT_REGION_INPUT_PATH)
	missing_type.erase("region_type")
	var missing_type_result: Dictionary = compiler.validate_region_input_result(missing_type)
	if bool(missing_type_result.get("success", false)):
		_fail("v67.1 RegionInput without region_type unexpectedly passed")
		return false
	if not str(missing_type_result.get("errors", [])).contains("region_type is missing"):
		_fail("v67.1 missing region_type did not produce a clear error: %s" % str(missing_type_result.get("errors", [])))
		return false

	var display_name_id: Dictionary = _load_json(DEFAULT_REGION_INPUT_PATH)
	display_name_id["region_id"] = "Oak Crossing"
	var display_name_result: Dictionary = compiler.validate_region_input_result(display_name_id)
	if bool(display_name_result.get("success", false)):
		_fail("v67.1 display-name-like region_id unexpectedly passed")
		return false
	if not str(display_name_result.get("errors", [])).contains("region.<scope>.<region_type>.<slug>.rg_####"):
		_fail("v67.1 bad region_id did not report the id template: %s" % str(display_name_result.get("errors", [])))
		return false
	return true


func _assert_main_path_no_longer_uses_old_world_generator() -> bool:
	var text := _load_text(MAIN_SCRIPT_PATH)
	if text.is_empty():
		_fail("v67.1 could not read main.gd")
		return false
	for token in ["WorldGraphGenerator", "DEFAULT_WORLD_ID", "DEFAULT_WORLD_SEED", "DEFAULT_REGION_PROFILE_ID", "temperate_frontier"]:
		if text.contains(token):
			_fail("v67.1 main path still references old world graph generator token: %s" % token)
			return false
	if not text.contains("RegionLocationGraphCompiler"):
		_fail("v67.1 main path does not use RegionLocationGraphCompiler")
		return false
	return true


func _assert_old_fixture_file_removed_from_main_data() -> bool:
	if FileAccess.file_exists("res://data/worlds/test_world.json"):
		_fail("v67.1 old graph fixture still exists in main data: data/worlds/test_world.json")
		return false
	return true


func _load_json(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _load_text(resource_path: String) -> String:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
