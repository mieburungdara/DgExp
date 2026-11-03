extends CharacterBody2D

signal map_changed

# --- STATISTIK PLAYER ---
@export var speed: float = 200.0
@export var hp: int = 100  # Dipastikan mulai dengan angka 100
@export var attack_damage: int = 10
@export var turn_lookahead: float = 12.0  # px titik lihat di sepanjang jalur; makin besar makin lebar lengkung belokan
@export var max_turn_deg_per_sec: float = 540.0  # berapa cepat karakter boleh ganti arah; membatasi sentakan di sudut tajam

# --- VARIABEL KONTROL ---
var target_monster = null
var is_attacking: bool = false
var _heading := Vector2.RIGHT
var _grid := GridPath.new()
var _path := PackedVector2Array()
var _path_idx := 0
var _planned_for := Vector2.INF
var _replan_in := 0.0
var _active_map: Node2D
var _clearance := Vector2(6, 6)
var _portal_lock := 0.0

# --- HUBUNGAN KE NODE ---
@onready var anim = $AnimatedSprite2D
@onready var hp_bar = $FloatingHealthBar
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready():
    hp_bar.setup(hp)  # Panggil fungsi setup saat mulai

    # Margin jalur diambil dari bentuk tabrakan itu sendiri (setengah ukuran +
    # offsetnya), jadi grid tidak bisa diam-diam berbeda dari badan karakter.
    _clearance = _collision.shape.get_rect().size * 0.5 + _collision.position.abs()

    var map := _map_at(global_position)
    if map == null:
        push_error("Player: tidak ada peta (group 'game_map') yang memuat posisi awal, pathfinding tidak aktif.")
        return
    _set_active_map(map)


# Peta yang rect ubinnya memuat titik ini; dipakai saat awal dan setelah warp.
func _map_at(pos: Vector2) -> Node2D:
    var first: Node2D = null
    for m in get_tree().get_nodes_in_group("game_map"):
        var map := m as Node2D
        if not map.has_method("get_grid_layer"):
            continue
        var layer := map.call("get_grid_layer") as TileMapLayer
        if layer == null:
            continue
        if first == null:
            first = map
        if _layer_rect(layer).grow(8.0).has_point(pos):
            return map
    return first


func _layer_rect(layer: TileMapLayer) -> Rect2:
    var used: Rect2i = layer.get_used_rect()
    var half := Vector2(layer.tile_set.tile_size) * 0.5
    var a := layer.to_global(layer.map_to_local(used.position)) - half
    var b := layer.to_global(layer.map_to_local(used.end)) - half
    return Rect2(a, b - a)


func get_active_map() -> Node2D:
    return _active_map


func can_reach(pos: Vector2) -> bool:
    return _grid.contains_world(pos)


func _set_active_map(map: Node2D) -> void:
    _active_map = map
    _grid.build(map.call("get_grid_layer"), _clearance)
    _path = PackedVector2Array()
    _path_idx = 0
    _planned_for = Vector2.INF
    _replan_in = 0.0
    map_changed.emit()


# Pindah peta: buang tujuan lama (monster itu ada di peta yang ditinggalkan),
# pasang posisi, lalu bangun grid peta baru. Kunci singkat mencegah portal tujuan
# langsung memicu warp balik pada frame yang sama.
func warp_to(map: Node2D, dest: Vector2) -> void:
    if _portal_lock > 0.0 or map == null or map == _active_map:
        return
    _portal_lock = 0.8
    target_monster = null
    velocity = Vector2.ZERO
    global_position = dest
    _set_active_map(map)


func _physics_process(delta):
    if _portal_lock > 0.0:
        _portal_lock -= delta

    if hp <= 0 or is_attacking:
        return

    if target_monster == null or not is_instance_valid(target_monster):
        play_animation("idle")
        velocity = Vector2.ZERO
        target_monster = null
        return

    var goal: Vector2 = target_monster.global_position

    # Jarak serang 20 pixel. Jika monster menjauh lebih dari ini, Player mengejar lagi.
    if global_position.distance_to(goal) <= 20.0:
        velocity = Vector2.ZERO
        start_attack_loop()
        return

    _replan_in -= delta
    if _needs_replan(goal):
        _path = _grid.find_path(global_position, goal)
        _path_idx = 0
        _planned_for = goal
        _replan_in = 0.3

    if _path.is_empty() or _path_idx >= _path.size():
        velocity = Vector2.ZERO
        play_animation("idle")
        return

    while _path_idx < _path.size() - 1 and global_position.distance_to(_path[_path_idx]) < 12.0:
        _path_idx += 1

    var direction := _limit_turn(global_position.direction_to(_lookahead_point()))
    velocity = direction * speed
    move_and_slide()

    play_animation("walk")
    if direction.x != 0:
        anim.flip_h = direction.x < 0


