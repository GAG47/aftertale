class_name SettlementGenerationSession
extends RefCounted

const RoadEndpointAgentScript := preload("res://scripts/systems/settlements/road_endpoint_agent.gd")
const RoadBranchAgentScript := preload("res://scripts/systems/settlements/road_branch_agent.gd")
const RoadReconnectAgentScript := preload("res://scripts/systems/settlements/road_reconnect_agent.gd")
const GenericPlotAgentScript := preload("res://scripts/systems/settlements/generic_plot_agent.gd")
const PlotDifferentiationAgentScript := preload("res://scripts/systems/settlements/plot_differentiation_agent.gd")
const BuildingFootprintAgentScript := preload("res://scripts/systems/settlements/building_footprint_agent.gd")
const InvalidConflictAgentScript := preload("res://scripts/systems/settlements/invalid_conflict_agent.gd")
const DemandLedgerScript := preload("res://scripts/systems/settlements/settlement_demand_ledger.gd")

const DEFAULT_MAX_BLUEPRINT_STEPS := 32

var policy: SettlementPolicy
var context: SettlementContext
var feature_maps: FeatureMapStore
var blueprint: SettlementBlueprint
var resolver: ProposalResolver
var evaluator: SettlementEvaluator
var trace: GenerationTrace
var demand_ledger: RefCounted
var active_agents: Array[SettlementAgent] = []
var current_step: int = -1
var committed_step: int = 0
var max_blueprint_steps: int = DEFAULT_MAX_BLUEPRINT_STEPS
var evaluation_feedback: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _proposal_sequence: int = 0
var _agent_commit_counts: Dictionary = {}


func _init(p_policy: SettlementPolicy = null, p_context: SettlementContext = null) -> void:
	policy = p_policy if p_policy != null else SettlementPolicy.new()
	context = p_context if p_context != null else SettlementContext.new()
	context.ensure_defaults()
	feature_maps = FeatureMapStore.new()
	blueprint = SettlementBlueprint.new()
	resolver = ProposalResolver.new()
	evaluator = SettlementEvaluator.new()
	trace = GenerationTrace.new()
	demand_ledger = DemandLedgerScript.new()


func run() -> Dictionary:
	_initialize_run()
	for step in range(max_blueprint_steps):
		current_step = step
		trace.record_step(step)
		var candidates: Array[PlanProposal] = []
		for agent in active_agents:
			if not agent.can_run(self):
				continue
			var proposals: Array[PlanProposal] = agent.propose(self)
			for proposal in proposals:
				candidates.append(proposal)
		resolver.resolve_step(candidates, self)
		trace.record_blueprint_snapshot(step, blueprint)
	trace.record_event("session_finished", {
		"committed_step": committed_step,
		"proposal_count": trace.proposals.size(),
		"max_blueprint_steps": max_blueprint_steps,
	})
	return get_result()


func randi_range(from_value: int, to_value: int, reason: String) -> int:
	var value := _rng.randi_range(from_value, to_value)
	trace.record_random_decision(current_step, reason, value)
	return value


func next_proposal_id(agent_id: String) -> String:
	_proposal_sequence += 1
	return "%s_%03d" % [agent_id, _proposal_sequence]


func record_agent_commit(agent_id: String) -> void:
	_agent_commit_counts[agent_id] = agent_commit_count(agent_id) + 1


func agent_commit_count(agent_id: String) -> int:
	return int(_agent_commit_counts.get(agent_id, 0))


func result_signature() -> String:
	return JSON.stringify({
		"blueprint": blueprint.to_dictionary(),
		"trace_summary": trace.summary(),
		"random_decisions": trace.random_decisions,
		"feature_update_count": feature_maps.update_count,
	})


func get_result() -> Dictionary:
	return {
		"policy": policy.to_dictionary(),
		"context": context.to_dictionary(),
		"blueprint": blueprint.to_dictionary(),
		"feature_maps": feature_maps.to_dictionary(),
		"trace": trace.to_dictionary(),
		"session_summary": {
			"current_step": current_step,
			"committed_step": committed_step,
			"proposal_sequence": _proposal_sequence,
			"max_blueprint_steps": max_blueprint_steps,
			"agent_commit_counts": _agent_commit_counts.duplicate(),
			"evaluation_feedback": evaluation_feedback.duplicate(true),
			"demand_ledger": demand_ledger.to_dictionary(),
			"result_signature": result_signature(),
		},
	}


func _initialize_run() -> void:
	_proposal_sequence = 0
	committed_step = 0
	current_step = -1
	evaluation_feedback.clear()
	_agent_commit_counts.clear()
	demand_ledger.reset()
	_rng.seed = _resolve_seed()
	feature_maps.initialize(context)
	blueprint = SettlementBlueprint.new()
	blueprint.set_context_entrances(context.entrances)
	trace = GenerationTrace.new()
	active_agents = [
		CoreSeedAgent.new(),
		RoadEndpointAgentScript.new(),
		RoadBranchAgentScript.new(),
		RoadReconnectAgentScript.new(),
		GenericPlotAgentScript.new("core_bias"),
		GenericPlotAgentScript.new("road_bias"),
		GenericPlotAgentScript.new("edge_bias"),
		PlotDifferentiationAgentScript.new(),
		BuildingFootprintAgentScript.new(),
		InvalidProposalAgent.new(),
		InvalidConflictAgentScript.new(),
	]
	trace.record_event("session_initialized", {
		"seed": _resolve_seed(),
		"agent_count": active_agents.size(),
		"max_blueprint_steps": max_blueprint_steps,
	})


func _resolve_seed() -> int:
	if policy.seed_override >= 0:
		return policy.seed_override
	return context.world_seed
