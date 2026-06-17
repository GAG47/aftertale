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
var agent_weight_summary: Dictionary = {}

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
			"agent_weight_summary": agent_weight_summary.duplicate(true),
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
	agent_weight_summary.clear()
	demand_ledger.reset(policy)
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
	_apply_policy_to_agents()
	trace.record_event("session_initialized", {
		"seed": _resolve_seed(),
		"agent_count": active_agents.size(),
		"max_blueprint_steps": max_blueprint_steps,
		"policy_id": policy.policy_id,
		"road_style": policy.road_style,
	})


func _resolve_seed() -> int:
	if policy.seed_override >= 0:
		return policy.seed_override
	return context.world_seed


func agent_weight(agent_id: String, family: String = "") -> float:
	var overrides := policy.agent_weight_overrides
	if overrides.has(agent_id):
		return maxf(0.0, float(overrides.get(agent_id, 1.0)))
	if not family.is_empty() and overrides.has(family):
		return maxf(0.0, float(overrides.get(family, 1.0)))
	return 1.0


func plot_use_weight(use: String) -> float:
	return maxf(0.0, float(policy.plot_use_weight_overrides.get(use, 1.0)))


func demand_weight(use: String) -> float:
	return maxf(0.0, float(policy.demand_weight_overrides.get(use, 1.0)))


func desired_plot_count() -> int:
	var map_area := float(context.map_size.x * context.map_size.y)
	var area_factor := clampf(map_area / 280.0, 1.0, 4.0)
	var density_factor := clampf(policy.density / 0.45, 0.65, 1.65)
	var weighted_need := 0.0
	var desired: Dictionary = demand_ledger.to_dictionary().get("desired_counts", {}) as Dictionary
	for value in desired.values():
		weighted_need += float(value)
	return clampi(int(round(maxf(6.0, weighted_need + area_factor * density_factor))), 5, 18)


func building_fill_ratio() -> float:
	return clampf(0.30 + policy.density * 0.65, 0.35, 0.82)


func asset_family_for_use(use: String) -> String:
	var rules: Dictionary = policy.gameplay_hook_rules.get("asset_family_by_use", {}) as Dictionary
	if rules.has(use):
		return str(rules.get(use, ""))
	if not policy.asset_family_preferences.is_empty():
		return policy.asset_family_preferences[0]
	return "common"


func building_type_for_use(use: String) -> String:
	var rules: Dictionary = policy.gameplay_hook_rules.get("building_type_by_use", {}) as Dictionary
	if rules.has(use):
		return str(rules.get(use, use))
	match use:
		"commercial":
			return "shop"
		"production":
			return "workshop"
		_:
			return "house"


func interior_template_for_building(building_type: String, use: String) -> String:
	var rules: Dictionary = policy.gameplay_hook_rules.get("interior_template_by_type", {}) as Dictionary
	if rules.has(building_type):
		return str(rules.get(building_type, ""))
	match use:
		"residential":
			return "basic_house_interior"
		"commercial":
			return "basic_shop_interior"
		"production":
			return "basic_workshop_interior"
		_:
			return ""


func hook_rule(key: String, default_value: Variant = null) -> Variant:
	return policy.gameplay_hook_rules.get(key, default_value)


func _apply_policy_to_agents() -> void:
	for agent in active_agents:
		var family := _agent_family(agent.agent_id)
		var weight := agent_weight(agent.agent_id, family)
		var original_max := agent.spec.max_commits
		if weight <= 0.0:
			agent.spec.max_commits = 0
		elif agent.agent_id.begins_with("invalid_"):
			agent.spec.max_commits = original_max
		else:
			agent.spec.max_commits = max(1, int(round(float(original_max) * weight)))
			if family == "plot" or family == "footprint":
				agent.spec.max_commits = max(1, int(round(float(agent.spec.max_commits) * clampf(policy.density / 0.45, 0.65, 1.55))))
			if weight >= 1.4 and agent.spec.activation_interval > 1:
				agent.spec.activation_interval = max(1, agent.spec.activation_interval - 1)
			elif weight < 0.8:
				agent.spec.activation_interval += 1
		agent_weight_summary[agent.agent_id] = {
			"family": family,
			"weight": weight,
			"activation_step": agent.spec.activation_step,
			"activation_interval": agent.spec.activation_interval,
			"max_commits": agent.spec.max_commits,
		}


func _agent_family(agent_id: String) -> String:
	if agent_id.begins_with("road_"):
		return "road"
	if agent_id.begins_with("generic_plot"):
		return "plot"
	if agent_id.begins_with("plot_differentiation"):
		return "differentiation"
	if agent_id.begins_with("building_footprint"):
		return "footprint"
	if agent_id.begins_with("core"):
		return "core"
	return agent_id
