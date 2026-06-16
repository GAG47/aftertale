class_name InvalidProposalAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "invalid_proposal_agent"


func is_active(session) -> bool:
	return session.current_phase == "validation"


func propose(session) -> Array[PlanProposal]:
	var bad_cell := Vector2i(session.context.map_size.x + 4, session.context.map_size.y + 4)
	var proposal := PlanProposal.create(agent_id, "add_core", session.current_phase, "Submit an intentionally invalid out-of-bounds proposal.", 999)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.affected_cells = [bad_cell]
	proposal.payload = { "id": "invalid_out_of_bounds_core", "cell": bad_cell }
	proposal.tags = ["invalid", "v61_smoke"]
	return [proposal]
