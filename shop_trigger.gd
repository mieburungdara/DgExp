extends Area2D

## Pemicu toko di lapak pedagang. Sama seperti portal: hanya mendeteksi player
## (group "player") dan meminta shell membuka panelnya.

func _ready() -> void:
    collision_layer = 0
    collision_mask = 1
    monitorable = false

    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = Vector2(30, 26)
    shape.shape = rect
    shape.position = Vector2(0, -6)
    add_child(shape)

    body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
    if not body.is_in_group("player"):
        return
    Game.open_shop()
