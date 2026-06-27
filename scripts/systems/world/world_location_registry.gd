class_name WorldLocationRegistry
extends RefCounted

const WildLocationCompilerScript := preload("res://scripts/systems/terrain/wild_location_compiler.gd")
const DEFAULT_WILD_SCENE_PATH := "res://scenes/locations/test_wild_plain.tscn"
const DEFAULT_INTERIOR_SCENE_PATH := "res://scenes/locations/generated_building_interior.tscn"
const DEFAULT_INTERIOR_DATA_PATH := "res://data/locations/generated_building_interior.json"


func resolve_location(graph: Variant, runtime: Variant, location_id: String) -> Dictionary:
	if graph == null or runtime == null:
		return _failure("world registry requires graph and runtime")
	if location_id.is_empty():
		return _failure("target location_id is empty")

	var spec: Dictionary = graph.get_location_spec(location_id)
	if spec.is_empty():
		return _failure("unknown world location: %s" % location_id)

	if runtime.has_location(location_id):
		return {
			"success": true,
			"location_id": location_id,
			"location_data": runtime.get_location_data(location_id),
			"scene_path": _scene_path_for_spec(spec),
			"generated_or_loaded": "runtime",
			"seed": _seed_for_spec(graph, spec),
			"metadata": runtime.get_location_metadata(location_id),
			"warnings": [],
		}

	var source_type := str(spec.get("source_type", "static_scene"))
	var location_data: Dictionary = {}
	var generated_or_loaded := "loaded"
	var warnings: Array = []
	match source_type:
		"static_scene":
			location_data = _materialize_static_location(spec)
			if location_data.is_empty():
				return _failure("could not materialize static location: %s" % location_id)
			generated_or_loaded = "loaded"
		"generated":
			var generated_result: Dictionary = _materialize_generated_location(graph, spec)
			if not bool(generated_result.get("success", false)):
				return generated_result
			location_data = generated_result.get("location_data", {}) as Dictionary
			generated_or_loaded = "generated"
			warnings = (generated_result.get("warnings", []) as Array).duplicate()
		_:
			return _failure("unsupported location source_type: %s" % source_type)

	if str(location_data.get("id", "")) != location_id:
		location_data["id"] = location_id
	if not spec.get("display_name", "").is_empty():
		location_data["display_name"] = str(spec.get("display_name", location_id))
	warnings.append_array(synchronize_graph_from_location_data(graph, location_data))

	var metadata := {
		"location_id": location_id,
		"location_kind": str(spec.get("location_kind", "")),
		"source_type": source_type,
		"generator_id": str(spec.get("generator_id", "")),
		"generator_profile_id": str(spec.get("generator_profile_id", "")),
		"seed": _seed_for_spec(graph, spec),
		"scene_path": _scene_path_for_spec(spec),
		"data_path": str(spec.get("data_path", "")),
	}
	runtime.register_location(location_id, location_data, metadata, generated_or_loaded == "generated")

	return {
		"success": true,
		"location_id": location_id,
		"location_data": location_data.duplicate(true),
		"scene_path": _scene_path_for_spec(spec),
		"generated_or_loaded": generated_or_loaded,
		"seed": _seed_for_spec(graph, spec),
		"metadata": metadata,
		"warnings": warnings,
	}


func _materialize_static_location(spec: Dictionary) -> Dictionary:
	var data_path := str(spec.get("data_path", ""))
	if data_path.is_empty():
		var location_id := str(spec.get("location_id", ""))
		data_path = "res://data/locations/%s.json" % location_id
	return DefinitionLoader.load_resolved_location(data_path)


