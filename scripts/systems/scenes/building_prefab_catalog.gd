class_name BuildingPrefabCatalog
extends RefCounted


static func load_prefabs(resource_path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if resource_path.is_empty():
		return result

	var file: FileAccess = FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		push_error("BuildingPrefabCatalog could not open prefab catalog: %s" % resource_path)
		return result

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("BuildingPrefabCatalog expected a JSON object: %s" % resource_path)
		return result

	var catalog: Dictionary = parsed as Dictionary
	for prefab_value in (catalog.get("prefabs", []) as Array):
		var prefab: Dictionary = prefab_value as Dictionary
		var normalized: Dictionary = _normalize_prefab(prefab)
		if normalized.is_empty():
			continue
		result.append(normalized)
	return result


static func _normalize_prefab(prefab: Dictionary) -> Dictionary:
	var prefab_id := str(prefab.get("id", ""))
	if prefab_id.is_empty():
		push_error("BuildingPrefabCatalog skipped prefab without id")
		return {}

	var normalized: Dictionary = prefab.duplicate(true)
	normalized["id"] = prefab_id
	normalized["door_side"] = str(normalized.get("door_side", "south"))
	normalized["door_offset"] = int(normalized.get("door_offset", 1))
	normalized["required_front_clearance"] = maxi(1, int(normalized.get("required_front_clearance", 1)))

	if not normalized.has("footprint_size"):
		normalized["footprint_size"] = { "w": 3, "h": 3 }
	if not normalized.has("allowed_yard_policies"):
		normalized["allowed_yard_policies"] = ["clear_frontage"]
	if not normalized.has("archetype_tags"):
		normalized["archetype_tags"] = []
	if not normalized.has("exterior_slots"):
		normalized["exterior_slots"] = []

	var visual: Dictionary = normalized.get("visual", {}) as Dictionary
	if visual.is_empty():
		visual = {
			"render_kind": "placeholder_facade",
			"asset_id": "",
			"placeholder_style": "generic_basic",
			"wall_palette": "generic_plaster",
			"roof_palette": "brown",
		}
	else:
		visual["render_kind"] = str(visual.get("render_kind", "placeholder_facade"))
		visual["asset_id"] = str(visual.get("asset_id", ""))
		visual["placeholder_style"] = str(visual.get("placeholder_style", "generic_basic"))
		visual["wall_palette"] = str(visual.get("wall_palette", "generic_plaster"))
		visual["roof_palette"] = str(visual.get("roof_palette", "brown"))
	normalized["visual"] = visual

	var slot_contract: Dictionary = normalized.get("exterior_slot_contract", {}) as Dictionary
	slot_contract["schema_version"] = int(slot_contract.get("schema_version", 1))
	slot_contract["coordinate_space"] = str(slot_contract.get("coordinate_space", "prefab_local_grid"))
	slot_contract["content_source"] = str(slot_contract.get("content_source", "prefab_declared_only"))
	slot_contract["requires_clearance_validation"] = bool(slot_contract.get("requires_clearance_validation", true))
	normalized["exterior_slot_contract"] = slot_contract

	return normalized
