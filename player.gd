extends CharacterBody2D

# --- STATISTIK PLAYER ---
@export var speed: float = 200.0
@export var hp: int = 100  # Dipastikan mulai dengan angka 100
@export var attack_damage: int = 10

# --- VARIABEL KONTROL ---
var target_monster = null
var is_attacking: bool = false
var _replan_nudge := 0.0

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
        var next_path_pos = nav_agent.get_next_path_position()
        var direction = (next_path_pos - global_position).normalized()

        velocity = direction * speed
        move_and_slide()

        play_animation("walk")
        if direction.x != 0:
            anim.flip_h = direction.x < 0
    else:
        velocity = Vector2.ZERO
        play_animation("idle")


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
