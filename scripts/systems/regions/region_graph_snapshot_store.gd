class_name RegionGraphSnapshotStore
extends RefCounted

const RegionLocationGraphValidatorScript := preload("res://scripts/systems/regions/region_location_graph_validator.gd")

const DEFAULT_SNAPSHOT_PATH := "user://region_graph_snapshots/default_region_graph.json"


func save_snapshot_to_path(snapshot: Dictionary, snapshot_path: String = DEFAULT_SNAPSHOT_PATH) -> Dictionary:
	var validator: RefCounted = RegionLocationGraphValidatorScript.new()
	var errors: Array[String] = validator.validate(snapshot)
	if not errors.is_empty():
		return _failure("validate_before_save", errors)
	if snapshot_path.is_empty():
		return _failure("save_snapshot", ["snapshot_path is empty"])
	var dir_path := snapshot_path.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	if dir_error != OK:
		return _failure("save_snapshot", ["could not create snapshot directory: %s" % dir_path])
	var file := FileAccess.open(snapshot_path, FileAccess.WRITE)
	if file == null:
		return _failure("save_snapshot", ["could not open snapshot for write: %s" % snapshot_path])
	file.store_string(JSON.stringify(snapshot, "\t"))
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"snapshot_path": snapshot_path,
	}


func load_snapshot_from_path(snapshot_path: String = DEFAULT_SNAPSHOT_PATH) -> Dictionary:
	if snapshot_path.is_empty():
		return _failure("load_snapshot", ["snapshot_path is empty"])
	var file := FileAccess.open(snapshot_path, FileAccess.READ)
	if file == null:
		return _failure("load_snapshot", ["could not open snapshot for read: %s" % snapshot_path])
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return _failure("load_snapshot", ["snapshot file must contain a JSON object: %s" % snapshot_path])
	var snapshot: Dictionary = parsed as Dictionary
	var validator: RefCounted = RegionLocationGraphValidatorScript.new()
	var errors: Array[String] = validator.validate(snapshot)
	if not errors.is_empty():
		return _failure("validate_after_load", errors, snapshot)
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"snapshot_path": snapshot_path,
		"snapshot": snapshot,
	}


func _failure(stage: String, errors: Array[String], snapshot: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"stage": stage,
		"errors": errors.duplicate(),
		"warnings": [],
		"snapshot": snapshot,
	}
