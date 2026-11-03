extends Node2D

@onready var player = $Player 
# Pastikan path ini benar sesuai susunan di panel Scene kamu
@onready var list_container = $CanvasLayer/MonsterList 

@export var slime_scene: PackedScene = preload("res://slime.tscn")
@export var min_spawn_distance: float = 250.0 # jarak minimum titik spawn dari player (px)

@onready var spawn_timer = $SpawnTimer

func _ready():
    # Hubungkan sinyal timeout dari timer ke fungsi spawn
    spawn_timer.timeout.connect(_on_spawn_timer_timeout)
    # Daftar tombol hanya berisi monster di peta yang sedang dipakai
    player.map_changed.connect(refresh_monster_buttons)
    # Mulai spawn pertama
    randomize_timer()
    
func _on_spawn_timer_timeout():
    # Batas 10 monster berlaku per peta, bukan global: kalau dihitung global,
    # desa akan tetap kosong selama dungeon sudah penuh.
    if _monsters_here() < 10:
        spawn_slime()
    
    randomize_timer()

func _monsters_here() -> int:
    var n := 0
    for m in get_tree().get_nodes_in_group("monsters"):
        if player.can_reach(m.global_position):
            n += 1
    return n

func spawn_slime():
    # 1. Titik spawn disediakan peta tempat player sedang berada
    var map = player.get_active_map()
    if map == null:
        push_warning("Tidak ada peta aktif, monster tidak bisa di-spawn.")
        return
    var holder = map.call("get_spawn_points")
    if holder == null:
        push_warning("Peta '%s' tidak punya SpawnPoints." % map.name)
        return
    var points = holder.get_children()
    if points.size() == 0:
        push_warning("SpawnPoints kosong, tidak ada tempat untuk spawn monster.")
        return

    # 2. Ambil yang paling acak tapi tidak terlalu dekat dengan player, supaya
    #    monster tidak muncul tepat di atas kepala karakter
    var candidates = []
    for p in points:
        if player.global_position.distance_to(p.global_position) >= min_spawn_distance:
            candidates.append(p)
    if candidates.is_empty():
        candidates = points
    var chosen = candidates.pick_random()

    # 3. Masuk tree dulu, baru pasang posisi global
    var new_slime = slime_scene.instantiate()
    add_child(new_slime)
    new_slime.global_position = chosen.global_position

    # Update tombol agar monster baru langsung terdaftar
    refresh_monster_buttons()

func randomize_timer():
    # Mengatur waktu tunggu berikutnya antara 2 sampai 7 detik
    spawn_timer.wait_time = randf_range(2.0, 7.0)
    spawn_timer.start()
    
func _on_btn_grind_pressed():
    refresh_monster_buttons()

func refresh_monster_buttons():
    # 1. Bersihkan daftar tombol lama
    for child in list_container.get_children():
        child.queue_free()

    # 2. Ambil monster yang masih hidup
    var all_monsters = get_tree().get_nodes_in_group("monsters")
    
    for m in all_monsters:
        if is_instance_valid(m) and not m.get("is_dead") and player.can_reach(m.global_position):
            var btn = Button.new()
            btn.text = "Serang " + m.monster_name
            btn.custom_minimum_size = Vector2(200, 60)
            list_container.add_child(btn)
            
            # PERBAIKAN: Gunakan .bind(m) daripada lambda func():
            # Ini lebih aman karena bind() menangani referensi dengan lebih baik
            btn.pressed.connect(_on_monster_button_pressed.bind(m))
            
            # OTOMATIS: Hapus tombol jika monster hilang dari map.
            # Daftar ini dibangun ulang tiap spawn, jadi koneksi percobaan sebelumnya
            # dilepas dulu — kalau tidak, Godot menolak connect yang sama dan ERROR.
            for conn in m.tree_exiting.get_connections():
                m.tree_exiting.disconnect(conn.callable)
            m.tree_exiting.connect(_on_monster_exiting.bind(btn))

# Tambahkan dua fungsi pembantu ini di bawah refresh_monster_buttons:

func _on_monster_button_pressed(m):
    # Cek validitas monster tepat saat tombol ditekan
    if is_instance_valid(m) and not m.is_dead:
        player.go_to_monster(m)
    else:
        # Jika monster sudah mati duluan, refresh daftar tombolnya
        refresh_monster_buttons()

func _on_monster_exiting(btn_to_remove):
    # Hapus tombol hanya jika tombolnya masih ada
    if is_instance_valid(btn_to_remove):
        btn_to_remove.queue_free()
