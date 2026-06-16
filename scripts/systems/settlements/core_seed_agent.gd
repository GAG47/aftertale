class_name CoreSeedAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "core_seed_agent"


func is_active(session) -> bool:
	return session.current_phase == "core" and session.blueprint.cores.is_empty()


func propose(session) -> Array[PlanProposal]:
	var center := Vector2i(session.context.map_size.x / 2, session.context.map_size.y / 2)
	var offset := Vector2i(
		session.randi_range(-1, 1, "core_offset_x"),
		session.randi_range(-1, 1, "core_offset_y")
	)
	var cell := center + offset
	var proposal := PlanProposal.create(agent_id, "add_core", session.current_phase, "Create the first settlement core.", 100)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.affected_cells = [cell]
	proposal.payload = { "id": "core_main", "cell": cell }
	proposal.tags = ["core", "v61_debug"]
	return [proposal]


func score(proposal: PlanProposal, session) -> float:
	var cell := proposal.primary_cell()
	var center_distance: float = session.feature_maps.get_value("center_distance", cell, 99.0)
	return 100.0 - center_distance
