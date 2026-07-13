class_name CanonicalDataSerializer
extends RefCounted

const HASH_PREFIX := "sha256_"


static func normalize_location_node_result(result: Dictionary) -> Dictionary:
	var normalized := result.duplicate(true)
	if _is_integer_like(normalized.get("schema_version")):
		normalized["schema_version"] = int(normalized.get("schema_version"))
	if _is_integer_like(normalized.get("seed")):
		normalized["seed"] = int(normalized.get("seed"))
	var nodes: Array = normalized.get("location_nodes", []) as Array
	for index in range(nodes.size()):
		if not (nodes[index] is Dictionary):
			continue
		var node: Dictionary = (nodes[index] as Dictionary).duplicate(true)
		if node.get("node_tags", null) is Array:
			node["node_tags"] = _normalize_string_set(node.get("node_tags", []) as Array)
		for affordance_key in ["gameplay_affordances", "narrative_affordances"]:
			if node.get(affordance_key, null) is Array:
				node[affordance_key] = _normalize_string_set(node.get(affordance_key, []) as Array)
		nodes[index] = node
	normalized["location_nodes"] = _sort_dictionary_array(nodes, ["location_id"])
	if normalized.get("role_node_bindings", null) is Array:
		normalized["role_node_bindings"] = _sort_dictionary_array(
			normalized.get("role_node_bindings", []) as Array,
			["source_role_id", "location_id"]
		)
	return normalized


static func normalize_location_node_result_set(results: Array) -> Array:
	var normalized: Array = []
	for value in results:
		if value is Dictionary:
			normalized.append(normalize_location_node_result(value as Dictionary))
		else:
			normalized.append(value)
	return _sort_dictionary_array(normalized, ["region_id"])


static func normalize_edge_contract_result(result: Dictionary) -> Dictionary:
	var normalized := result.duplicate(true)
	if _is_integer_like(normalized.get("schema_version")):
		normalized["schema_version"] = int(normalized.get("schema_version"))
	if normalized.get("source_location_node_hashes", null) is Array:
		normalized["source_location_node_hashes"] = _sort_dictionary_array(
			normalized.get("source_location_node_hashes", []) as Array,
			["region_id"]
		)
	var edges: Array = normalized.get("edge_contracts", []) as Array
	for index in range(edges.size()):
		if not (edges[index] is Dictionary):
			continue
		var edge: Dictionary = (edges[index] as Dictionary).duplicate(true)
		if edge.get("traversal_tags", null) is Array:
			edge["traversal_tags"] = _normalize_string_set(edge.get("traversal_tags", []) as Array)
		if edge.get("validation_flags", null) is Array:
			edge["validation_flags"] = _normalize_string_set(edge.get("validation_flags", []) as Array)
		edges[index] = edge
	normalized["edge_contracts"] = _sort_dictionary_array(edges, ["edge_id"])
	return normalized


static func normalize_snapshot(snapshot: Dictionary) -> Dictionary:
	var normalized := snapshot.duplicate(true)
	if _is_integer_like(normalized.get("schema_version")):
		normalized["schema_version"] = int(normalized.get("schema_version"))
	var nodes: Array = normalized.get("location_nodes", []) as Array
	for index in range(nodes.size()):
		if not (nodes[index] is Dictionary):
			continue
		var node: Dictionary = (nodes[index] as Dictionary).duplicate(true)
		if node.get("node_tags", null) is Array:
			node["node_tags"] = _normalize_string_set(node.get("node_tags", []) as Array)
		for affordance_key in ["gameplay_affordances", "narrative_affordances"]:
			if node.get(affordance_key, null) is Array:
				node[affordance_key] = _normalize_string_set(node.get(affordance_key, []) as Array)
		nodes[index] = node
	normalized["location_nodes"] = _sort_dictionary_array(nodes, ["location_id"])
	var edges: Array = normalized.get("edge_contracts", []) as Array
	for index in range(edges.size()):
		if not (edges[index] is Dictionary):
			continue
		var edge: Dictionary = (edges[index] as Dictionary).duplicate(true)
		if edge.get("traversal_tags", null) is Array:
			edge["traversal_tags"] = _normalize_string_set(edge.get("traversal_tags", []) as Array)
		if edge.get("validation_flags", null) is Array:
			edge["validation_flags"] = _normalize_string_set(edge.get("validation_flags", []) as Array)
		edges[index] = edge
	normalized["edge_contracts"] = _sort_dictionary_array(edges, ["edge_id"])
	if normalized.get("node_sources", null) is Array:
		normalized["node_sources"] = _sort_dictionary_array(
			normalized.get("node_sources", []) as Array,
			["location_id"]
		)
	if normalized.get("source_manifest", null) is Array:
		normalized["source_manifest"] = _sort_dictionary_array(
			normalized.get("source_manifest", []) as Array,
			["source_kind", "source_id"]
		)
	if normalized.get("rule_manifest", null) is Array:
		normalized["rule_manifest"] = _sort_dictionary_array(
			normalized.get("rule_manifest", []) as Array,
			["profile_kind", "profile_path"]
		)
	return normalized


