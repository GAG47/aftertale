class_name WorldGraphCompiler
extends RefCounted

const WorldGraphBlueprintScript := preload("res://scripts/systems/world/world_graph_blueprint.gd")
const WorldLocationGraphScript := preload("res://scripts/systems/world/world_location_graph.gd")


func compile_to_world_data(blueprint: Variant) -> Dictionary:
	if blueprint == null:
		return {}
	if blueprint is Dictionary:
		return (blueprint as Dictionary).duplicate(true)
	if blueprint.has_method("to_dictionary"):
		return (blueprint.to_dictionary() as Dictionary).duplicate(true)
	return {}


func compile_to_graph(blueprint: Variant) -> Dictionary:
	var data := compile_to_world_data(blueprint)
	if data.is_empty():
		return {
			"success": false,
			"errors": ["world graph blueprint is empty"],
		}

	var blueprint_object: RefCounted = WorldGraphBlueprintScript.new()
	blueprint_object.configure(data)
	var blueprint_errors: Array[String] = blueprint_object.validate()
	if not blueprint_errors.is_empty():
		return {
			"success": false,
			"errors": blueprint_errors,
			"world_data": data,
		}

	var graph: RefCounted = WorldLocationGraphScript.new()
	var graph_errors: Array[String] = graph.configure(data)
	if not graph_errors.is_empty():
		return {
			"success": false,
			"errors": graph_errors,
			"world_data": data,
		}

	return {
		"success": true,
		"errors": [],
		"world_data": data,
		"graph": graph,
	}