func _materialize_generated_location(graph: Variant, spec: Dictionary) -> Dictionary:
	var generator_id := str(spec.get("generator_id", ""))
	match generator_id:
		"wild_terrain":
			var source_data := _wild_source_data(graph, spec)
			var compiler: RefCounted = WildLocationCompilerScript.new()
			var location_data: Dictionary = compiler.generate_location(source_data, _wild_generation_context(spec))
			var errors: Array[String] = compiler.validate_location(location_data)
			if not errors.is_empty():
				return _failure("generated_wild validation failed: %s" % str(errors))
			return {
				"success": true,
				"location_data": location_data,
				"warnings": [],
			}
		"building_interior", "settlement_interior":
			var interior_data := _materialize_building_interior(spec)
			if interior_data.is_empty():
				return _failure("could not materialize building interior: %s" % str(spec.get("location_id", "")))
			return {
				"success": true,
				"location_data": interior_data,
				"warnings": [],
			}
		"generated_settlement":
			return _failure("generated_settlement world locations are reserved but not implemented by the world registry yet")
		_:
			return _failure("unsupported generator_id: %s" % generator_id)


func synchronize_graph_from_runtime(graph: Variant, runtime: Variant) -> Array:
	var warnings: Array = []
	if graph == null or runtime == null:
		return warnings
	for location_id_value in runtime.generated_locations_by_id.keys():
		var location_id := str(location_id_value)
		var location_data: Dictionary = runtime.get_location_data(location_id)
		warnings.append_array(synchronize_graph_from_location_data(graph, location_data))
	return warnings