static func location_node_result_hash(result: Dictionary) -> String:
	var payload := normalize_location_node_result(result)
	payload.erase("result_hash")
	return hash_value(payload)


static func location_node_result_set_hash(results: Array) -> String:
	return hash_value(normalize_location_node_result_set(results))


static func edge_contract_result_hash(result: Dictionary) -> String:
	var payload := normalize_edge_contract_result(result)
	payload.erase("result_hash")
	return hash_value(payload)


static func profile_content_hash(profile_data: Dictionary) -> String:
	return hash_value(profile_data.duplicate(true))


static func snapshot_content_hash(snapshot: Dictionary) -> String:
	var payload := normalize_snapshot(snapshot)
	payload.erase("content_hash")
	payload.erase("snapshot_id")
	return hash_value(payload)


static func snapshot_id(graph_id: String, content_hash: String) -> String:
	var identity_hash := hash_text("%s:%s" % [graph_id, content_hash])
	if identity_hash.is_empty():
		return ""
	return "snapshot.lgs_%s" % identity_hash.trim_prefix(HASH_PREFIX)


static func snapshot_json(snapshot: Dictionary) -> String:
	return serialize(normalize_snapshot(snapshot))


static func snapshot_collections_are_canonical(snapshot: Dictionary) -> bool:
	if not _dictionary_array_is_sorted(snapshot.get("location_nodes", []) as Array, ["location_id"]):
		return false
	if not _dictionary_array_is_sorted(snapshot.get("edge_contracts", []) as Array, ["edge_id"]):
		return false
	if not _dictionary_array_is_sorted(snapshot.get("node_sources", []) as Array, ["location_id"]):
		return false
	if not _dictionary_array_is_sorted(snapshot.get("source_manifest", []) as Array, ["source_kind", "source_id"]):
		return false
	if not _dictionary_array_is_sorted(snapshot.get("rule_manifest", []) as Array, ["profile_kind", "profile_path"]):
		return false
	for node_value in (snapshot.get("location_nodes", []) as Array):
		if not (node_value is Dictionary):
			continue
		if not _string_set_is_canonical((node_value as Dictionary).get("node_tags", []) as Array):
			return false
		for affordance_key in ["gameplay_affordances", "narrative_affordances"]:
			if not _string_set_is_canonical((node_value as Dictionary).get(affordance_key, []) as Array):
				return false
	for edge_value in (snapshot.get("edge_contracts", []) as Array):
		if not (edge_value is Dictionary):
			continue
		var edge: Dictionary = edge_value as Dictionary
		if not _string_set_is_canonical(edge.get("traversal_tags", []) as Array):
			return false
		if not _string_set_is_canonical(edge.get("validation_flags", []) as Array):
			return false
	return true


static func serialize(value: Variant) -> String:
	if not validate_value(value).is_empty():
		return ""
	return _serialize_value(value)


