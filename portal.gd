extends Area2D

## Gerbang antar peta. Menyentuhnya meminta shell (Game) menukar scene peta ke
## map_id tujuan. Yang dikirim hanya id, bukan referensi node: scene tujuan belum
## ada di tree saat portal dipanggil, dan peta yang lama akan dibuang.

@export var target_map_id: StringName = &"village"
@export var label: String = "Portal"

func _ready() -> void:
    collision_layer = 0
    collision_mask = 1
    monitorable = false

    var shape := CollisionShape2D.new()
    shape.name = "CollisionShape2D"
    var rect := RectangleShape2D.new()
    rect.size = Vector2(18, 14)
    shape.shape = rect
    shape.position = Vector2(0, 4)
    add_child(shape)

    var sprite := Sprite2D.new()
    sprite.name = "Sprite"
    sprite.texture = load("res://portal.png")
    sprite.position = Vector2(0, -6)
    add_child(sprite)

    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
    if not body.is_in_group("player"):
        return
    # Ditunda: menukar scene tidak boleh dilakukan dari dalam callback fisika,
    # karena node-node yang sedang dipakai tabrakan ikut dibuang di tengah loop.
    Game.warp_to.call_deferred(target_map_id)


## True kalau titik ini berada di dalam area gerbang. Dipakai shell supaya
## pemain tidak dipulangkan ke posisi yang sedang berdiri di atas gerbang:
## dari sana gerbangnya tidak bisa dipakai lagi sampai dia keluar dan masuk
## (body_entered hanya memicu saat MASUK area).
func covers(point: Vector2) -> bool:
    var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
    if shape == null or shape.shape == null:
        return false
    var size := shape.shape.get_rect().size
    var origin := shape.global_position - size * 0.5
    return Rect2(origin, size).has_point(point)
