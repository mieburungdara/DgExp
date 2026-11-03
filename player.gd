extends CharacterBody2D

# --- STATISTIK PLAYER ---
@export var speed: float = 200.0
@export var hp: int = 100  # Dipastikan mulai dengan angka 100
@export var attack_damage: int = 10
@export var turn_lookahead: float = 12.0  # px titik lihat di sepanjang jalur; makin besar makin lebar lengkung belokan
@export var max_turn_deg_per_sec: float = 540.0  # berapa cepat karakter boleh ganti arah; membatasi sentakan di sudut tajam

# --- VARIABEL KONTROL ---
var target_monster = null
var is_attacking: bool = false
var _replan_nudge := 0.0
var _heading := Vector2.RIGHT

# --- HUBUNGAN KE NODE ---
@onready var nav_agent = $NavigationAgent2D
@onready var anim = $AnimatedSprite2D
@onready var hp_bar = $FloatingHealthBar


func _ready():
    hp_bar.setup(hp)  # Panggil fungsi setup saat mulai


func _physics_process(_delta):
    if hp <= 0 or is_attacking:
        return

    if target_monster == null or not is_instance_valid(target_monster):
        play_animation("idle")
        velocity = Vector2.ZERO
        target_monster = null
        return

    # Target harus titik yang ada di navmesh. NavigationAgent hanya menghitung ulang
    # jalur saat nilainya berubah, jadi kalau jalur selesai padahal monster masih jauh
    # (misal karakter tersorong keluar jalur), geser target sedikit untuk memicu replan.
    var goal := _navmesh_target(target_monster.global_position)
    if nav_agent.is_navigation_finished() and global_position.distance_to(goal) > 40.0:
        _replan_nudge = 0.0 if _replan_nudge > 0.0 else 0.5
    nav_agent.target_position = goal + Vector2(_replan_nudge, 0.0)

    var distance_to_monster = global_position.distance_to(target_monster.global_position)

    # Jarak serang (50 pixel). Jika monster menjauh lebih dari ini, Player akan mengejar lagi.
    if distance_to_monster <= 20.0:
        velocity = Vector2.ZERO
        start_attack_loop()
        return

    # Logika berjalan menuju posisi terbaru monster
    if not nav_agent.is_navigation_finished():
        var direction = _limit_turn(global_position.direction_to(_lookahead_point()))

        velocity = direction * speed
        move_and_slide()

        play_animation("walk")
        if direction.x != 0:
            anim.flip_h = direction.x < 0
    else:
        velocity = Vector2.ZERO
        play_animation("idle")


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


# Titik sejauh turn_lookahead px di depan, diukur sepanjang jalur, TAPI hanya selama
# garis lurus dari karakter ke titik itu benar-benar bebas dinding. Tanpa pemeriksaan
# ini, memotong sudut justru mengarahkan karakter ke sisi dinding dan ia tertahan di situ.
# Titik sejauh turn_lookahead px di depan, diukur sepanjang jalur. Karena titik ini
# sudah "melihat" ke segmen sesudah sudut, belokan berubah menjadi lengkung alih-alih
# patahan tepat di titik sudut jalur.
func _lookahead_point() -> Vector2:
    var path: PackedVector2Array = nav_agent.get_current_navigation_path()
    var idx: int = nav_agent.get_current_navigation_path_index()
    if path.is_empty() or idx >= path.size():
        return nav_agent.target_position
    var cursor := global_position
    var remaining := turn_lookahead
    for i in range(idx, path.size()):
        var seg: Vector2 = path[i] - cursor
        var seg_len := seg.length()
        if seg_len <= 0.001:
            continue
        if seg_len >= remaining:
            return cursor + seg * (remaining / seg_len)
        remaining -= seg_len
        cursor = path[i]
    return cursor


func _navmesh_target(point: Vector2) -> Vector2:
    return NavigationServer2D.map_get_closest_point(get_world_2d().navigation_map, point)


# --- FUNGSI PERINTAH ---
func go_to_monster(monster_node):
    if is_instance_valid(monster_node):
        target_monster = monster_node
        is_attacking = false


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
