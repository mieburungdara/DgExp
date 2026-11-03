extends Area2D

## Gerbang antar peta. Menyentuhnya memindahkan Player ke container peta tujuan.
## Peta tujuan dicari lewat group, jadi portal yang disimpan di dalam village.tscn
## tidak perlu tahu jalur node scene lain (dungeon dibangun runtime).

@export var target_map_group: String = ""
@export var label: String = "Portal"

func _ready() -> void:
    collision_layer = 0
    collision_mask = 1
    monitorable = false

    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = Vector2(18, 14)
    shape.shape = rect
    shape.position = Vector2(0, 4)
    add_child(shape)

    var sprite := Sprite2D.new()
    sprite.texture = load("res://portal.png")
    sprite.position = Vector2(0, -6)
    add_child(sprite)

    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
    if not body.has_method("warp_to"):
        return
    var target := get_tree().get_first_node_in_group(target_map_group)
    if target == null or not target.has_method("get_arrival_point"):
        push_warning("Portal '%s': group peta tujuan '%s' tidak punya get_arrival_point()." % [label, target_map_group])
        return
    body.warp_to(target, target.get_arrival_point())
