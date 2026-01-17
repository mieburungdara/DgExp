extends CharacterBody2D

# --- STATISTIK SLIME ---
# Menambahkan : int dan : float memastikan variabel tidak akan pernah 'Nil'
@export var hp: int = 30
@export var speed: float = 50.0 
@export var monster_name: String = "Slime Hijau"

@onready var anim = $AnimatedSprite2D
@onready var hp_bar = $FloatingHealthBar

var is_dead: bool = false
var is_hurting: bool = false
var is_attacking: bool = false
var can_be_hurt: bool = true
var walk_timer: float = 0.0
var move_direction: Vector2 = Vector2.ZERO

func _ready():
    # Memastikan monster masuk dalam group saat mulai
    add_to_group("monsters")
    hp_bar.setup(hp) # Panggil fungsi setup saat mulai
    play_animation("idle")

func _physics_process(delta):
    # Jika mati, sedang kaget (hurt), atau SEDANG MENYERANG, jangan ganti animasi
    if is_dead or is_hurting or is_attacking:
        velocity = Vector2.ZERO
        return

    walk_timer -= delta
    if walk_timer <= 0:
        pick_new_direction()

    velocity = move_direction * speed
    
    if velocity.length() > 0:
        play_animation("walk")
        if move_direction.x != 0:
            anim.flip_h = move_direction.x < 0
    else:
        play_animation("idle")
    
    move_and_slide()

func pick_new_direction():
    var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.ZERO]
    move_direction = dirs.pick_random()
    walk_timer = randf_range(1.5, 4.0) # Slime lebih santai geraknya

# --- FUNGSI PERTARUNGAN ---
func be_attacked(player_node):
    # Jika sedang sakit (hurt) atau mati, jangan menyerang balik dulu
    if is_dead or is_hurting or is_attacking: return
    
    is_attacking = true 
    move_direction = Vector2.ZERO
    
    # Menghadap ke player saat menyerang balik
    if is_instance_valid(player_node):
        anim.flip_h = player_node.global_position.x < global_position.x
    
    play_animation("attack")
    
    # Tunggu timer serangan
    await get_tree().create_timer(0.1).timeout 
    
    # Cek lagi: Jika saat menunggu timer ternyata Slime kena pukul (is_hurting), batalkan damage
    if is_instance_valid(player_node) and not is_dead and not is_hurting:
        player_node.take_damage(5)
    
    is_attacking = false

func take_damage(amount):
    if is_dead: return
    
    hp -= amount
    if hp_bar: # Pastikan variabel hp_bar terhubung
        hp_bar.update_hp(hp)
    print(monster_name, " HP: ", hp)
    
    if hp <= 0:
        die()
        return

    # SUPER ARMOR: Jika sedang menyerang, terima damage tapi jangan putus animasi
    if is_attacking:
        return

    # VISUAL COOLDOWN: Jika baru saja hurt, jangan mainkan animasi hurt lagi (tapi damage tetap masuk di atas)
    if not can_be_hurt:
        return

    # Efek Hurt dengan jeda
    can_be_hurt = false
    is_hurting = true
    
    play_animation("hurt")
    
    # Tunggu animasi hurt selesai
    await anim.animation_finished
    
    is_hurting = false
    play_animation("idle")
    
    # Beri jeda 0.5 detik sebelum animasi hurt bisa dimainkan lagi
    await get_tree().create_timer(0.5).timeout
    can_be_hurt = true
        
        
func die():
    is_dead = true
    remove_from_group("monsters")
    move_direction = Vector2.ZERO
    velocity = Vector2.ZERO
    
    play_animation("death")
    
    # Matikan tabrakan agar tidak menghalangi jalan Player
    if has_node("CollisionShape2D"):
        $CollisionShape2D.set_deferred("disabled", true)
        
    await anim.animation_finished
    queue_free()

# Fungsi pembantu agar tidak error jika salah satu animasi belum dibuat
func play_animation(anim_name: String):
    if anim and anim.sprite_frames.has_animation(anim_name):
        anim.play(anim_name)
