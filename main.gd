extends Node2D

## Shell permainan yang bertahan antar pergantian scene peta: player, UI, dan
## timer spawn. Peta (dungeon / desa) adalah scene yang ditukar lewat
## change_scene, jadi semua state yang harus selamat dari tukar scene disimpan
## di sini, per map_id.

const MAP_SCENES := {
    &"dungeon": "res://dungeon_5.tscn",
    &"village": "res://village.tscn",
}
const SEED_MONSTER_COUNT := 3

@export var slime_scene: PackedScene = preload("res://slime.tscn")
@export var min_spawn_distance: float = 250.0 # jarak minimum titik spawn dari player (px)
@export var monster_cap: int = 10 # batas monster per peta

@onready var player: CharacterBody2D = $Player
@onready var list_container: VBoxContainer = $CanvasLayer/MonsterList
@onready var spawn_timer: Timer = $SpawnTimer

var current_map: Node
var warp_lock := 0.0
var _saved_monsters: Dictionary = {}  # map_id -> Array[Dictionary{pos, hp}]
var _saved_positions: Dictionary = {} # map_id -> Vector2


func _ready() -> void:
    spawn_timer.timeout.connect(_on_spawn_timer_timeout)
    player.map_changed.connect(refresh_monster_buttons)


func _process(delta: float) -> void:
    if warp_lock > 0.0:
        warp_lock -= delta


# Dipanggil dari _ready() scene peta, sesaat setelah grid dan SpawnPoints-nya siap.
func on_map_ready(map: Node) -> void:
    current_map = map
    var id: StringName = map.call("get_map_id")
    var pos: Vector2 = _saved_positions.get(id, map.call("get_arrival_point"))
    player.enter_map(map, pos)
    _restore_monsters(id)
    refresh_monster_buttons()


func warp_to(id: StringName) -> void:
    if warp_lock > 0.0 or not MAP_SCENES.has(id) or not is_instance_valid(current_map):
        return
    var from: StringName = current_map.call("get_map_id")
    _saved_positions[from] = player.global_position
    _saved_monsters[from] = _snapshot_monsters()
    _drop_monsters()
    warp_lock = 0.8
    get_tree().change_scene_to_file(MAP_SCENES[id])


func _snapshot_monsters() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for m in get_tree().get_nodes_in_group("monsters"):
        out.append({"pos": (m as Node2D).global_position, "hp": m.get("hp")})
    return out


# Monster adalah anak shell, jadi tidak ikut terbuang saat scene peta berganti;
# dibuang di sini supaya peta yang ditinggalkan benar-benar tidak tersisa.
# queue_free tidak dipakai: ekornya berjalan setelah scene baru siap, jadi
# monster lama akan terhitung ulang sebagai monster peta baru.
func _drop_monsters() -> void:
    for m in get_tree().get_nodes_in_group("monsters"):
        m.free()


func _restore_monsters(id: StringName) -> void:
    var saved = _saved_monsters.get(id)
    if saved == null:
        for i in range(SEED_MONSTER_COUNT):
            _spawn_slime()
        return
    for data in saved:
        var mon = slime_scene.instantiate()
        add_child(mon)
        mon.global_position = data["pos"]
        mon.hp = data["hp"]
        mon.hp_bar.update_hp(data["hp"])


func _on_spawn_timer_timeout():
    if get_tree().get_nodes_in_group("monsters").size() < monster_cap:
        _spawn_slime()
    randomize_timer()

func _spawn_slime():
    # 1. Titik spawn disediakan peta yang sedang aktif
    if not is_instance_valid(current_map):
        return
    var holder = current_map.call("get_spawn_points")
    if holder == null:
        push_warning("Peta '%s' tidak punya SpawnPoints." % current_map.name)
        return
    var points = holder.get_children()
    if points.size() == 0:
        push_warning("SpawnPoints kosong, tidak ada tempat untuk spawn monster.")
        return

    # 2. Acak dari titik yang tidak terlalu dekat dengan player, supaya monster
    #    tidak muncul tepat di atas kepala karakter
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

    # 2. Ambil monster yang masih hidup. Hanya peta aktif yang punya monster di
    #    tree, jadi daftar ini otomatis sesuai peta tempat player berada.
    var all_monsters = get_tree().get_nodes_in_group("monsters")

    for m in all_monsters:
        if is_instance_valid(m) and not m.get("is_dead"):
            var btn = Button.new()
            btn.text = "Serang " + m.get("monster_name")
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
    if is_instance_valid(m) and not m.get("is_dead"):
        player.go_to_monster(m)
    else:
        # Jika monster sudah mati duluan, refresh daftar tombolnya
        refresh_monster_buttons()

func _on_monster_exiting(btn_to_remove):
    # Hapus tombol hanya jika tombolnya masih ada
    if is_instance_valid(btn_to_remove):
        btn_to_remove.queue_free()
