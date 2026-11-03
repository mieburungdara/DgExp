extends SceneTree

# Pembangun sekali-jalan untuk peta desa: menghasilkan village_tileset.tres dan
# village.tscn dari layout di bawah. Layoutnya deterministik (seed tetap) supaya
# yang tersimpan di git sama dengan yang diverifikasi.

const W := 44
const H := 30

const GRASS := 0
const FLOWER := 1
const DIRT := 2
const COBBLE := 3
const WALL := 4
const WALL_PLASTER := 5
const ROOF := 6
const RIDGE := 7
const DOOR := 8
const WINDOW := 9
const TREE := 10
const BUSH := 11
const WELL := 12
const FENCE := 13
const ROCK := 14
const WATER_EDGE := 15
const WATER := 16

const LEGEND := [".", "*", "d", "c", "W", "P", "R", "p", "D", "w", "T", "b", "#", "f", "o", "~", "X"]

var _g: Array[int] = []
var _rng := RandomNumberGenerator.new()

var portal_cell := Vector2i(19, 16)
var arrival_cell := Vector2i(20, 16)
var well_cell := Vector2i(23, 16)

func _atlas(idx: int) -> Vector2i:
    return Vector2i(idx % 4, int(idx / 4))

func _at(x: int, y: int) -> int:
    return _g[y * W + x]

func _is_walkable(idx: int) -> bool:
    return idx <= COBBLE

func _initialize() -> void:
    _rng.seed = 20261104
    # Array.shuffle() memakai RNG global, jadi ikut dipatok supaya titik spawn
    # yang tersimpan di file selalu sama dengan yang diverifikasi.
    seed(20261104)
    _g.resize(W * H)
    _g.fill(GRASS)
    paint()
    dump()

    var ts := load("res://village_tileset.tres") as TileSet
    if ts == null or ts.get_source_count() == 0:
        push_error("village_tileset.tres kosong/gagal dimuat, berhenti.")
        quit(1)
        return
    var scene := build_scene(ts)
    print("simpan scene: ", ResourceSaver.save(scene, "res://village.tscn"), " (0 = OK)")
    print("ubin layak di desa: ", count_walkable(), " dari ", W * H)
    quit()

func paint() -> void:
    # Dasar: rumput dengan sedikit bunga.
    for y in range(H):
        for x in range(W):
            _g[y * W + x] = FLOWER if _rng.randf() < 0.16 else GRASS

    # Hutan pembatas dua ubin tebal: karakter tidak bisa keluar peta.
    for y in range(H):
        for x in range(W):
            if x < 2 or y < 2 or x >= W - 2 or y >= H - 2:
                _g[y * W + x] = TREE

    # Kolam di pojok kanan atas; baris teratas memakai ubin bertepi pasir.
    paint_rect(30, 3, 38, 6, WATER)
    paint_rect(30, 3, 38, 3, WATER_EDGE)
    _put(29, 4, ROCK)
    _put(29, 6, ROCK)
    _put(39, 5, ROCK)

    # Jalan tanah utama, gang selatan, gang penghubung utara-selatan.
    paint_rect(2, 14, W - 3, 16, DIRT)
    paint_rect(2, 22, W - 3, 23, DIRT)
    paint_rect(21, 11, 22, 24, DIRT)

    # Plaza batu: satu di utara jalan, satu di persimpangan jalan utama.
    paint_rect(16, 11, 27, 13, COBBLE)
    paint_rect(17, 14, 26, 17, COBBLE)
    _put(well_cell.x, well_cell.y, WELL)

    # Delapan rumah: empat menghadap jalan utama, empat menghadap gang selatan.
    var north_x := [4, 11, 28, 35]
    for i in range(north_x.size()):
        house(north_x[i], 7, 6, 2, i == 1)
    var south_x := [4, 11, 27, 34]
    for i in range(south_x.size()):
        house(south_x[i], 17, 6, 2, i == 2)

    # Kebun tertutup di belakang rumah barat laut (pintu di bawah pintunya),
    # dan kandang di tenggara dengan satu lubang masuk.
    paint_rect(4, 12, 9, 12, FENCE)
    _put(6, 12, GRASS)
    outline_rect(34, 24, 39, 27)
    _put(39, 26, GRASS)

    # Semak dan batu hanya di rumput kosong, jauh dari pintu.
    for y in range(3, H - 3):
        for x in range(3, W - 3):
            var idx := _at(x, y)
            if idx != GRASS and idx != FLOWER:
                continue
            if _near_door(x, y, 3):
                continue
            var r := _rng.randf()
            if r < 0.030:
                _g[y * W + x] = BUSH
            elif r < 0.042:
                _g[y * W + x] = ROCK
            elif r < 0.058 and (x < 6 or x > W - 7 or y > H - 7):
                _g[y * W + x] = TREE

