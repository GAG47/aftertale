class_name RegionLocationGraphCompiler
extends RefCounted

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const COMPILER_VERSION := "v67.1"


func validate_region_input_result(input: Dictionary) -> Dictionary:
	var region_input: RefCounted = RegionInputScript.new()
	var errors: Array[String] = region_input.configure(input)
	if not errors.is_empty():
		return _failure("validate_region_input", errors, {})
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"region_input": region_input.to_dictionary(),
		"compiler_version": COMPILER_VERSION,
	}


func compile_to_location_graph_result(input: Dictionary) -> Dictionary:
	var validation_result := validate_region_input_result(input)
	if not bool(validation_result.get("success", false)):
		return validation_result
	return _failure("semantic_roles_to_location_graph", [
		"v67.2 semantic role expansion is not implemented; RegionInput is valid, but v67.1 cannot produce a Location Graph.",
	], {
		"region_input": validation_result.get("region_input", {}),
	})


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result
