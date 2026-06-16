class_name InvalidProposalAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "invalid_proposal_agent"
	spec = AgentSpecScript.create(5, 5, 1)


func is_active(session) -> bool:
	return session.current_step >= 5


func propose(session) -> Array[PlanProposal]:
	var bad_cell := Vector2i(session.context.map_size.x + 4, session.context.map_size.y + 4)
	var proposal := PlanProposal.create(agent_id, "add_core_seed", session.current_step, "blueprint_growth", "Submit an intentionally invalid out-of-bounds proposal.", 999)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	var affected_cells: Array[Vector2i] = [bad_cell]
	proposal.affected_cells = affected_cells
	proposal.payload = { "id": "invalid_out_of_bounds_core", "cell": bad_cell }
	var tags: Array[String] = ["invalid", "v62_step_smoke"]
	proposal.tags = tags
	session.trace.record_agent_search(session.current_step, agent_id, {
		"valid_candidates_count": 0,
		"sampled_candidates_count": 1,
		"top_score": 0.0,
		"chosen_score": 0.0,
		"chosen_cell": { "x": bad_cell.x, "y": bad_cell.y },
		"rejected_reason_distribution": { "intentional_invalid": 1 },
	})
	var result: Array[PlanProposal] = []
	result.append(proposal)
	return result
