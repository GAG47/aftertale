class_name SettlementAgent
extends RefCounted

var agent_id: String = "settlement_agent"


func is_active(_session) -> bool:
	return true


func propose(_session) -> Array[PlanProposal]:
	return []


func score(proposal: PlanProposal, _session) -> float:
	return float(proposal.priority)
