class_name UnloadAction
extends BaseAction

var unload_tile: Vector2i

func _init(p_transport: TransportUnit, p_tile: Vector2i) -> void:
	actor = p_transport
	unload_tile = p_tile
	type = Type.UNLOAD
	team = p_transport.team

func to_dict() -> Dictionary:
	return {
		"actor_id": actor.unit_id,
		"tile_x": unload_tile.x,
		"tile_y": unload_tile.y,
	}
