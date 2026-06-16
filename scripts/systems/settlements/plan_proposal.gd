class_name PlanProposal
extends RefCounted

const STATUS_CREATED := "created"
const STATUS_REJECTED := "rejected"
const STATUS_ACCEPTED := "accepted"
const STATUS_COMMITTED := "committed"
const STATUS_SUPERSEDED := "superseded"

var proposal_id: String = ""
var proposer_id: String = ""
var phase: String = ""
var type: String = ""
var priority: int = 0
var score: float = 0.0
var cost: float = 0.0
var reason: String = ""
var affected_cells: Array[Vector2i] = []
var area: Dictionary = {}
var path: Array[Vector2i] = []
var tags: Array[String] = []
var dependencies: Array[String] = []
var conflicts: Array[String] = []
var payload: Dictionary = {}
var validation_notes: Array[String] = []
var status: String = STATUS_CREATED


static func create(
	p_proposer_id: String,
	p_type: String,
	p_phase: String,
	p_reason: String,
	p_priority: int = 0
) -> PlanProposal:
	var proposal := PlanProposal.new()
	proposal.proposer_id = p_proposer_id
	proposal.type = p_type
	proposal.phase = p_phase
	proposal.reason = p_reason
	proposal.priority = p_priority
	return proposal


func primary_cell() -> Vector2i:
	if not affected_cells.is_empty():
		return affected_cells[0]
	if payload.has("cell"):
		return _cell_from_variant(payload.get("cell"))
	return Vector2i(-9999, -9999)


func duplicate_for_trace() -> Dictionary:
	return to_dictionary()


func to_dictionary() -> Dictionary:
	return {
		"proposal_id": proposal_id,
		"proposer_id": proposer_id,
		"phase": phase,
		"type": type,
		"priority": priority,
		"score": score,
		"cost": cost,
		"reason": reason,
		"affected_cells": _cells_to_dicts(affected_cells),
		"area": area.duplicate(true),
		"path": _cells_to_dicts(path),
		"tags": tags.duplicate(),
		"dependencies": dependencies.duplicate(),
		"conflicts": conflicts.duplicate(),
		"payload": _payload_to_dictionary(),
		"validation_notes": validation_notes.duplicate(),
		"status": status,
	}


func _payload_to_dictionary() -> Dictionary:
	var result := payload.duplicate(true)
	if result.has("cell"):
		var cell := _cell_from_variant(result.get("cell"))
		result["cell"] = { "x": cell.x, "y": cell.y }
	return result


static func _cells_to_dicts(cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in cells:
		result.append({ "x": cell.x, "y": cell.y })
	return result


static func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
