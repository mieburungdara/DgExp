extends Node2D

## Peta desa statis. Kontraknya sama dengan generator dungeon supaya shell (Game)
## memperlakukan semua peta dengan satu cara: id, grid jalur, titik spawn, dan
## titik jatuh untuk yang baru masuk.

const MAP_ID := &"village"

@export var grid_layer: TileMapLayer
@export var spawn_points: Node2D
@export var arrival_point: Marker2D

func _ready() -> void:
    Game.on_map_ready(self)

func get_map_id() -> StringName:
    return MAP_ID

func get_map_label() -> String:
    return "Desa"

func get_map_icon() -> String:
    return "map_village"

func get_grid_layer() -> TileMapLayer:
    return grid_layer

func get_spawn_points() -> Node:
    return spawn_points

# Zona aman: tidak ada monster yang muncul di desa.
func get_monsters_allowed() -> bool:
    return false

func get_arrival_point() -> Vector2:
    return arrival_point.global_position
