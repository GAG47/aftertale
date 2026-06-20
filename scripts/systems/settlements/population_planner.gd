class_name PopulationPlanner
extends RefCounted

const SchedulePlannerScript := preload("res://scripts/systems/settlements/schedule_planner.gd")
const MAX_GENERATED_NPCS := 12

var _schedule_planner: RefCounted


func _init() -> void:
	_schedule_planner = SchedulePlannerScript.new()


func plan_population(settlement_id: String, policy_id: String, seed: int, exterior_location: Dictionary) -> Dictionary:
	var schedule_targets: Array = exterior_location.get("schedule_targets", []) as Array
	var building_contracts: Array = exterior_location.get("building_contracts", []) as Array
	var target_index: Dictionary = _build_target_index(schedule_targets)
	var contracts_by_use: Dictionary = _contracts_by_use(building_contracts)
	var social_target: Dictionary = _first_target_for_roles(target_index, ["dining", "tavern", "rest", "gathering", "activity", "exterior_transition"])
	var fallback_target: Dictionary = _first_target_for_roles(target_index, ["exterior_transition", "home", "bed", "work", "service", "counter"])

	var definitions: Array[Dictionary] = []
	var assignments: Array[Dictionary] = []
	var spawn_rows_by_location: Dictionary = {}
	var unresolved: Array[Dictionary] = []
	var role_counts: Dictionary = {}
	var sequence: int = 1

	for contract in _selected_contracts(contracts_by_use, "residential", 4):
		sequence = _append_npc("resident", settlement_id, policy_id, seed, sequence, contract, target_index, social_target, fallback_target, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	for contract in _selected_contracts(contracts_by_use, "commercial", 3):
		var role := "shopkeeper"
		if _target_for_contract(target_index, contract, ["tavern", "tavern_counter"]).is_empty():
			role = "merchant"
		else:
			role = "innkeeper"
		sequence = _append_npc(role, settlement_id, policy_id, seed, sequence, contract, target_index, social_target, fallback_target, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	for contract in _selected_contracts(contracts_by_use, "production", 3):
		sequence = _append_npc("worker", settlement_id, policy_id, seed, sequence, contract, target_index, social_target, fallback_target, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	for contract in _selected_contracts(contracts_by_use, "public", 2):
		sequence = _append_npc("traveler", settlement_id, policy_id, seed, sequence, contract, target_index, social_target, fallback_target, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	if definitions.is_empty() and not fallback_target.is_empty():
		sequence = _append_npc("resident", settlement_id, policy_id, seed, sequence, {}, target_index, social_target, fallback_target, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	return {
		"npc_definitions": definitions,
		"npc_role_assignments": assignments,
		"npc_spawn_rows_by_location": spawn_rows_by_location,
		"population_summary": {
			"settlement_id": settlement_id,
			"policy_id": policy_id,
			"seed": seed,
			"npc_count": definitions.size(),
			"role_counts": role_counts,
			"spawn_location_count": spawn_rows_by_location.size(),
			"unresolved_targets": unresolved,
		},
	}


func _append_npc(
	role: String,
	settlement_id: String,
	policy_id: String,
	seed: int,
	sequence: int,
	contract: Dictionary,
	target_index: Dictionary,
	social_target: Dictionary,
	fallback_target: Dictionary,
	definitions: Array[Dictionary],
	assignments: Array[Dictionary],
	spawn_rows_by_location: Dictionary,
	unresolved: Array[Dictionary],
	role_counts: Dictionary
) -> int:
	if definitions.size() >= MAX_GENERATED_NPCS:
		return sequence

	var npc_id := "%s__npc_%s_%03d" % [settlement_id, role, sequence]
	var assignment := _assignment_for_role(npc_id, role, contract, target_index, social_target, fallback_target)
	var schedule: Array[Dictionary] = _schedule_planner.build_schedule(npc_id, role, assignment)
	var validation: Dictionary = _validate_assignment_and_schedule(npc_id, assignment, schedule)
	if not (validation.get("errors", []) as Array).is_empty():
		unresolved.append(validation)
	if schedule.is_empty():
		return sequence + 1

	var definition := _npc_definition(npc_id, role, settlement_id, policy_id, seed, assignment, schedule, sequence)
	definitions.append(definition)
	assignments.append(_assignment_record(npc_id, role, assignment, validation))
	_add_spawn_rows(npc_id, role, schedule, spawn_rows_by_location)
	role_counts[role] = int(role_counts.get(role, 0)) + 1
	return sequence + 1


func _assignment_for_role(npc_id: String, role: String, contract: Dictionary, target_index: Dictionary, social_target: Dictionary, fallback_target: Dictionary) -> Dictionary:
	var home_target: Dictionary = _target_for_contract(target_index, contract, ["bed", "home"])
	var rest_target: Dictionary = _target_for_contract(target_index, contract, ["bed", "rest", "home"])
	var work_target: Dictionary = {}
	match role:
		"merchant", "shopkeeper", "innkeeper":
			work_target = _target_for_contract(target_index, contract, ["counter", "service", "tavern_counter"])
		"worker", "crafter", "blacksmith":
			work_target = _target_for_contract(target_index, contract, ["workstation", "work"])
		"guard", "trainer":
			work_target = _target_for_contract(target_index, contract, ["training", "trainer_spot"])
		_:
			work_target = _target_for_contract(target_index, contract, ["activity", "gathering", "home"])

	if home_target.is_empty():
		home_target = _first_target_for_roles(target_index, ["bed", "home", "rest"])
	if rest_target.is_empty():
		rest_target = home_target
	if work_target.is_empty():
		work_target = _first_target_for_roles(target_index, ["workstation", "work", "counter", "service", "activity", "exterior_transition"])
	if social_target.is_empty():
		social_target = _first_target_for_roles(target_index, ["gathering", "activity", "dining", "rest", "exterior_transition"])
	if fallback_target.is_empty():
		fallback_target = _first_target_for_roles(target_index, ["exterior_transition", "home", "bed", "workstation", "counter"])

	return {
		"npc_id": npc_id,
		"role": role,
		"source_building_id": str(contract.get("building_id", contract.get("source_building_id", ""))),
		"home_target": home_target,
		"work_target": work_target,
		"social_target": social_target,
		"rest_target": rest_target,
		"fallback_target": fallback_target,
	}


func _npc_definition(npc_id: String, role: String, settlement_id: String, policy_id: String, seed: int, assignment: Dictionary, schedule: Array[Dictionary], sequence: int) -> Dictionary:
	var display_role := role.capitalize().replace("_", " ")
	return {
		"id": npc_id,
		"display_name": "%s %02d" % [display_role, sequence],
		"character_kind": "npc",
		"generated": true,
		"source_settlement_id": settlement_id,
		"policy_id": policy_id,
		"seed": seed,
		"role": role,
		"role_tags": [role, "generated", "settlement_population"],
		"home_location_id": str((assignment.get("home_target", {}) as Dictionary).get("location_id", "")),
		"home_anchor_id": str((assignment.get("home_target", {}) as Dictionary).get("anchor_id", "")),
		"work_location_id": str((assignment.get("work_target", {}) as Dictionary).get("location_id", "")),
		"work_anchor_id": str((assignment.get("work_target", {}) as Dictionary).get("anchor_id", "")),
		"social_location_id": str((assignment.get("social_target", {}) as Dictionary).get("location_id", "")),
		"social_anchor_id": str((assignment.get("social_target", {}) as Dictionary).get("anchor_id", "")),
		"portrait_pool": _portrait_pool_for_role(role),
		"sprite_pool": _sprite_pool_for_role(role),
		"dialogue_profile_id": "generated_%s" % role,
		"personality_tag": _personality_for_role(role),
		"attributes": _attributes_for_role(role),
		"identity": {
			"age": 24 + (sequence % 23),
			"species": "human",
			"gender": "unspecified",
			"origin": settlement_id,
			"occupation": role,
			"personality": _personality_for_role(role),
		},
		"appearance_profile": {
			"importance": "common",
			"role": _appearance_role_for_role(role),
			"gender_hint": "neutral",
			"age_hint": "adult",
			"wealth": "common",
			"culture": "village",
			"neatness": "medium",
		},
		"faction_id": "field_neutral",
		"relation_slots": {
			"personal": {},
			"faction": {},
		},
		"is_player_controlled": false,
		"is_interactable": true,
		"is_combatable": false,
		"blocks_movement": true,
		"schedule": schedule,
	}


func _assignment_record(npc_id: String, role: String, assignment: Dictionary, validation: Dictionary) -> Dictionary:
	return {
		"npc_id": npc_id,
		"role": role,
		"source_building_id": str(assignment.get("source_building_id", "")),
		"home_target": (assignment.get("home_target", {}) as Dictionary).duplicate(true),
		"work_target": (assignment.get("work_target", {}) as Dictionary).duplicate(true),
		"social_target": (assignment.get("social_target", {}) as Dictionary).duplicate(true),
		"rest_target": (assignment.get("rest_target", {}) as Dictionary).duplicate(true),
		"fallback_target": (assignment.get("fallback_target", {}) as Dictionary).duplicate(true),
		"validation": validation.duplicate(true),
	}


func _add_spawn_rows(npc_id: String, role: String, schedule: Array[Dictionary], spawn_rows_by_location: Dictionary) -> void:
	var location_ids: Array[String] = []
	for entry in schedule:
		var location_id := str(entry.get("location_id", ""))
		if location_id.is_empty() or location_ids.has(location_id):
			continue
		location_ids.append(location_id)

	for location_id in location_ids:
		if not spawn_rows_by_location.has(location_id):
			spawn_rows_by_location[location_id] = []
		var rows: Array = spawn_rows_by_location.get(location_id, []) as Array
		rows.append({
			"id": npc_id,
			"source": "",
			"spawn_tags": ["generated", role],
		})
		spawn_rows_by_location[location_id] = rows


func _validate_assignment_and_schedule(npc_id: String, assignment: Dictionary, schedule: Array[Dictionary]) -> Dictionary:
	var errors: Array[Dictionary] = []
	for key in ["home_target", "work_target", "social_target", "rest_target"]:
		var target: Dictionary = assignment.get(key, {}) as Dictionary
		if str(target.get("location_id", "")).is_empty() or str(target.get("anchor_id", "")).is_empty():
			errors.append({ "type": "missing_target", "key": key })
	for entry in schedule:
		if str(entry.get("location_id", "")).is_empty() or str(entry.get("anchor_id", "")).is_empty():
			errors.append({
				"type": "unresolved_schedule_entry",
				"entry_id": str(entry.get("id", "")),
			})
	return {
		"npc_id": npc_id,
		"errors": errors,
	}


func _build_target_index(schedule_targets: Array) -> Dictionary:
	var by_role: Dictionary = {}
	var by_building: Dictionary = {}
	for target_value in schedule_targets:
		var target: Dictionary = (target_value as Dictionary).duplicate(true)
		var role := str(target.get("role", ""))
		var building_id := str(target.get("source_building_id", ""))
		target["global_target_id"] = "%s:%s" % [str(target.get("location_id", "")), str(target.get("anchor_id", ""))]
		if not by_role.has(role):
			by_role[role] = []
		(by_role[role] as Array).append(target)
		if not building_id.is_empty():
			if not by_building.has(building_id):
				by_building[building_id] = []
			(by_building[building_id] as Array).append(target)
	return {
		"by_role": by_role,
		"by_building": by_building,
	}


func _contracts_by_use(building_contracts: Array) -> Dictionary:
	var result: Dictionary = {}
	for contract_value in building_contracts:
		var contract: Dictionary = contract_value as Dictionary
		var use_type := str(contract.get("use_type", "public"))
		if not result.has(use_type):
			result[use_type] = []
		(result[use_type] as Array).append(contract)
	return result


func _selected_contracts(contracts_by_use: Dictionary, use_type: String, limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rows: Array = contracts_by_use.get(use_type, []) as Array
	for row_value in rows:
		if result.size() >= limit:
			break
		result.append((row_value as Dictionary).duplicate(true))
	return result


func _target_for_contract(target_index: Dictionary, contract: Dictionary, roles: Array[String]) -> Dictionary:
	var building_id := str(contract.get("building_id", contract.get("source_building_id", "")))
	var by_building: Dictionary = target_index.get("by_building", {}) as Dictionary
	var rows: Array = by_building.get(building_id, []) as Array
	for role in roles:
		for row_value in rows:
			var row: Dictionary = row_value as Dictionary
			if str(row.get("role", "")) == role:
				return row.duplicate(true)
	return _first_target_for_roles(target_index, roles)


func _first_target_for_roles(target_index: Dictionary, roles: Array[String]) -> Dictionary:
	var by_role: Dictionary = target_index.get("by_role", {}) as Dictionary
	for role in roles:
		var rows: Array = by_role.get(role, []) as Array
		if rows.is_empty():
			continue
		return (rows[0] as Dictionary).duplicate(true)
	return {}


func _attributes_for_role(role: String) -> Dictionary:
	match role:
		"guard", "trainer":
			return { "level": 2, "strength": 5, "agility": 4, "intellect": 3, "vitality": 6 }
		"merchant", "shopkeeper", "innkeeper":
			return { "level": 1, "strength": 3, "agility": 3, "intellect": 5, "vitality": 4 }
		"worker", "crafter", "blacksmith":
			return { "level": 1, "strength": 5, "agility": 3, "intellect": 4, "vitality": 5 }
		_:
			return { "level": 1, "strength": 3, "agility": 3, "intellect": 4, "vitality": 4 }


func _appearance_role_for_role(role: String) -> String:
	match role:
		"merchant", "shopkeeper", "innkeeper":
			return "merchant"
		"worker", "crafter", "blacksmith":
			return "worker"
		"guard", "trainer":
			return "guard"
		"traveler":
			return "traveler"
		_:
			return "villager"


func _portrait_pool_for_role(role: String) -> String:
	return "generated_%s_pool" % _appearance_role_for_role(role)


func _sprite_pool_for_role(role: String) -> String:
	return "generated_%s_sprites" % _appearance_role_for_role(role)


func _personality_for_role(role: String) -> String:
	match role:
		"merchant", "shopkeeper", "innkeeper":
			return "practical"
		"worker", "crafter", "blacksmith":
			return "steady"
		"guard", "trainer":
			return "watchful"
		"traveler":
			return "curious"
		_:
			return "calm"
