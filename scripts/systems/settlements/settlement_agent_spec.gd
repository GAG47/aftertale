class_name SettlementAgentSpec
extends RefCounted

var activation_step: int = 0
var activation_interval: int = 1
var max_commits: int = 1


static func create(p_activation_step: int, p_activation_interval: int, p_max_commits: int):
	var spec := SettlementAgentSpec.new()
	spec.activation_step = p_activation_step
	spec.activation_interval = max(1, p_activation_interval)
	spec.max_commits = max(0, p_max_commits)
	return spec