# Membatasi kecepatan ganti arah supaya sudut tajam dilewati sebagai lengkungan,
# bukan sentakan satu tick. Radius belok efektif = speed / laju_putur (radian).
func _limit_turn(desired: Vector2) -> Vector2:
    if desired == Vector2.ZERO:
        return Vector2.ZERO
    var step := deg_to_rad(max_turn_deg_per_sec * get_physics_process_delta_time())
    var ang := _heading.angle_to(desired)
    if absf(ang) <= step:
        _heading = desired
    else:
        _heading = _heading.rotated(signf(ang) * step)
    return _heading


# Pencarian jalur itu mahal (terukur ~25 ms rata-rata, ~75 ms terburuk pada peta
# 340x420 ubin), jadi tidak boleh tiap tick: hanya saat tujuan berpindah jauh,
# karakter menyimpang dari segmen berjalan, atau jalur habis.
func _needs_replan(goal: Vector2) -> bool:
    if _path.is_empty():
        return goal.distance_to(_planned_for) > 8.0
    if _replan_in > 0.0:
        return false
    if goal.distance_to(_planned_for) > 32.0:
        return true
    return _distance_to_current_leg() > 24.0


func _distance_to_current_leg() -> float:
    var a: Vector2 = _path[clampi(_path_idx, 0, _path.size() - 1)]
    var b: Vector2 = _path[min(_path_idx + 1, _path.size() - 1)]
    var seg: Vector2 = b - a
    var len2 := seg.length_squared()
    if len2 <= 0.001:
        return global_position.distance_to(a)
    var t := clampf((global_position - a).dot(seg) / len2, 0.0, 1.0)
    return global_position.distance_to(a + seg * t)


# Titik sejauh turn_lookahead px di depan, diukur sepanjang jalur. Karena titik ini
# sudah "melihat" ke segmen sesudah sudut, belokan berubah menjadi lengkung alih-alih
# patahan tepat di titik sudut jalur.
func _lookahead_point() -> Vector2:
    var cursor := global_position
    var remaining := turn_lookahead
    for i in range(_path_idx, _path.size()):
        var seg: Vector2 = _path[i] - cursor
        var seg_len := seg.length()
        if seg_len <= 0.001:
            continue
        if seg_len >= remaining:
            return cursor + seg * (remaining / seg_len)
        remaining -= seg_len
        cursor = _path[i]
    return cursor


# --- FUNGSI PERINTAH ---
func go_to_monster(monster_node):
    # Monster di peta lain tidak bisa dijangkau jalurnya; menolak di sini lebih
    # jujur daripada berdiri diam tanpa sebab.
    if is_instance_valid(monster_node) and _grid.contains_world(monster_node.global_position):
        target_monster = monster_node
        is_attacking = false
        _path = PackedVector2Array()
        _planned_for = Vector2.INF
        _replan_in = 0.0


# --- LOOP SERANGAN OTOMATIS ---
func start_attack_loop():
    if is_attacking or target_monster == null:
        return

    is_attacking = true
    velocity = Vector2.ZERO

    # TERUS MENYERANG selama monster masih ada dan HP monster > 0
    while is_instance_valid(target_monster) and target_monster.hp > 0:
        # Hadapkan ke monster
        anim.flip_h = target_monster.global_position.x < global_position.x

        play_animation("attack")

        # Pemicu serangan balik monster
        if target_monster.has_method("be_attacked"):
            target_monster.be_attacked(self)

        # Tunggu animasi selesai sebelum hitung damage
        await anim.animation_finished

        # Berikan damage ke monster
        if is_instance_valid(target_monster):
            target_monster.take_damage(attack_damage)

        # Jeda sebentar agar tidak terlalu kaku
        await get_tree().create_timer(0.2).timeout

        # Jika player mati di tengah pertarungan, hentikan loop
        if hp <= 0:
            break

    # Selesai bertarung (monster mati atau player kalah)
    is_attacking = false
    target_monster = null
    if hp > 0:
        play_animation("idle")


# --- FUNGSI TERKENA DAMAGE ---
func take_damage(amount):
    if hp <= 0:
        return

    hp -= amount
    if hp_bar:  # Pastikan variabel hp_bar terhubung
        hp_bar.update_hp(hp)
    print("HP Player: ", hp)

    if hp <= 0:
        die()
    else:
        # Mainkan animasi hurt jika tidak sedang menyerang
        if not is_attacking:
            play_animation("hurt")


func die():
    play_animation("death")
    set_physics_process(false)
    print("Game Over!")


func play_animation(anim_name: String):
    if anim and anim.sprite_frames.has_animation(anim_name):
        anim.play(anim_name)