static func hash_value(value: Variant) -> String:
	var text := serialize(value)
	if text.is_empty():
		return ""
	return hash_text(text)


static func hash_text(text: String) -> String:
	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	var update_error := context.update(text.to_utf8_buffer())
	if update_error != OK:
		return ""
	return "%s%s" % [HASH_PREFIX, context.finish().hex_encode()]


static func validate_value(value: Variant, path: String = "$") -> Array[String]:
	var errors: Array[String] = []
	_validate_value_recursive(value, path, errors)
	return errors


static func is_sha256_hash(value: String) -> bool:
	if not value.begins_with(HASH_PREFIX):
		return false
	var hex := value.trim_prefix(HASH_PREFIX)
	if hex.length() != 64:
		return false
	for index in range(hex.length()):
		var code := hex.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_lower_hex := code >= 97 and code <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true


static func _serialize_value(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			return JSON.stringify(float(value))
		TYPE_STRING:
			return JSON.stringify(str(value))
		TYPE_ARRAY:
			var parts: Array[String] = []
			for item in (value as Array):
				parts.append(_serialize_value(item))
			return "[%s]" % ",".join(parts)
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value as Dictionary
			var keys: Array[String] = []
			for key_value in dictionary.keys():
				keys.append(str(key_value))
			keys.sort()
			var parts: Array[String] = []
			for key in keys:
				parts.append("%s:%s" % [JSON.stringify(key), _serialize_value(dictionary.get(key))])
			return "{%s}" % ",".join(parts)
	return ""


static func _validate_value_recursive(value: Variant, path: String, errors: Array[String]) -> void:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return
		TYPE_FLOAT:
			if not is_finite(float(value)):
				errors.append("Canonical data contains a non-finite number at %s" % path)
		TYPE_ARRAY:
			var values: Array = value as Array
			for index in range(values.size()):
				_validate_value_recursive(values[index], "%s[%d]" % [path, index], errors)
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value as Dictionary
			for key_value in dictionary.keys():
				if not (key_value is String):
					errors.append("Canonical data contains a non-string dictionary key at %s" % path)
					continue
				var key := str(key_value)
				_validate_value_recursive(dictionary.get(key_value), "%s.%s" % [path, key], errors)
		_:
			errors.append("Canonical data contains an unsupported value type at %s: %s" % [path, type_string(typeof(value))])


static func _normalize_string_set(values: Array) -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if seen.has(text):
			continue
		seen[text] = true
		result.append(text)
	result.sort()
	return result


static func _sort_dictionary_array(values: Array, keys: Array[String]) -> Array:
	var result := values.duplicate(true)
	for index in range(1, result.size()):
		var current: Variant = result[index]
		var current_key := _dictionary_sort_key(current, keys)
		var cursor := index - 1
		while cursor >= 0 and _dictionary_sort_key(result[cursor], keys) > current_key:
			result[cursor + 1] = result[cursor]
			cursor -= 1
		result[cursor + 1] = current
	return result


static func _dictionary_sort_key(value: Variant, keys: Array[String]) -> String:
	if not (value is Dictionary):
		return "\uffff%s" % serialize(value)
	var dictionary: Dictionary = value as Dictionary
	var parts: Array[String] = []
	for key in keys:
		parts.append(str(dictionary.get(key, "")))
	return "\u001f".join(parts)


static func _dictionary_array_is_sorted(values: Array, keys: Array[String]) -> bool:
	var previous_key := ""
	for index in range(values.size()):
		var current_key := _dictionary_sort_key(values[index], keys)
		if index > 0 and current_key < previous_key:
			return false
		previous_key = current_key
	return true


static func _string_set_is_canonical(values: Array) -> bool:
	var previous := ""
	var seen: Dictionary = {}
	for index in range(values.size()):
		if not (values[index] is String):
			return false
		var current := str(values[index])
		if seen.has(current):
			return false
		if index > 0 and current < previous:
			return false
		seen[current] = true
		previous = current
	return true


static func _is_integer_like(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and is_equal_approx(float(value), float(int(value)))
	return false
