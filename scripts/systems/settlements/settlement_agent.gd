class_name SettlementAgent
extends RefCounted

const AgentSpecScript := preload("res://scripts/systems/settlements/settlement_agent_spec.gd")

var agent_id: String = "settlement_agent"
var spec = AgentSpecScript.create(0, 1, 1)


func can_run(session) -> bool:
	if session.current_step < spec.activation_step:
		return false
	if ((session.current_step - spec.activation_step) % spec.activation_interval) != 0:
		return false
	if session.agent_commit_count(agent_id) >= spec.max_commits:
		return false
	return is_active(session)


func is_active(_session) -> bool:
	return true


func propose(_session) -> Array[PlanProposal]:
	return []


func score(proposal: PlanProposal, _session) -> float:
	return float(proposal.priority)
