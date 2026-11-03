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
const KILL_REWARD := 10 # koin per monster yang mati

@export var slime_scene: PackedScene = preload("res://slime.tscn")
@export var min_spawn_distance: float = 250.0 # jarak minimum titik spawn dari player (px)
@export var monster_cap: int = 10 # batas monster per peta

@onready var player: CharacterBody2D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var spawn_timer: Timer = $SpawnTimer
@onready var shop: CanvasLayer = $Shop

signal coins_changed(new_coins: int)

var current_map: Node
var warp_lock := 0.0
var coins := 0 # tidak ikut terbuang saat scene peta berganti
var kills := 0
var _saved_monsters: Dictionary = {}  # map_id -> Array[Dictionary{pos, hp}]
var _saved_positions: Dictionary = {} # map_id -> Vector2
var _grids: Dictionary = {}           # map_id -> GridPath yang sudah dipindai


func _ready() -> void:
    spawn_timer.timeout.connect(_on_spawn_timer_timeout)
    player.map_changed.connect(_on_targets_changed)
    player.hp_changed.connect(_on_player_hp_changed)
    hud.grind_pressed.connect(_on_grind_pressed)
    coins_changed.connect(_on_coins_changed)
    _on_coins_changed(coins)
    hud.set_kills(kills)
    _on_player_hp_changed(player.hp, player.max_hp)


func add_coins(amount: int) -> void:
    coins += amount
    coins_changed.emit(coins)


func spend_coins(amount: int) -> void:
    add_coins(-amount)


func _on_coins_changed(value: int) -> void:
    hud.set_coins(value)


func _on_player_hp_changed(value: int, maximum: int) -> void:
    hud.set_hp(value, maximum)


func open_shop() -> void:
    shop.open()


func _process(delta: float) -> void:
    if warp_lock > 0.0:
        warp_lock -= delta


# Dipanggil dari _ready() scene peta, sesaat setelah grid dan SpawnPoints-nya siap.
func on_map_ready(map: Node) -> void:
    current_map = map
    hud.set_map(String(map.call("get_map_label")), String(map.call("get_map_icon")))
    var id: StringName = map.call("get_map_id")
    var pos: Vector2 = _saved_positions.get(id, map.call("get_arrival_point"))
    # Posisi terakhir hampir selalu "tepat di atas gerbang yang baru dipakai".
    # Kalau dipulangkan ke sana, gerbangnya jadi tidak bisa dipakai lagi, jadi
    # pakai titik datang peta itu.
    if _lands_on_gate(map, pos):
        pos = map.call("get_arrival_point")
    player.enter_map(map, pos, _grids.get(id))
    _grids[id] = player.get_grid()
    _restore_monsters(id)
    _on_targets_changed()
    # Peta lama sudah dibuang, jadi panel toko tidak boleh tertinggal terbuka.
    shop.close_panel()


func _lands_on_gate(map: Node, pos: Vector2) -> bool:
    for c in map.get_children():
        if c.has_method("covers") and c.call("covers", pos):
            return true
    return false


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
    # Peta bisa menandai dirinya zona aman (desa); seed dan timer sama-sama lewat
    # sini, jadi satu pemeriksaan cukup.
    if not current_map.call("get_monsters_allowed"):
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

    _on_targets_changed()

func randomize_timer():
    # Mengatur waktu tunggu berikutnya antara 2 sampai 7 detik
    spawn_timer.wait_time = randf_range(2.0, 7.0)
    spawn_timer.start()

func monsters_here() -> int:
    # Hanya peta aktif yang punya monster di tree, karena scene peta lama ikut
    # dibuang saat warp.
    var n := 0
    for m in get_tree().get_nodes_in_group("monsters"):
        if is_instance_valid(m) and not m.get("is_dead"):
            n += 1
    return n


func _on_targets_changed() -> void:
    for m in get_tree().get_nodes_in_group("monsters"):
        if is_instance_valid(m) and not m.get("is_dead"):
            _watch(m)


## GRIND: cari monster terdekat yang benar-benar bisa dijangkau di peta ini,
## lalu serang. Yang di luar grid peta (mis. monster dungeon saat player di
## desa) tidak dihitung, jadi tombol tidak pernah "berhasil" tanpa efek.
func _on_grind_pressed() -> void:
    _on_targets_changed()
    var best: Node = null
    var best_dist := INF
    for m in get_tree().get_nodes_in_group("monsters"):
        if not is_instance_valid(m) or m.get("is_dead"):
            continue
        var mp := m as Node2D
        if not player.can_reach(mp.global_position):
            continue
        var d: float = player.global_position.distance_to(mp.global_position)
        if d < best_dist:
            best_dist = d
            best = mp
    if best == null:
        if monsters_here() > 0:
            hud.flash("Semua monster di peta ini tidak bisa dijangkau.")
        else:
            hud.flash("Belum ada monster di peta ini.")
        return
    player.go_to_monster(best)
    hud.flash("Mencari sasaran terdekat... %.0f px" % best_dist, 1.2)


# Tanda "sudah dipantau" ditempel di monster itu sendiri, bukan di kamus
# milik shell. Instance ID Godot dipakai ulang setelah node dibuang, dan
# dictionary yang keyed by id bisa lupa menghapusnya — hasilnya connect kedua
# atas (method + bind) yang sama ditolak Godot.
func _watch(monster: Node) -> void:
    if monster.has_meta("digaji"):
        return
    monster.set_meta("digaji", true)
    monster.tree_exiting.connect(_on_monster_exiting.bind(monster))


func _on_monster_exiting(monster: Node) -> void:
    # Bayaran hanya untuk monster yang benar-benar mati. Monster yang dibuang
    # saat pindah peta masih hidup (hp > 0) dan tidak boleh menghasilkan koin.
    if is_instance_valid(monster) and monster.get("hp") <= 0:
        kills += 1
        hud.set_kills(kills)
        add_coins(KILL_REWARD)
    _on_targets_changed()
