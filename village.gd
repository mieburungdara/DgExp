extends Node2D

## Peta desa statis. Kontraknya sama dengan generator dungeon supaya player dan
## main.gd tidak perlu tahu bentuk internal peta: grid jalur, titik spawn, dan
## titik jatuh untuk warp masuk.

@export var grid_layer: TileMapLayer
@export var spawn_points: Node2D
@export var arrival_point: Marker2D

# Group didaftarkan di sini, bukan disimpan di file: PackedScene.pack() tidak
# menyimpan group milik node root scene, dan cara ini sama persis dengan
# IsaacGenerator yang juga mendaftar dirinya saat _ready.
func _ready() -> void:
    add_to_group("game_map")
    add_to_group("village_map")

func get_grid_layer() -> TileMapLayer:
    return grid_layer

func get_spawn_points() -> Node:
    return spawn_points

func get_arrival_point() -> Vector2:
    return arrival_point.global_position
