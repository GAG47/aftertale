class_name CharacterAppearanceResolver
extends RefCounted

const CATALOG_PATH := "res://data/appearance/common_appearance_parts.json"

static var _catalog: Dictionary = {}
static var _parts_by_layer: Dictionary = {}


static func resolve(character_id: String, character_kind: String, profile: Dictionary, base_appearance: Dictionary) -> Dictionary:
	var appearance: Dictionary = _dictionary(base_appearance).duplicate(true)
	if str(appearance.get("display_mode", "modular")) == "badge":
		return appearance
	if not _should_auto_resolve(character_kind, profile, appearance):
		return appearance

	var layers: Dictionary = _dictionary(appearance.get("layers", {})).duplicate(true)
	appearance["layers"] = layers

	_apply_layer_if_missing(layers, appearance, "body", _select_part("body", character_id, profile, appearance))
	_apply_layer_if_missing(layers, appearance, "outfit", _select_part("outfit", character_id, profile, appearance))
	_apply_layer_if_missing(layers, appearance, "head", _select_part("head", character_id, profile, appearance))
	_apply_accessory_if_needed(layers, appearance, character_id, profile)
	_apply_hair_if_missing(layers, appearance, character_id, profile)

	return appearance


static func _should_auto_resolve(character_kind: String, profile: Dictionary, appearance: Dictionary) -> bool:
	if bool(appearance.get("auto_resolve", false)):
		return true
	if character_kind == "player" or character_kind == "enemy":
		return false
	return str(profile.get("importance", "common")) == "common"


static func _apply_layer_if_missing(layers: Dictionary, appearance: Dictionary, layer_id: String, part: Dictionary) -> void:
	if part.is_empty() or layers.has(layer_id):
		return

	var layer_data: Dictionary = {
		"source": str(part.get("source", "")),
	}
	layers[layer_id] = layer_data
	appearance["%s_id" % layer_id] = str(part.get("id", ""))


static func _apply_hair_if_missing(layers: Dictionary, appearance: Dictionary, character_id: String, profile: Dictionary) -> void:
	if layers.has("hair"):
		return

	var part: Dictionary = _select_part("hair", character_id, profile, appearance)
	if part.is_empty():
		return

	var layer_data: Dictionary = {
		"source": str(part.get("source", "")),
	}
	if str(part.get("dye_mode", "fixed")) == "tint":
		layer_data["modulate"] = _hair_color(character_id, appearance)

	layers["hair"] = layer_data
	appearance["hair_id"] = str(part.get("id", ""))


static func _apply_accessory_if_needed(layers: Dictionary, appearance: Dictionary, character_id: String, profile: Dictionary) -> void:
	if layers.has("accessory"):
		return

	var role: String = _role(profile)
	if role != "guard" and _stable_index(character_id, "accessory_chance", 100) >= 18:
		return

	var part: Dictionary = _select_part("accessory", character_id, profile, appearance)
	if part.is_empty():
		return

	layers["accessory"] = {
		"source": str(part.get("source", "")),
	}
	appearance["accessory_ids"] = [str(part.get("id", ""))]


static func _select_part(layer_id: String, character_id: String, profile: Dictionary, appearance: Dictionary) -> Dictionary:
	var parts: Array = _parts_for_layer(layer_id)
	if parts.is_empty():
		return {}

	var role: String = _role(profile)
	var candidates: Array = []
	for part_value in parts:
		var part: Dictionary = _dictionary(part_value)
		if not _part_matches_role(part, role):
			continue
		if not _part_matches_layer_policy(part, role, layer_id):
			continue
		candidates.append(part)

	if candidates.is_empty():
		for part_value in parts:
			var fallback_part: Dictionary = _dictionary(part_value)
			if _part_matches_layer_policy(fallback_part, role, layer_id):
				candidates.append(fallback_part)

	if candidates.is_empty():
		candidates = parts

	var explicit_id: String = str(appearance.get("%s_id" % layer_id, ""))
	if layer_id == "hair":
		explicit_id = str(appearance.get("hair_id", explicit_id))
	if not explicit_id.is_empty():
		for candidate_value in candidates:
			var candidate: Dictionary = _dictionary(candidate_value)
			if str(candidate.get("id", "")) == explicit_id:
				return candidate

	var index: int = _stable_index(character_id, "%s:%s" % [layer_id, role], candidates.size())
	return _dictionary(candidates[index])


static func _part_matches_layer_policy(part: Dictionary, role: String, layer_id: String) -> bool:
	var category: String = str(part.get("category", ""))
	if layer_id == "outfit":
		if role == "guard":
			return category == "armor"
		return category != "armor"
	if layer_id == "accessory":
		if role == "guard":
			return category == "helmet"
		return category == "hat"
	return true


static func _part_matches_role(part: Dictionary, role: String) -> bool:
	var roles: Array = _array(part.get("roles", []))
	if roles.is_empty():
		return true
	if roles.has(role) or roles.has("common"):
		return true
	if role == "shopkeeper" and roles.has("merchant"):
		return true
	if role == "farmer" and (roles.has("worker") or roles.has("villager")):
		return true
	if role == "worker" and roles.has("villager"):
		return true
	if role == "traveler" and roles.has("villager"):
		return true
	return false


static func _parts_for_layer(layer_id: String) -> Array:
	_ensure_catalog_loaded()
	return (_parts_by_layer.get(layer_id, []) as Array).duplicate()


static func _ensure_catalog_loaded() -> void:
	if not _catalog.is_empty():
		return

	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_warning("Appearance catalog could not be opened: %s" % CATALOG_PATH)
		_catalog = {}
		_parts_by_layer = {}
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("Appearance catalog is not a dictionary: %s" % CATALOG_PATH)
		_catalog = {}
		_parts_by_layer = {}
		return

	_catalog = (parsed as Dictionary).duplicate(true)
	_parts_by_layer = {}
	var parts: Array = _array(_catalog.get("parts", []))
	for part_value in parts:
		var part: Dictionary = _dictionary(part_value)
		var layer_id: String = str(part.get("layer", ""))
		if layer_id.is_empty():
			continue
		if not _parts_by_layer.has(layer_id):
			_parts_by_layer[layer_id] = []
		(_parts_by_layer[layer_id] as Array).append(part)


static func _hair_color(character_id: String, appearance: Dictionary) -> String:
	var palette: Dictionary = _dictionary(appearance.get("palette", {}))
	var explicit_color: String = str(palette.get("hair", ""))
	if not explicit_color.is_empty():
		return explicit_color

	_ensure_catalog_loaded()
	var colors: Array = _array(_catalog.get("hair_palettes", []))
	if colors.is_empty():
		return "#74502e"
	return str(colors[_stable_index(character_id, "hair_palette", colors.size())])


static func _role(profile: Dictionary) -> String:
	var role: String = str(profile.get("role", "villager")).to_lower()
	match role:
		"shopkeep", "shopkeeper":
			return "shopkeeper"
		"merchant":
			return "merchant"
		"guard", "militia", "patrol":
			return "guard"
		"farmer":
			return "farmer"
		"worker":
			return "worker"
		"scholar", "researcher":
			return "scholar"
		"traveler", "wanderer":
			return "traveler"
	return "villager"


static func _stable_index(seed: String, salt: String, count: int) -> int:
	if count <= 0:
		return 0

	var value: int = 17
	var text := "%s:%s" % [seed, salt]
	for index in text.length():
		value = int((value * 131 + text.unicode_at(index)) % 2147483647)
	return value % count


static func _dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}


static func _array(value: Variant) -> Array:
	if value is Array:
		return value as Array
	return []
