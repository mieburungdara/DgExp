extends Area2D

## Pemicu toko di lapak pedagang. Sama seperti portal: hanya mendeteksi player
## (group "player") dan meminta shell membuka panelnya.

var _mark: Sprite2D


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

    # Penanda visual: tanpa ini lapak pedagang hanya petak biasa dan pemain
    # tidak tahu harus menginjak apa.
    var mark := Sprite2D.new()
    mark.texture = load("res://art/ui/stall.png")
    mark.scale = Vector2(1.4, 1.4)
    mark.position = Vector2(0, -34)
    add_child(mark)
    _mark = mark

    body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
    if not body.is_in_group("player"):
        return
    Game.open_shop()
