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
	var target_allocator: Dictionary = _build_target_allocator(target_index)
	var contracts_by_use: Dictionary = _contracts_by_use(building_contracts)

	var definitions: Array[Dictionary] = []
	var assignments: Array[Dictionary] = []
	var spawn_rows_by_location: Dictionary = {}
	var unresolved: Array[Dictionary] = []
	var role_counts: Dictionary = {}
	var sequence: int = 1

	for contract in _selected_contracts(contracts_by_use, "residential", 4):
		sequence = _append_npc("resident", settlement_id, policy_id, seed, sequence, contract, target_index, target_allocator, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	for contract in _selected_contracts(contracts_by_use, "commercial", 3):
		var role := "shopkeeper"
		if _target_for_contract(target_index, contract, ["tavern", "tavern_counter"]).is_empty():
			role = "merchant"
		else:
			role = "innkeeper"
		sequence = _append_npc(role, settlement_id, policy_id, seed, sequence, contract, target_index, target_allocator, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	for contract in _selected_contracts(contracts_by_use, "production", 3):
		sequence = _append_npc("worker", settlement_id, policy_id, seed, sequence, contract, target_index, target_allocator, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	for contract in _selected_contracts(contracts_by_use, "public", 2):
		sequence = _append_npc("traveler", settlement_id, policy_id, seed, sequence, contract, target_index, target_allocator, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	if definitions.is_empty() and _allocator_has_available_targets(target_allocator):
		sequence = _append_npc("resident", settlement_id, policy_id, seed, sequence, {}, target_index, target_allocator, definitions, assignments, spawn_rows_by_location, unresolved, role_counts)

	var occupancy_audit := _audit_schedule_occupancy(definitions)
	if not (occupancy_audit.get("conflicts", []) as Array).is_empty():
		for conflict in (occupancy_audit.get("conflicts", []) as Array):
			unresolved.append(conflict as Dictionary)

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
			"target_allocation": _allocation_summary(target_allocator),
			"schedule_occupancy": occupancy_audit,
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
	target_allocator: Dictionary,
	definitions: Array[Dictionary],
	assignments: Array[Dictionary],
	spawn_rows_by_location: Dictionary,
	unresolved: Array[Dictionary],
	role_counts: Dictionary
) -> int:
	if definitions.size() >= MAX_GENERATED_NPCS:
		return sequence

	var npc_id := "%s__npc_%s_%03d" % [settlement_id, role, sequence]
	var assignment := _assignment_for_role(npc_id, role, contract, target_index, target_allocator)
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


func _assignment_for_role(npc_id: String, role: String, contract: Dictionary, target_index: Dictionary, target_allocator: Dictionary) -> Dictionary:
	var assigned_slots: Array[Dictionary] = []
	var fallbacks: Array[Dictionary] = []
	var reserved_keys: Array[String] = []
	var home_target: Dictionary = _claim_target_for_contract(target_allocator, target_index, contract, ["bed", "home"], npc_id, "home", assigned_slots, reserved_keys)
	var rest_target: Dictionary = home_target.duplicate(true)
	var work_target: Dictionary = {}
	match role:
		"merchant", "shopkeeper", "innkeeper":
			work_target = _claim_target_for_contract(target_allocator, target_index, contract, ["counter", "service", "tavern_counter"], npc_id, "work", assigned_slots, reserved_keys)
		"worker", "crafter", "blacksmith":
			work_target = _claim_target_for_contract(target_allocator, target_index, contract, ["workstation", "work"], npc_id, "work", assigned_slots, reserved_keys)
		"guard", "trainer":
			work_target = _claim_target_for_contract(target_allocator, target_index, contract, ["training", "trainer_spot"], npc_id, "work", assigned_slots, reserved_keys)
		_:
			work_target = _claim_target_for_contract(target_allocator, target_index, contract, ["activity", "gathering", "home"], npc_id, "work", assigned_slots, reserved_keys)

	if home_target.is_empty():
		home_target = _claim_first_target(target_allocator, target_index, ["bed", "home", "rest", "interior_entry"], npc_id, "home", assigned_slots, reserved_keys, fallbacks, "contract_home_unavailable")
		rest_target = home_target.duplicate(true)
	if work_target.is_empty():
		work_target = _claim_first_target(target_allocator, target_index, ["workstation", "work", "counter", "service", "tavern_counter", "activity", "gathering", "exterior_transition"], npc_id, "work", assigned_slots, reserved_keys, fallbacks, "contract_work_unavailable")
	var social_target := _claim_first_target(target_allocator, target_index, ["dining", "tavern", "gathering", "activity", "public", "building_entrance", "exterior_transition"], npc_id, "social", assigned_slots, reserved_keys, fallbacks, "social_target_unavailable")
	if social_target.is_empty():
		social_target = _first_valid_target([work_target, home_target, rest_target])
		if not social_target.is_empty():
			fallbacks.append({
				"kind": "social_reuses_existing_assignment",
				"target_key": str(social_target.get("target_key", social_target.get("global_target_id", ""))),
			})
	if rest_target.is_empty():
		rest_target = home_target.duplicate(true)
	if rest_target.is_empty():
		rest_target = _first_valid_target([home_target, work_target, social_target])
	var fallback_target := _first_valid_target([social_target, work_target, home_target, rest_target])
	if fallback_target.is_empty():
		fallback_target = _claim_first_target(target_allocator, target_index, ["building_entrance", "exterior_transition", "interior_entry"], npc_id, "fallback", assigned_slots, reserved_keys, fallbacks, "fallback_target_unavailable")

	return {
		"npc_id": npc_id,
		"role": role,
		"source_building_id": str(contract.get("building_id", contract.get("source_building_id", ""))),
		"home_target": home_target,
		"work_target": work_target,
		"social_target": social_target,
		"rest_target": rest_target,
		"fallback_target": fallback_target,
		"assigned_target_slots": assigned_slots,
		"fallbacks": fallbacks,
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
		"appearance": _appearance_for_role(role),
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
		"id": "%s__role_assignment" % npc_id,
		"npc_id": npc_id,
		"role": role,
		"source_building_id": str(assignment.get("source_building_id", "")),
		"home_target": (assignment.get("home_target", {}) as Dictionary).duplicate(true),
		"work_target": (assignment.get("work_target", {}) as Dictionary).duplicate(true),
		"social_target": (assignment.get("social_target", {}) as Dictionary).duplicate(true),
		"rest_target": (assignment.get("rest_target", {}) as Dictionary).duplicate(true),
		"fallback_target": (assignment.get("fallback_target", {}) as Dictionary).duplicate(true),
		"assigned_target_slots": (assignment.get("assigned_target_slots", []) as Array).duplicate(true),
		"fallbacks": (assignment.get("fallbacks", []) as Array).duplicate(true),
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
		target["global_target_id"] = _target_key(target)
		target["target_key"] = _target_key(target)
		target["capacity"] = _capacity_for_target(target)
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


func _build_target_allocator(target_index: Dictionary) -> Dictionary:
	var allocator: Dictionary = {}
	var by_role: Dictionary = target_index.get("by_role", {}) as Dictionary
	for role in by_role.keys():
		for row_value in (by_role.get(role, []) as Array):
			var row: Dictionary = row_value as Dictionary
			var key := _target_key(row)
			if key.is_empty() or allocator.has(key):
				continue
			var capacity := _capacity_for_target(row)
			allocator[key] = {
				"target": row.duplicate(true),
				"capacity": capacity,
				"claimed": [],
			}
	return allocator


func _claim_target_for_contract(
	target_allocator: Dictionary,
	target_index: Dictionary,
	contract: Dictionary,
	roles: Array[String],
	npc_id: String,
	claim_kind: String,
	assigned_slots: Array[Dictionary],
	reserved_keys: Array[String]
) -> Dictionary:
	var building_id := str(contract.get("building_id", contract.get("source_building_id", "")))
	var by_building: Dictionary = target_index.get("by_building", {}) as Dictionary
	var rows: Array = by_building.get(building_id, []) as Array
	var candidates: Array[Dictionary] = []
	for role in roles:
		for row_value in rows:
			var row: Dictionary = row_value as Dictionary
			if str(row.get("role", "")) == role:
				candidates.append(row)
	var claimed := _claim_from_candidates(target_allocator, candidates, npc_id, claim_kind, assigned_slots, reserved_keys)
	if not claimed.is_empty():
		return claimed
	return {}


func _claim_first_target(
	target_allocator: Dictionary,
	target_index: Dictionary,
	roles: Array[String],
	npc_id: String,
	claim_kind: String,
	assigned_slots: Array[Dictionary],
	reserved_keys: Array[String],
	fallbacks: Array[Dictionary],
	fallback_reason: String
) -> Dictionary:
	var by_role: Dictionary = target_index.get("by_role", {}) as Dictionary
	var candidates: Array[Dictionary] = []
	for role in roles:
		for row_value in (by_role.get(role, []) as Array):
			candidates.append(row_value as Dictionary)
	var claimed := _claim_from_candidates(target_allocator, candidates, npc_id, claim_kind, assigned_slots, reserved_keys)
	if claimed.is_empty():
		fallbacks.append({
			"kind": fallback_reason,
			"roles": roles.duplicate(),
		})
	else:
		fallbacks.append({
			"kind": fallback_reason,
			"resolved_target_key": str(claimed.get("target_key", "")),
			"role": str(claimed.get("role", "")),
		})
	return claimed


func _claim_from_candidates(
	target_allocator: Dictionary,
	candidates: Array[Dictionary],
	npc_id: String,
	claim_kind: String,
	assigned_slots: Array[Dictionary],
	reserved_keys: Array[String]
) -> Dictionary:
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var key := _target_key(candidate)
		if key.is_empty() or reserved_keys.has(key):
			continue
		var allocation: Dictionary = target_allocator.get(key, {}) as Dictionary
		if allocation.is_empty():
			continue
		var claimed_rows: Array = allocation.get("claimed", []) as Array
		var capacity := int(allocation.get("capacity", 1))
		if claimed_rows.size() >= capacity:
			continue
		var slot_index := claimed_rows.size()
		var target := (allocation.get("target", candidate) as Dictionary).duplicate(true)
		target["target_key"] = key
		target["capacity"] = capacity
		target["slot_index"] = slot_index
		_apply_slot_position(target, slot_index)
		var claim := {
			"npc_id": npc_id,
			"claim_kind": claim_kind,
			"target_key": key,
			"role": str(target.get("role", "")),
			"location_id": str(target.get("location_id", "")),
			"anchor_id": str(target.get("anchor_id", "")),
			"capacity": capacity,
			"slot_index": slot_index,
		}
		claimed_rows.append(claim)
		allocation["claimed"] = claimed_rows
		target_allocator[key] = allocation
		assigned_slots.append(claim.duplicate(true))
		reserved_keys.append(key)
		return target
	return {}


func _apply_slot_position(target: Dictionary, slot_index: int) -> void:
	var activity_cells: Array = target.get("activity_cells", []) as Array
	if slot_index >= 0 and slot_index < activity_cells.size():
		target["grid_position"] = (activity_cells[slot_index] as Dictionary).duplicate(true)
		target["uses_capacity_slot"] = true
		return
	if target.has("grid_position"):
		target["grid_position"] = (target.get("grid_position", {}) as Dictionary).duplicate(true)


func _capacity_for_target(target: Dictionary) -> int:
	var declared := int(target.get("capacity", 0))
	if declared > 0:
		if declared > 1 and (target.get("activity_cells", []) as Array).is_empty():
			return 1
		return declared
	var role := str(target.get("role", ""))
	match role:
		"dining", "tavern", "social", "gathering", "activity", "public":
			return max(1, min(4, (target.get("activity_cells", []) as Array).size()))
		_:
			return 1


func _target_key(target: Dictionary) -> String:
	var location_id := str(target.get("location_id", ""))
	var anchor_id := str(target.get("anchor_id", ""))
	if location_id.is_empty() or anchor_id.is_empty():
		return ""
	return "%s:%s" % [location_id, anchor_id]


func _allocator_has_available_targets(target_allocator: Dictionary) -> bool:
	for key in target_allocator.keys():
		var allocation: Dictionary = target_allocator.get(key, {}) as Dictionary
		if (allocation.get("claimed", []) as Array).size() < int(allocation.get("capacity", 1)):
			return true
	return false


func _first_valid_target(targets: Array) -> Dictionary:
	for value in targets:
		var target: Dictionary = value as Dictionary
		if not str(target.get("location_id", "")).is_empty() and not str(target.get("anchor_id", "")).is_empty():
			return target.duplicate(true)
	return {}


func _audit_schedule_occupancy(definitions: Array[Dictionary]) -> Dictionary:
	var occupied_rows: Array[Dictionary] = []
	var conflicts: Array[Dictionary] = []
	for definition in definitions:
		var npc_id := str(definition.get("id", ""))
		for entry_value in (definition.get("schedule", []) as Array):
			var entry: Dictionary = entry_value as Dictionary
			for interval in _entry_intervals(entry):
				var row := {
					"npc_id": npc_id,
					"entry_id": str(entry.get("id", "")),
					"location_id": str(entry.get("location_id", "")),
					"cell_key": _schedule_cell_key(entry),
					"start": int(interval.get("start", 0)),
					"end": int(interval.get("end", 0)),
				}
				for existing_value in occupied_rows:
					var existing: Dictionary = existing_value as Dictionary
					if str(existing.get("location_id", "")) != str(row.get("location_id", "")):
						continue
					if str(existing.get("cell_key", "")) != str(row.get("cell_key", "")):
						continue
					if not _intervals_overlap(existing, row):
						continue
					conflicts.append({
						"type": "schedule_occupancy_conflict",
						"npc_id": npc_id,
						"other_npc_id": str(existing.get("npc_id", "")),
						"entry_id": str(entry.get("id", "")),
						"other_entry_id": str(existing.get("entry_id", "")),
						"location_id": str(row.get("location_id", "")),
						"cell_key": str(row.get("cell_key", "")),
					})
				occupied_rows.append(row)
	return {
		"conflict_count": conflicts.size(),
		"conflicts": conflicts,
		"occupied_slot_count": occupied_rows.size(),
	}


func _schedule_cell_key(entry: Dictionary) -> String:
	var grid_position: Dictionary = entry.get("grid_position", {}) as Dictionary
	if not grid_position.is_empty():
		return "%s,%s" % [int(grid_position.get("x", 0)), int(grid_position.get("y", 0))]
	return str(entry.get("anchor_id", ""))


func _allocation_summary(target_allocator: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	for key in target_allocator.keys():
		var allocation: Dictionary = target_allocator.get(key, {}) as Dictionary
		var claimed: Array = allocation.get("claimed", []) as Array
		if claimed.is_empty():
			continue
		rows.append({
			"target_key": str(key),
			"capacity": int(allocation.get("capacity", 1)),
			"claimed_count": claimed.size(),
			"claimed": claimed.duplicate(true),
		})
	return {
		"claimed_target_count": rows.size(),
		"claimed_targets": rows,
	}


func _entry_intervals(entry: Dictionary) -> Array[Dictionary]:
	var start_minutes := _time_to_minutes(str(entry.get("start", "00:00")))
	var end_minutes := _time_to_minutes(str(entry.get("end", "00:00")))
	if end_minutes < start_minutes:
		return [
			{ "start": start_minutes, "end": 1440 },
			{ "start": 0, "end": end_minutes },
		]
	return [{ "start": start_minutes, "end": end_minutes }]


func _intervals_overlap(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("start", 0)) <= int(b.get("end", 0)) and int(b.get("start", 0)) <= int(a.get("end", 0))


func _time_to_minutes(value: String) -> int:
	var parts := value.split(":")
	if parts.size() < 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])


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


func _appearance_for_role(_role: String) -> Dictionary:
	return {
		"display_mode": "map_sprite",
		"map_sprite": {
			"source": "res://assets/art/characters/map_sprites/npc_guard_001.png",
			"offset": { "x": 0, "y": 10 },
			"scale": 0.034,
			"anchor": { "x": 0.5, "y": 0.94 },
		},
		"portrait": {
			"id": "npc_guard_001",
			"full": "res://assets/art/characters/portraits/full/npc_guard_001.png",
			"avatar": "res://assets/art/characters/portraits/avatars/npc_guard_001_avatar.png",
		},
	}


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
