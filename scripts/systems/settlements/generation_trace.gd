class_name GenerationTrace
extends RefCounted

var proposals: Array[Dictionary] = []
var accepted_proposals: Array[Dictionary] = []
var rejected_proposals: Array[Dictionary] = []
var committed_proposals: Array[Dictionary] = []
var evaluator_reports: Array[Dictionary] = []
var random_decisions: Array[Dictionary] = []
var phase_transitions: Array[Dictionary] = []
var events: Array[Dictionary] = []


func record_phase(phase: String) -> void:
	phase_transitions.append({ "phase": phase, "index": phase_transitions.size() })


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


func record_random_decision(phase: String, reason: String, value: int) -> void:
	random_decisions.append({
		"phase": phase,
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
		"phase_transitions": phase_transitions.duplicate(true),
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
		"phase_count": phase_transitions.size(),
	}
