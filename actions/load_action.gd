class_name LoadAction
extends BaseAction

var transport: TransportUnit

func _init(p_actor: Unit, p_transport: TransportUnit) -> void:
	actor = p_actor
	transport = p_transport
	type = Type.LOAD
	team = p_actor.team

func to_dict() -> Dictionary:
	return {
		"actor_id": actor.unit_id,
		"transport_id": transport.unit_id,
	}