func house(x0: int, y0: int, w: int, door_off: int, plaster: bool) -> void:
    paint_rect(x0, y0, x0 + w - 1, y0, RIDGE)
    paint_rect(x0, y0 + 1, x0 + w - 1, y0 + 2, ROOF)
    paint_rect(x0, y0 + 3, x0 + w - 1, y0 + 3, WALL_PLASTER if plaster else WALL)
    _put(x0 + door_off, y0 + 3, DOOR)
    _put(x0 + door_off + 2, y0 + 3, WINDOW)

func outline_rect(x0: int, y0: int, x1: int, y1: int) -> void:
    paint_rect(x0, y0, x1, y0, FENCE)
    paint_rect(x0, y1, x1, y1, FENCE)
    for y in range(y0, y1 + 1):
        _put(x0, y, FENCE)
        _put(x1, y, FENCE)

func _near_door(x: int, y: int, radius: int) -> bool:
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            var nx := x + dx
            var ny := y + dy
            if nx < 0 or ny < 0 or nx >= W or ny >= H:
                continue
            if _at(nx, ny) == DOOR:
                return true
    return false

func paint_rect(x0: int, y0: int, x1: int, y1: int, idx: int) -> void:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            _g[y * W + x] = idx

func _put(x: int, y: int, idx: int) -> void:
    _g[y * W + x] = idx

func count_walkable() -> int:
    var n := 0
    for idx in _g:
        if _is_walkable(idx):
            n += 1
    return n

func dump() -> void:
    print("peta desa ", W, "x", H, "  . rumput  * bunga  d tanah  c batu  W/P dinding  R/p atap  D pintu  w jendela  T pohon  b semak  # sumur  f pagar  o batu kali  ~/X air")
    for y in range(H):
        var line := ""
        for x in range(W):
            line += LEGEND[_at(x, y)]
        print("%02d %s" % [y, line])

func build_scene(ts: TileSet) -> PackedScene:
    var root := Node2D.new()
    root.name = "Village"
    root.set_script(load("res://village.gd"))

    var layer := TileMapLayer.new()
    layer.name = "TileMapLayer"
    layer.tile_set = ts
    for y in range(H):
        for x in range(W):
            layer.set_cell(Vector2i(x, y), 0, _atlas(_at(x, y)))
    root.add_child(layer)
    layer.owner = root

    var arrive := Marker2D.new()
    arrive.name = "ArriveFromDungeon"
    root.add_child(arrive)
    arrive.owner = root
    arrive.global_position = layer.to_global(layer.map_to_local(arrival_cell))

    var portal := Area2D.new()
    portal.name = "PortalToDungeon"
    portal.set_script(load("res://portal.gd"))
    portal.set("target_map_id", &"dungeon")
    portal.set("label", "Ke Dungeon")
    root.add_child(portal)
    portal.owner = root
    portal.global_position = layer.to_global(layer.map_to_local(portal_cell))

    var points := Node2D.new()
    points.name = "SpawnPoints"
    root.add_child(points)
    points.owner = root
    var chosen := spawn_cells()
    for i in range(chosen.size()):
        var marker := Marker2D.new()
        marker.name = "Spawn%d" % (i + 1)
        points.add_child(marker)
        marker.owner = root
        marker.global_position = layer.to_global(layer.map_to_local(chosen[i]))
    print("titik spawn desa: ", chosen.size(), " -> ", chosen)

    root.set("grid_layer", layer)
    root.set("spawn_points", points)
    root.set("arrival_point", arrive)

    var ps := PackedScene.new()
    print("pack village: ", ps.pack(root), " (0 = OK)")
    return ps

# Sel layak spawn: ubin terbuka dengan keempat tetangga orthogonal ikut terbuka,
# tidak menempeli plaza tempat player datang.
func spawn_cells() -> Array[Vector2i]:
    var open: Array[Vector2i] = []
    for y in range(3, H - 3):
        for x in range(3, W - 3):
            if not _is_walkable(_at(x, y)):
                continue
            var ok := true
            for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
                if not _is_walkable(_at(x + d.x, y + d.y)):
                    ok = false
                    break
            if ok:
                open.append(Vector2i(x, y))
    open.shuffle()
    var chosen: Array[Vector2i] = []
    for c in open:
        if chosen.size() >= 10:
            break
        if c.distance_to(portal_cell) < 6.0:
            continue
        var far := true
        for k in chosen:
            if Vector2(c - k).length() < 7.0:
                far = false
                break
        if far:
            chosen.append(c)
    return chosen
