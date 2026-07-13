class_name RegionSemanticVocabulary
extends RefCounted

const ALLOWED_NEEDS := [
	"settlement.core",
	"settlement.support",
	"wilderness.core",
	"wilderness.inner",
	"production.food",
	"production.resource",
	"public.gathering",
	"public.trade",
	"travel.access",
	"travel.road",
	"travel.crossing",
	"safety.watch",
	"danger.local",
	"landmark.memorable",
	"resource.water",
	"resource.forest",
	"shelter.local",
	"ritual.place",
	"boundary.frontier",
]

const ALLOWED_NEED_DOMAINS := [
	"boundary",
	"danger",
	"landmark",
	"production",
	"public",
	"resource",
	"ritual",
	"safety",
	"settlement",
	"shelter",
	"travel",
	"wilderness",
]

const ALLOWED_ROLE_PROPERTIES := [
	"access",
	"boundary",
	"core",
	"dangerous",
	"forest",
	"hidden",
	"inner",
	"production",
	"public",
	"ritual",
	"road",
	"shelter",
	"support",
	"trade",
	"water",
]

const ALLOWED_ROLE_AFFINITIES := [
	"danger.high",
	"forest.edge",
	"hidden.available",
	"political.frontier",
	"political.kingdom",
	"resource.abundant",
	"settlement.near",
	"terrain.forest",
	"terrain.plain",
	"travel.road_access",
	"water.river",
	"wilderness.deep",
]

const ALLOWED_ROLE_CATEGORIES := [
	"landmark",
	"resource",
	"settlement",
	"travel_point",
	"wilderness",
]

const ALLOWED_TRAITS := [
	"settlement",
	"wilderness",
	"town",
	"forest",
	"plain",
	"river",
	"frontier",
	"kingdom",
	"road_access",
	"resource_rich",
	"dangerous",
	"public",
	"production",
	"landmark",
]

const ALLOWED_FACTS := [
	"has_road",
	"has_river",
	"near_river",
	"near_forest",
	"has_forest",
	"has_farmland",
	"belongs_to_kingdom",
	"border_region",
	"has_hidden_places",
	"resource_site",
]

const ALLOWED_COARSE_CONTEXT := {
	"terrain_context": ["plain", "forest", "river_near"],
	"political_context": ["kingdom", "wilderness", "border", "frontier"],
	"scale": ["small", "medium", "large"],
}


static func validate_need_array(value: Variant, key: String, require_array: bool = true) -> Array[String]:
	var errors: Array[String] = []
	if value == null:
		if require_array:
			errors.append("RegionInput.%s is missing" % key)
		return errors
	if not (value is Array):
		errors.append("RegionInput.%s must be an array" % key)
		return errors
	var seen: Dictionary = {}
	var values: Array = value as Array
	for index in range(values.size()):
		var need_id := str(values[index])
		if need_id.is_empty():
			errors.append("RegionInput.%s[%d] is empty" % [key, index])
			continue
		if not is_need_id(need_id):
			errors.append("RegionInput.%s[%d] is not supported by the controlled vocabulary: %s" % [key, index, need_id])
		if seen.has(need_id):
			errors.append("RegionInput.%s contains duplicate need_id: %s" % [key, need_id])
		seen[need_id] = true
	return errors


static func validate_trait_array(value: Variant, key: String) -> Array[String]:
	return _validate_limited_token_array(value, key, ALLOWED_TRAITS)


static func validate_fact_array(value: Variant, key: String) -> Array[String]:
	return _validate_limited_token_array(value, key, ALLOWED_FACTS)


static func validate_coarse_context(value: Variant, key: String) -> Array[String]:
	var errors: Array[String] = []
	if not (value is Dictionary):
		errors.append("RegionInput.%s must be an object" % key)
		return errors
	var context: Dictionary = value as Dictionary
	if context.is_empty():
		errors.append("RegionInput.%s is missing" % key)
		return errors
	for required_key in ALLOWED_COARSE_CONTEXT.keys():
		if not context.has(required_key) or _context_value_is_empty(context.get(required_key)):
			errors.append("RegionInput.%s.%s is missing" % [key, str(required_key)])
			continue
		var allowed_values: Array = ALLOWED_COARSE_CONTEXT.get(required_key, []) as Array
		for context_value in context_values(context.get(required_key)):
			if not allowed_values.has(context_value):
				errors.append("RegionInput.%s.%s is not supported by the controlled vocabulary: %s" % [key, str(required_key), context_value])
	for context_key in context.keys():
		if not ALLOWED_COARSE_CONTEXT.has(context_key):
			errors.append("RegionInput.%s contains unsupported key: %s" % [key, str(context_key)])
	return errors


static func is_need_id(value: String) -> bool:
	return ALLOWED_NEEDS.has(value)


static func need_domain(value: String) -> String:
	var separator := value.find(".")
	if separator <= 0:
		return ""
	return value.substr(0, separator)


static func is_need_domain(value: String) -> bool:
	return ALLOWED_NEED_DOMAINS.has(value)


static func is_role_property(value: String) -> bool:
	return ALLOWED_ROLE_PROPERTIES.has(value)


static func is_role_affinity(value: String) -> bool:
	return ALLOWED_ROLE_AFFINITIES.has(value)


static func is_role_category(value: String) -> bool:
	return ALLOWED_ROLE_CATEGORIES.has(value)


static func is_trait(value: String) -> bool:
	return ALLOWED_TRAITS.has(value)


static func is_fact(value: String) -> bool:
	return ALLOWED_FACTS.has(value)


static func is_coarse_context_key(value: String) -> bool:
	return ALLOWED_COARSE_CONTEXT.has(value)


static func is_coarse_context_value(key: String, value: String) -> bool:
	if not ALLOWED_COARSE_CONTEXT.has(key):
		return false
	var allowed_values: Array = ALLOWED_COARSE_CONTEXT.get(key, []) as Array
	return allowed_values.has(value)


static func need_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text := str(item)
		if not text.is_empty():
			result.append(text)
	return result


static func unique_strings(values: Array) -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if text.is_empty() or seen.has(text):
			continue
		seen[text] = true
		result.append(text)
	return result


static func context_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in (value as Array):
			var text := str(item)
			if not text.is_empty():
				result.append(text)
	else:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


static func _validate_limited_token_array(value: Variant, key: String, allowed_values: Array) -> Array[String]:
	var errors: Array[String] = []
	if not (value is Array):
		errors.append("RegionInput.%s must be an array" % key)
		return errors
	var seen: Dictionary = {}
	var values: Array = value as Array
	for index in range(values.size()):
		var token := str(values[index])
		if token.is_empty():
			errors.append("RegionInput.%s[%d] is empty" % [key, index])
			continue
		if not allowed_values.has(token):
			errors.append("RegionInput.%s[%d] is not supported by the controlled vocabulary: %s" % [key, index, token])
		if seen.has(token):
			errors.append("RegionInput.%s contains duplicate token: %s" % [key, token])
		seen[token] = true
	return errors


static func _context_value_is_empty(value: Variant) -> bool:
	if value is String:
		return str(value).is_empty()
	if value is Array:
		return (value as Array).is_empty()
	return value == null
