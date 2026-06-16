class_name SettlementGenerationSession
extends RefCounted

const RoadAgentScript := preload("res://scripts/systems/settlements/road_agent.gd")
const PlotAgentScript := preload("res://scripts/systems/settlements/plot_agent.gd")
const BuildingAgentScript := preload("res://scripts/systems/settlements/building_agent.gd")
const LandmarkAgentScript := preload("res://scripts/systems/settlements/landmark_agent.gd")
const InvalidConflictAgentScript := preload("res://scripts/systems/settlements/invalid_conflict_agent.gd")

var policy: SettlementPolicy
var context: SettlementContext
var feature_maps: FeatureMapStore
var blueprint: SettlementBlueprint
var resolver: ProposalResolver
var evaluator: SettlementEvaluator
var trace: GenerationTrace
var active_agents: Array[SettlementAgent] = []
var current_phase: String = ""
var committed_step: int = 0

var _rng := RandomNumberGenerator.new()
var _proposal_sequence: int = 0


func _init(p_policy: SettlementPolicy = null, p_context: SettlementContext = null) -> void:
	policy = p_policy if p_policy != null else SettlementPolicy.new()
	context = p_context if p_context != null else SettlementContext.new()
	context.ensure_defaults()
	feature_maps = FeatureMapStore.new()
	blueprint = SettlementBlueprint.new()
	resolver = ProposalResolver.new()
	evaluator = SettlementEvaluator.new()
	trace = GenerationTrace.new()


func run() -> Dictionary:
	_initialize_run()
	for phase in ["core", "road", "plot", "building", "landmark", "validation"]:
		current_phase = phase
		trace.record_phase(phase)
		for agent in active_agents:
			if not agent.is_active(self):
				continue
			var proposals := agent.propose(self)
			for proposal in proposals:
				resolver.process_proposal(proposal, self, agent)
	trace.record_event("session_finished", {
		"committed_step": committed_step,
		"proposal_count": trace.proposals.size(),
	})
	return get_result()


func randi_range(from_value: int, to_value: int, reason: String) -> int:
	var value := _rng.randi_range(from_value, to_value)
	trace.record_random_decision(current_phase, reason, value)
	return value


func next_proposal_id(agent_id: String) -> String:
	_proposal_sequence += 1
	return "%s_%03d" % [agent_id, _proposal_sequence]


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
			"current_phase": current_phase,
			"committed_step": committed_step,
			"proposal_sequence": _proposal_sequence,
			"result_signature": result_signature(),
		},
	}


func _initialize_run() -> void:
	_proposal_sequence = 0
	committed_step = 0
	current_phase = "initialize"
	_rng.seed = _resolve_seed()
	feature_maps.initialize(context)
	blueprint = SettlementBlueprint.new()
	trace = GenerationTrace.new()
	active_agents = [
		CoreSeedAgent.new(),
		RoadAgentScript.new(),
		PlotAgentScript.new(),
		BuildingAgentScript.new(),
		LandmarkAgentScript.new(),
		InvalidProposalAgent.new(),
		InvalidConflictAgentScript.new(),
	]
	trace.record_event("session_initialized", {
		"seed": _resolve_seed(),
		"agent_count": active_agents.size(),
	})


func _resolve_seed() -> int:
	if policy.seed_override >= 0:
		return policy.seed_override
	return context.world_seed
