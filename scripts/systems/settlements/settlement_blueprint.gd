class_name SettlementBlueprint
extends RefCounted

const COMMIT_TOKEN := "settlement_resolver_commit_v61"

var cores: Array[Dictionary] = []
var districts: Array[Dictionary] = []
var roads: Array[Dictionary] = []
var plots: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var production_areas: Array[Dictionary] = []
var defenses: Array[Dictionary] = []
var decorations: Array[Dictionary] = []
var entrances: Array[Dictionary] = []
var exits: Array[Dictionary] = []
var interaction_anchors: Array[Dictionary] = []
var history: Array[Dictionary] = []
var committed_proposal_ids: Array[String] = []


func apply_committed_proposal(proposal: PlanProposal, commit_token: String) -> bool:
	if commit_token != COMMIT_TOKEN:
		return false
	if proposal == null:
		return false

	match proposal.type:
		"add_core":
			cores.append({
				"id": str(proposal.payload.get("id", "core_%d" % cores.size())),
				"cell": _dict_cell(proposal.primary_cell()),
				"tags": proposal.tags.duplicate(),
			})
		"add_anchor":
			interaction_anchors.append({
				"id": str(proposal.payload.get("id", "anchor_%d" % interaction_anchors.size())),
				"kind": str(proposal.payload.get("kind", "approach")),
				"cell": _dict_cell(proposal.primary_cell()),
				"tags": proposal.tags.duplicate(),
			})
		"add_path", "add_road":
			roads.append({
				"id": str(proposal.payload.get("id", "road_%d" % roads.size())),
				"kind": str(proposal.payload.get("kind", "settlement_road")),
				"path": _cells_to_dicts(proposal.path),
				"tags": proposal.tags.duplicate(),
			})
		"add_plot":
			plots.append({
				"id": str(proposal.payload.get("id", "plot_%d" % plots.size())),
				"kind": str(proposal.payload.get("kind", "general")),
				"area": _rect_to_dictionary(proposal.area),
				"road_access_cell": _dict_cell(_cell_from_variant(proposal.payload.get("road_access_cell", Vector2i(-9999, -9999)))),
				"tags": proposal.tags.duplicate(),
			})
		"add_building":
			buildings.append({
				"id": str(proposal.payload.get("id", "building_%d" % buildings.size())),
				"kind": str(proposal.payload.get("kind", "house")),
				"plot_id": str(proposal.payload.get("plot_id", "")),
				"area": _rect_to_dictionary(proposal.area),
				"entrance_cell": _dict_cell(_cell_from_variant(proposal.payload.get("entrance_cell", proposal.primary_cell()))),
				"tags": proposal.tags.duplicate(),
			})
		"add_landmark":
			landmarks.append({
				"id": str(proposal.payload.get("id", "landmark_%d" % landmarks.size())),
				"kind": str(proposal.payload.get("kind", "well")),
				"cell": _dict_cell(proposal.primary_cell()),
				"tags": proposal.tags.duplicate(),
			})
		_:
			return false

	committed_proposal_ids.append(proposal.proposal_id)
	history.append({
		"proposal_id": proposal.proposal_id,
		"type": proposal.type,
		"reason": proposal.reason,
	})
	return true


func committed_count() -> int:
	return committed_proposal_ids.size()


func to_dictionary() -> Dictionary:
	return {
		"cores": cores.duplicate(true),
		"districts": districts.duplicate(true),
		"roads": roads.duplicate(true),
		"plots": plots.duplicate(true),
		"buildings": buildings.duplicate(true),
		"landmarks": landmarks.duplicate(true),
		"production_areas": production_areas.duplicate(true),
		"defenses": defenses.duplicate(true),
		"decorations": decorations.duplicate(true),
		"entrances": entrances.duplicate(true),
		"exits": exits.duplicate(true),
		"interaction_anchors": interaction_anchors.duplicate(true),
		"history": history.duplicate(true),
		"committed_proposal_ids": committed_proposal_ids.duplicate(),
	}


static func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


static func _cells_to_dicts(cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in cells:
		result.append(_dict_cell(cell))
	return result


static func _rect_to_dictionary(rect: Dictionary) -> Dictionary:
	return {
		"x": int(rect.get("x", 0)),
		"y": int(rect.get("y", 0)),
		"width": int(rect.get("width", 0)),
		"height": int(rect.get("height", 0)),
	}


static func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
