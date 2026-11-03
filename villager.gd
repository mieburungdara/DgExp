extends CharacterBody2D

## Warga desa: berjalan acak di sekitar titik asalnya. Bukan monster — tidak
## masuk group "monsters", tidak diserang, dan tidak dihitung batas spawn.
## Layer tabrakan 2: mereka tetap terhalang dinding tilemap, tapi tidak berdiri
## di jalur player (yang bermasker 1) sehingga pathfinding tidak bisa tersendat
## oleh badan NPC.

@export var texture_path: String = ""
@export var wander_radius: float = 48.0
@export var speed: float = 26.0

var _sprite: Sprite2D
var _home := Vector2.ZERO
var _dir := Vector2.ZERO
var _timer := 0.0
var _bob := 0.0


func _ready() -> void:
    collision_layer = 2
    collision_mask = 1

    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = 4.0
    shape.shape = circle
    add_child(shape)

    _sprite = Sprite2D.new()
    if texture_path != "":
        _sprite.texture = load(texture_path)
        _sprite.offset = Vector2(0, -_sprite.texture.get_height() * 0.5)
    add_child(_sprite)

    _home = global_position
    _timer = randf_range(0.2, 1.6)


func _physics_process(delta: float) -> void:
    # Tali kekang dievaluasi setiap fisika tick kalau sudah keluar radius:
    # memutuskan arah tiap 0,35 detik saja masih sempat menyeret bebek 61 px
    # dari rumahnya dengan radius 18, karena ia meluncur di sepanjang tepi air.
    if wander_radius > 0.0 and global_position.distance_to(_home) > wander_radius:
        _dir = _best_leash_direction()
        _timer = maxf(_timer, 0.8)
    else:
        _timer -= delta
        if _timer <= 0.0:
            _pick_direction()
            _timer = randf_range(1.2, 3.4)

    var before := global_position
    velocity = _dir * speed
    move_and_slide()

    # Tersempat di tembok: pilih arah baru segera. Tanpa ini warga yang sedang
    # "pulang" ke titik asal membentur pagar berkali-kali tanpa pernah ganti
    # arah, dan terlihat patung (terukur: farmer/hen/goat hanya bergeser 6-7 px
    # dalam 21 detik).
    if _dir != Vector2.ZERO and global_position.distance_to(before) < 0.2:
        _pick_direction(true)
        _timer = randf_range(0.8, 2.2)

    if _dir == Vector2.ZERO:
        _bob = 0.0
        _sprite.offset = _rest_offset()
        return
    _bob += delta * 9.0
    var step := 1.0 if fmod(floor(_bob), 2.0) < 1.0 else 0.0
    _sprite.offset = _rest_offset() + Vector2(0, -step)
    if _dir.x != 0:
        _sprite.flip_h = _dir.x < 0


func _rest_offset() -> Vector2:
    if _sprite.texture == null:
        return Vector2.ZERO
    return Vector2(0, -_sprite.texture.get_height() * 0.5)


func _pick_direction(forced: bool = false) -> void:
    if wander_radius <= 0.0:
        _dir = Vector2.ZERO
        return
    if not forced and global_position.distance_to(_home) > wander_radius:
        _dir = _best_leash_direction()
        return
    var a := randf_range(0.0, TAU)
    _dir = Vector2(cos(a), sin(a))


# Tali kekang: dari delapan arah, ambil yang jalurnya bebas dan paling mendekati
# rumah. Memilih "lurus ke rumah" saja tidak cukup — kalau jalur itu terhalang
# pagar, warga akan menabraknya terus dan tetap melayang keluar radius (terukur:
# ayam lepas sampai 71 px dari rumah dengan radius 20).
func _best_leash_direction() -> Vector2:
    var to_home := (_home - global_position).normalized()
    var best := Vector2.ZERO
    var best_score := -999.0
    for i in range(8):
        var cand := Vector2.from_angle(TAU * i / 8.0)
        if _blocked_toward(cand):
            continue
        var score := cand.dot(to_home)
        if score > best_score:
            best_score = score
            best = cand
    return best if best != Vector2.ZERO else to_home


func _blocked_toward(dir: Vector2) -> bool:
    var space := get_world_2d().direct_space_state
    var from := global_position + Vector2(0, -4)
    var to := from + dir * 14.0
    var query := PhysicsRayQueryParameters2D.create(from, to, 1)
    query.exclude = [get_rid()]
    return not space.intersect_ray(query).is_empty()
