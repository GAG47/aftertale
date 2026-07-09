class_name LocationGraphSnapshotStore
extends RefCounted

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const LocationGraphSnapshotValidatorScript := preload("res://scripts/systems/regions/location_graph_snapshot_validator.gd")


func save_snapshot_to_path(snapshot: Dictionary, snapshot_path: String) -> Dictionary:
	if snapshot_path.is_empty():
		return _failure("save_snapshot", ["snapshot_path is required"])
	var validator: RefCounted = LocationGraphSnapshotValidatorScript.new()
	var validation_errors: Array[String] = validator.validate(snapshot)
	if not validation_errors.is_empty():
		return _failure("validate_before_save", validation_errors)
	var canonical_text: String = CanonicalDataSerializerScript.snapshot_json(snapshot)
	if canonical_text.is_empty():
		return _failure("serialize_snapshot", ["LocationGraphSnapshot could not be canonically serialized"])
	var global_path := ProjectSettings.globalize_path(snapshot_path)
	var directory_path := global_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		return _failure("save_snapshot", ["could not create snapshot directory: %s" % directory_path])
	var temp_path := "%s.tmp" % global_path
	var backup_path := "%s.bak" % global_path
	_remove_if_exists(temp_path)
	_remove_if_exists(backup_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _failure("save_snapshot", ["could not open temporary snapshot for write: %s" % snapshot_path])
	file.store_string(canonical_text)
	file.flush()
	file = null
	var had_existing := FileAccess.file_exists(global_path)
	if had_existing:
		var backup_error := DirAccess.rename_absolute(global_path, backup_path)
		if backup_error != OK:
			_remove_if_exists(temp_path)
			return _failure("save_snapshot", ["could not prepare existing snapshot for replacement: %s" % snapshot_path])
	var replace_error := DirAccess.rename_absolute(temp_path, global_path)
	if replace_error != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_path, global_path)
		_remove_if_exists(temp_path)
		return _failure("save_snapshot", ["could not atomically replace snapshot: %s" % snapshot_path])
	_remove_if_exists(backup_path)
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"snapshot_path": snapshot_path,
	}


func load_snapshot_from_path(snapshot_path: String) -> Dictionary:
	if snapshot_path.is_empty():
		return _failure("load_snapshot", ["snapshot_path is required"])
	var file := FileAccess.open(snapshot_path, FileAccess.READ)
	if file == null:
		return _failure("load_snapshot", ["could not open snapshot for read: %s" % snapshot_path])
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return _failure("load_snapshot", ["snapshot file must contain a JSON object: %s" % snapshot_path])
	var snapshot: Dictionary = parsed as Dictionary
	var validator: RefCounted = LocationGraphSnapshotValidatorScript.new()
	var validation_errors: Array[String] = validator.validate(snapshot)
	if not validation_errors.is_empty():
		return _failure("validate_after_load", validation_errors, snapshot)
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"snapshot_path": snapshot_path,
		"location_graph_snapshot": snapshot,
	}


func _remove_if_exists(global_path: String) -> void:
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)


func _failure(stage: String, errors: Array[String], snapshot: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"stage": stage,
		"errors": errors.duplicate(),
		"warnings": [],
		"location_graph_snapshot": snapshot,
	}
