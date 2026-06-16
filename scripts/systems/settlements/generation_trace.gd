class_name GenerationTrace
extends RefCounted

var proposals: Array[Dictionary] = []
var accepted_proposals: Array[Dictionary] = []
var rejected_proposals: Array[Dictionary] = []
var committed_proposals: Array[Dictionary] = []
var evaluator_reports: Array[Dictionary] = []
var random_decisions: Array[Dictionary] = []
var step_transitions: Array[Dictionary] = []
var step_resolutions: Array[Dictionary] = []
var agent_search_stats: Array[Dictionary] = []
var blueprint_snapshots: Array[Dictionary] = []
var events: Array[Dictionary] = []


func record_step(step: int) -> void:
	step_transitions.append({ "step": step, "index": step_transitions.size() })


func record_proposal(proposal: PlanProposal) -> void:
	proposals.append(proposal.duplicate_for_trace())


func record_accepted(proposal: PlanProposal) -> void:
	accepted_proposals.append(proposal.duplicate_for_trace())


func record_rejected(proposal: PlanProposal, notes: Array[String]) -> void:
	var entry := proposal.duplicate_for_trace()
	entry["validation_notes"] = notes.duplicate()
	rejected_proposals.append(entry)


func record_committed(proposal: PlanProposal) -> void:
	committed_proposals.append(proposal.duplicate_for_trace())


func record_evaluator_report(report: Dictionary) -> void:
	evaluator_reports.append(report.duplicate(true))


func record_step_resolution(step: int, winners: Array[PlanProposal], losers: Array[Dictionary]) -> void:
	var winner_rows: Array[Dictionary] = []
	for winner in winners:
		winner_rows.append(winner.duplicate_for_trace())
	step_resolutions.append({
		"step": step,
		"winners": winner_rows,
		"losers": losers.duplicate(true),
		"winner_count": winner_rows.size(),
		"loser_count": losers.size(),
	})


func record_agent_search(step: int, agent_id: String, stats: Dictionary) -> void:
	var row := stats.duplicate(true)
	row["step"] = step
	row["agent_id"] = agent_id
	agent_search_stats.append(row)


func record_blueprint_snapshot(step: int, blueprint: SettlementBlueprint) -> void:
	if blueprint == null:
		return
	blueprint_snapshots.append({
		"step": step,
		"blueprint": blueprint.to_dictionary(),
	})


func record_random_decision(step: int, reason: String, value: int) -> void:
	random_decisions.append({
		"step": step,
		"reason": reason,
		"value": value,
		"index": random_decisions.size(),
	})


func record_event(kind: String, data: Dictionary = {}) -> void:
	events.append({
		"kind": kind,
		"data": data.duplicate(true),
		"index": events.size(),
	})


func to_dictionary() -> Dictionary:
	return {
		"proposals": proposals.duplicate(true),
		"accepted_proposals": accepted_proposals.duplicate(true),
		"rejected_proposals": rejected_proposals.duplicate(true),
		"committed_proposals": committed_proposals.duplicate(true),
		"evaluator_reports": evaluator_reports.duplicate(true),
		"random_decisions": random_decisions.duplicate(true),
		"step_transitions": step_transitions.duplicate(true),
		"step_resolutions": step_resolutions.duplicate(true),
		"agent_search_stats": agent_search_stats.duplicate(true),
		"blueprint_snapshots": blueprint_snapshots.duplicate(true),
		"events": events.duplicate(true),
		"summary": summary(),
	}


func summary() -> Dictionary:
	return {
		"proposal_count": proposals.size(),
		"accepted_count": accepted_proposals.size(),
		"rejected_count": rejected_proposals.size(),
		"committed_count": committed_proposals.size(),
		"evaluator_report_count": evaluator_reports.size(),
		"random_decision_count": random_decisions.size(),
		"step_count": step_transitions.size(),
		"step_resolution_count": step_resolutions.size(),
		"agent_search_count": agent_search_stats.size(),
		"blueprint_snapshot_count": blueprint_snapshots.size(),
	}