func synchronize_graph_from_location_data(graph: Variant, location_data: Dictionary) -> Array:
	var warnings: Array = []
	if graph == null or location_data.is_empty():
		return warnings
	var parent_location_id := str(location_data.get("id", ""))
	if parent_location_id.is_empty():
		return warnings

	var building_by_id: Dictionary = {}
	var building_by_interior_id: Dictionary = {}
	var interior_manifest_by_id: Dictionary = {}
	for building_value in (location_data.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var building_id := str(building.get("id", ""))
		var interior_id := str(building.get("interior_location_id", ""))
		if not building_id.is_empty():
			building_by_id[building_id] = building.duplicate(true)
		if not interior_id.is_empty():
			building_by_interior_id[interior_id] = building.duplicate(true)

	for interior_value in (location_data.get("interiors", []) as Array):
		var interior_manifest: Dictionary = interior_value as Dictionary
		var interior_id := str(interior_manifest.get("location_id", ""))
		if interior_id.is_empty():
			warnings.append("interior manifest missing location_id in %s" % parent_location_id)
			continue
		interior_manifest_by_id[interior_id] = interior_manifest.duplicate(true)
		var building := _building_for_interior(interior_manifest, building_by_id, building_by_interior_id)
		var location_errors: Array = graph.upsert_location_spec(_interior_location_spec(parent_location_id, interior_manifest, building))
		warnings.append_array(location_errors)
		if not location_errors.is_empty():
			continue

		var entry_spawn_id := _interior_entry_spawn_id(interior_manifest, building)
		var entry_entrance_id := _interior_entry_entrance_id(interior_manifest, building)
		if entry_spawn_id.is_empty() or entry_entrance_id.is_empty():
			warnings.append("interior manifest missing entry spawn or entrance: %s" % interior_id)
			continue
		warnings.append_array(graph.upsert_spawn_spec({
			"location_id": interior_id,
			"spawn_id": entry_spawn_id,
			"entrance_id": entry_entrance_id,
			"facing": _interior_entry_facing(interior_manifest, building),
			"tags": ["inside_door", "interior_entry", "generated_manifest"],
		}))
		var return_entrance_id := _return_entrance_id(interior_manifest, building)
		if not return_entrance_id.is_empty():
			_ensure_exterior_spawn_for_entrance(graph, parent_location_id, building, return_entrance_id, _return_spawn_id(interior_manifest, building))

	for transition_value in (location_data.get("transitions", []) as Array):
		var transition: Dictionary = transition_value as Dictionary
		warnings.append_array(_upsert_manifest_transition_edge(graph, parent_location_id, transition, building_by_id, building_by_interior_id, interior_manifest_by_id))
	return warnings


func _wild_source_data(graph: Variant, spec: Dictionary) -> Dictionary:
	var data_path := str(spec.get("data_path", ""))
	var source_data: Dictionary = {}
	if not data_path.is_empty():
		source_data = DefinitionLoader.load_location(data_path)
	if source_data.is_empty():
		source_data = {
			"id": str(spec.get("location_id", "")),
			"display_name": str(spec.get("display_name", spec.get("location_id", ""))),
			"tile_size": int(spec.get("tile_size", 32)),
			"generator": {
				"type": "wild_terrain",
			},
		}
	var generator_data: Dictionary = (source_data.get("generator", {}) as Dictionary).duplicate(true)
	generator_data["type"] = "wild_terrain"
	generator_data["seed"] = _seed_for_spec(graph, spec)
	if spec.has("generator_profile_id"):
		generator_data["terrain_profile_id"] = str(spec.get("generator_profile_id", "plain"))
	if spec.has("size"):
		generator_data["size"] = (spec.get("size", {}) as Dictionary).duplicate(true)
	var exit_hints := _wild_exit_hints_from_graph(graph, str(spec.get("location_id", "")))
	if not exit_hints.is_empty():
		generator_data["optional_exit_hints"] = exit_hints
	source_data["generator"] = generator_data
	source_data["id"] = str(spec.get("location_id", source_data.get("id", "")))
	source_data["display_name"] = str(spec.get("display_name", source_data.get("display_name", source_data.get("id", ""))))
	return source_data


func _wild_exit_hints_from_graph(graph: Variant, location_id: String) -> Array[Dictionary]:
	var hints: Array[Dictionary] = []
	if graph == null or location_id.is_empty():
		return hints
	for edge_value in graph.get_edges_from(location_id):
		var edge: Dictionary = edge_value as Dictionary
		var metadata: Dictionary = edge.get("metadata", {}) as Dictionary
		var hint := {
			"id": str(edge.get("exit_id", "")),
			"world_exit_id": str(edge.get("exit_id", "")),
			"side": str(metadata.get("side", metadata.get("from_side", ""))),
			"facing": str(metadata.get("facing", "")),
			"target_scene_path": "__world__",
			"target_entrance_id": str(edge.get("target_spawn_id", "")),
		}
		var entry_entrance_id := _wild_entry_entrance_for_paired_edge(graph, location_id, edge)
		if not entry_entrance_id.is_empty():
			hint["entry_entrance_id"] = entry_entrance_id
		hints.append(hint)
	return hints


func _wild_entry_entrance_for_paired_edge(graph: Variant, location_id: String, edge: Dictionary) -> String:
	var paired_exit_id := str(edge.get("paired_exit_id", ""))
	if paired_exit_id.is_empty():
		return ""
	var paired_edge: Dictionary = graph.get_exit_spec("", paired_exit_id)
	if paired_edge.is_empty():
		return ""
	if str(paired_edge.get("target_location_id", "")) != location_id:
		return ""
	var target_spawn_id := str(paired_edge.get("target_spawn_id", ""))
	var spawn_spec: Dictionary = graph.get_spawn_spec(location_id, target_spawn_id)
	return str(spawn_spec.get("entrance_id", ""))


func _wild_generation_context(spec: Dictionary) -> Dictionary:
	var context: Dictionary = {}
	if spec.has("seed"):
		context["seed"] = int(spec.get("seed", 0))
	if spec.has("generator_profile_id"):
		context["terrain_profile_id"] = str(spec.get("generator_profile_id", "plain"))
	if spec.has("size"):
		context["size"] = (spec.get("size", {}) as Dictionary).duplicate(true)
	return context


func _materialize_building_interior(spec: Dictionary) -> Dictionary:
	var data_path := str(spec.get("data_path", DEFAULT_INTERIOR_DATA_PATH))
	if data_path.is_empty():
		data_path = DEFAULT_INTERIOR_DATA_PATH
	var source_data: Dictionary = DefinitionLoader.load_location(data_path)
	if source_data.is_empty():
		return {}
	var context := _building_interior_context(spec)
	return DefinitionLoader.materialize_location(source_data, data_path, context)


func _building_interior_context(spec: Dictionary) -> Dictionary:
	var context: Dictionary = (spec.get("generation_context", {}) as Dictionary).duplicate(true)
	var metadata: Dictionary = spec.get("metadata", {}) as Dictionary
	if context.is_empty() and metadata.has("generation_context"):
		context = (metadata.get("generation_context", {}) as Dictionary).duplicate(true)
	var location_id := str(spec.get("location_id", ""))
	context["location_id"] = str(context.get("location_id", location_id))
	context["exterior_location_id"] = str(context.get("exterior_location_id", spec.get("parent_location_id", "")))
	context["display_name"] = str(context.get("display_name", spec.get("display_name", "Building")))
	context["archetype_id"] = str(context.get("archetype_id", spec.get("generator_profile_id", "residential")))
	context["world_leave_exit_id"] = str(context.get("world_leave_exit_id", "%s.leave" % location_id))
	var building_instance: Dictionary = context.get("building_instance", {}) as Dictionary
	if building_instance.is_empty():
		building_instance = {
			"id": str(spec.get("parent_object_id", location_id)),
			"display_name": str(spec.get("display_name", "Building")),
			"archetype_id": str(context.get("archetype_id", "residential")),
			"interior_location_id": location_id,
			"exterior_location_id": str(spec.get("parent_location_id", "")),
			"return_entrance_id": str(metadata.get("return_entrance_id", "")),
		}
		context["building_instance"] = building_instance
	return context


func _building_for_interior(interior_manifest: Dictionary, building_by_id: Dictionary, building_by_interior_id: Dictionary) -> Dictionary:
	var interior_id := str(interior_manifest.get("location_id", ""))
	if building_by_interior_id.has(interior_id):
		return (building_by_interior_id.get(interior_id, {}) as Dictionary).duplicate(true)
	var building_id := str(interior_manifest.get("building_instance_id", ""))
	if building_by_id.has(building_id):
		return (building_by_id.get(building_id, {}) as Dictionary).duplicate(true)
	var context: Dictionary = interior_manifest.get("generation_context", {}) as Dictionary
	return (context.get("building_instance", {}) as Dictionary).duplicate(true)


func _interior_location_spec(parent_location_id: String, interior_manifest: Dictionary, building: Dictionary) -> Dictionary:
	var interior_id := str(interior_manifest.get("location_id", ""))
	var context: Dictionary = (interior_manifest.get("generation_context", {}) as Dictionary).duplicate(true)
	if not building.is_empty():
		context["building_instance"] = building.duplicate(true)
	context["location_id"] = str(context.get("location_id", interior_id))
	context["exterior_location_id"] = str(context.get("exterior_location_id", parent_location_id))
	context["archetype_id"] = str(context.get("archetype_id", building.get("archetype_id", "residential")))
	context["display_name"] = str(context.get("display_name", building.get("display_name", interior_id)))
	context["world_leave_exit_id"] = str(context.get("world_leave_exit_id", building.get("world_leave_exit_id", "%s.leave" % interior_id)))
	context["entry_entrance_id"] = str(context.get("entry_entrance_id", _interior_entry_entrance_id(interior_manifest, building)))
	context["entry_spawn_id"] = str(context.get("entry_spawn_id", _interior_entry_spawn_id(interior_manifest, building)))
	context["entry_facing"] = str(context.get("entry_facing", _interior_entry_facing(interior_manifest, building)))
	context["exit_anchor_id"] = str(context.get("exit_anchor_id", _interior_exit_anchor_id(interior_manifest, building)))
	context["return_entrance_id"] = str(context.get("return_entrance_id", _return_entrance_id(interior_manifest, building)))
	context["return_spawn_id"] = str(context.get("return_spawn_id", _return_spawn_id(interior_manifest, building)))

	return {
		"location_id": interior_id,
		"display_name": "%s Interior" % str(context.get("display_name", interior_id)),
		"location_kind": "interior",
		"source_type": "generated",
		"scene_path": str(interior_manifest.get("source_scene_path", DEFAULT_INTERIOR_SCENE_PATH)),
		"data_path": DEFAULT_INTERIOR_DATA_PATH,
		"generator_id": "building_interior",
		"generator_profile_id": str(context.get("archetype_id", "residential")),
		"parent_location_id": parent_location_id,
		"parent_object_id": "%s.door" % str(building.get("id", interior_id)),
		"metadata": {
			"source": "generated_location_manifest",
			"building_instance_id": str(building.get("id", "")),
			"entry_entrance_id": str(context.get("entry_entrance_id", "")),
			"entry_spawn_id": str(context.get("entry_spawn_id", "")),
			"exit_anchor_id": str(context.get("exit_anchor_id", "")),
			"return_entrance_id": str(context.get("return_entrance_id", "")),
			"return_spawn_id": str(context.get("return_spawn_id", "")),
		},
		"generation_context": context,
	}


func _ensure_exterior_spawn_for_entrance(
	graph: Variant,
	location_id: String,
	building: Dictionary,
	entrance_id: String,
	desired_spawn_id: String = ""
) -> String:
	var existing_spawn_id := str(graph.find_spawn_id_for_entrance(location_id, entrance_id))
	if not existing_spawn_id.is_empty():
		return existing_spawn_id
	var building_id := str(building.get("id", "building"))
	var spawn_id := desired_spawn_id
	if spawn_id.is_empty():
		spawn_id = "%s.outside" % building_id
	graph.upsert_spawn_spec({
		"location_id": location_id,
		"spawn_id": spawn_id,
		"entrance_id": entrance_id,
		"facing": str(building.get("door_facing", "down")),
		"tags": ["from_interior", "generated_manifest", building_id],
	})
	return spawn_id


func _upsert_manifest_transition_edge(
	graph: Variant,
	parent_location_id: String,
	transition: Dictionary,
	building_by_id: Dictionary,
	building_by_interior_id: Dictionary,
	interior_manifest_by_id: Dictionary
) -> Array:
	var from_location_id := str(transition.get("from_location_id", ""))
	var to_location_id := str(transition.get("to_location_id", ""))
	var building_id := str(transition.get("building_instance_id", ""))
	var building: Dictionary = {}
	if building_by_id.has(building_id):
		building = (building_by_id.get(building_id, {}) as Dictionary).duplicate(true)
	elif building_by_interior_id.has(from_location_id):
		building = (building_by_interior_id.get(from_location_id, {}) as Dictionary).duplicate(true)
	elif building_by_interior_id.has(to_location_id):
		building = (building_by_interior_id.get(to_location_id, {}) as Dictionary).duplicate(true)
	var interior_manifest: Dictionary = {}
	if interior_manifest_by_id.has(to_location_id):
		interior_manifest = (interior_manifest_by_id.get(to_location_id, {}) as Dictionary).duplicate(true)
	elif interior_manifest_by_id.has(from_location_id):
		interior_manifest = (interior_manifest_by_id.get(from_location_id, {}) as Dictionary).duplicate(true)

	if from_location_id == parent_location_id and to_location_id != parent_location_id:
		var enter_exit_id := str(building.get("world_enter_exit_id", "%s.enter" % to_location_id))
		var target_spawn_id := str(transition.get("target_spawn_id", _interior_entry_spawn_id(interior_manifest, building)))
		if target_spawn_id.is_empty():
			target_spawn_id = graph.find_spawn_id_for_entrance(to_location_id, str(transition.get("to_anchor_id", "")))
		return graph.upsert_exit_spec({
			"exit_id": enter_exit_id,
			"from_location_id": from_location_id,
			"from_anchor_id": str(transition.get("from_anchor_id", "")),
			"target_location_id": to_location_id,
			"target_spawn_id": target_spawn_id,
			"transition_type": "door",
			"enabled": true,
			"metadata": {
				"source": "generated_location_manifest",
				"building_instance_id": building_id,
			},
		})

	if from_location_id != parent_location_id and to_location_id == parent_location_id:
		var return_entrance_id := str(transition.get("to_anchor_id", _return_entrance_id(interior_manifest, building)))
		var target_spawn_id := str(transition.get("target_spawn_id", _return_spawn_id(interior_manifest, building)))
		target_spawn_id = _ensure_exterior_spawn_for_entrance(graph, parent_location_id, building, return_entrance_id, target_spawn_id)
		var leave_exit_id := str(building.get("world_leave_exit_id", "%s.leave" % from_location_id))
		return graph.upsert_exit_spec({
			"exit_id": leave_exit_id,
			"from_location_id": from_location_id,
			"from_anchor_id": str(transition.get("from_anchor_id", _interior_exit_anchor_id(interior_manifest, building))),
			"target_location_id": to_location_id,
			"target_spawn_id": target_spawn_id,
			"transition_type": "door",
			"enabled": true,
			"metadata": {
				"source": "generated_location_manifest",
				"building_instance_id": building_id,
			},
		})

	return []


func _interior_entry_spawn_id(interior_manifest: Dictionary, building: Dictionary) -> String:
	var manifest_value := str(interior_manifest.get("entry_spawn_id", ""))
	if not manifest_value.is_empty():
		return manifest_value
	var context: Dictionary = interior_manifest.get("generation_context", {}) as Dictionary
	var context_value := str(context.get("entry_spawn_id", ""))
	if not context_value.is_empty():
		return context_value
	return str(building.get("interior_entry_spawn_id", ""))


func _interior_entry_entrance_id(interior_manifest: Dictionary, building: Dictionary) -> String:
	var manifest_value := str(interior_manifest.get("entry_entrance_id", ""))
	if not manifest_value.is_empty():
		return manifest_value
	var context: Dictionary = interior_manifest.get("generation_context", {}) as Dictionary
	var context_value := str(context.get("entry_entrance_id", ""))
	if not context_value.is_empty():
		return context_value
	return str(building.get("interior_entry_entrance_id", ""))


func _interior_entry_facing(interior_manifest: Dictionary, building: Dictionary) -> String:
	var manifest_value := str(interior_manifest.get("entry_facing", ""))
	if not manifest_value.is_empty():
		return manifest_value
	var context: Dictionary = interior_manifest.get("generation_context", {}) as Dictionary
	var context_value := str(context.get("entry_facing", ""))
	if not context_value.is_empty():
		return context_value
	return str(building.get("interior_entry_facing", "up"))


func _interior_exit_anchor_id(interior_manifest: Dictionary, building: Dictionary) -> String:
	var manifest_value := str(interior_manifest.get("exit_anchor_id", ""))
	if not manifest_value.is_empty():
		return manifest_value
	var context: Dictionary = interior_manifest.get("generation_context", {}) as Dictionary
	var context_value := str(context.get("exit_anchor_id", ""))
	if not context_value.is_empty():
		return context_value
	return str(building.get("interior_exit_anchor_id", ""))


func _return_entrance_id(interior_manifest: Dictionary, building: Dictionary) -> String:
	var manifest_value := str(interior_manifest.get("return_entrance_id", ""))
	if not manifest_value.is_empty():
		return manifest_value
	var context: Dictionary = interior_manifest.get("generation_context", {}) as Dictionary
	var context_value := str(context.get("return_entrance_id", ""))
	if not context_value.is_empty():
		return context_value
	return str(building.get("return_entrance_id", ""))


func _return_spawn_id(interior_manifest: Dictionary, building: Dictionary) -> String:
	var manifest_value := str(interior_manifest.get("return_spawn_id", ""))
	if not manifest_value.is_empty():
		return manifest_value
	var context: Dictionary = interior_manifest.get("generation_context", {}) as Dictionary
	var context_value := str(context.get("return_spawn_id", ""))
	if not context_value.is_empty():
		return context_value
	return str(building.get("exterior_return_spawn_id", ""))


func _scene_path_for_spec(spec: Dictionary) -> String:
	var scene_path := str(spec.get("scene_path", ""))
	if not scene_path.is_empty():
		return scene_path
	if str(spec.get("location_kind", "")) == "generated_wild":
		return DEFAULT_WILD_SCENE_PATH
	if str(spec.get("location_kind", "")) == "interior":
		return DEFAULT_INTERIOR_SCENE_PATH
	return ""


func _seed_for_spec(graph: Variant, spec: Dictionary) -> int:
	if spec.has("seed"):
		return int(spec.get("seed", 0))
	var location_id := str(spec.get("location_id", ""))
	return int(graph.world_seed + abs(hash(location_id)) % 100000)


func _failure(reason: String) -> Dictionary:
	return {
		"success": false,
		"error": reason,
		"warnings": [reason],
	}
