class_name UnloadAction
extends BaseAction

var unload_tile: Vector2i
var move_path: Array[Vector2i] = []
var is_wrapped: bool = false

func _init(p_transport: TransportUnit, p_tile: Vector2i) -> void:
	actor = p_transport
	unload_tile = p_tile
	type = Type.UNLOAD
	team = p_transport.team

func to_dict() -> Dictionary:
	var path_x: Array = []
	var path_y: Array = []
	for p in move_path:
		path_x.append(p.x)
		path_y.append(p.y)
	return {
		"type_int": type,
		"actor_id": actor.unit_id,
		"tile_x": unload_tile.x,
		"tile_y": unload_tile.y,
		"path_x": path_x,
		"path_y": path_y,
		"is_wrapped": is_wrapped,
	}
