extends SceneTree

# Pembangun sekali-jalan untuk peta desa. Tileset-nya dibangkitkan
# tools/build_village_art.py; skrip ini menyusun layout dan menyimpan village.tscn.
# Deterministik (seed dipatok) supaya file yang masuk git sama dengan yang
# diverifikasi.
#
# Tiga TileMapLayer:
#   GroundLayer  rumput / jalan / plaza, tanpa collision
#   ShadowLayer  tile bayangan semi-transparan, tanpa collision
#   ObjectLayer  rumah / pohon / prop / air, plus tile EMPTY transparan di sel
#                yang kosong. Layer ini yang jadi grid jalur, makanya setiap sel
#                harus terisi: GridPath menganggap sel kosong "bukan lantai".

const W := 44
const H := 30

const GRASS := 0
const GRASS_FLOWER := 1
const GRASS_DARK := 2
const GRASS_WORN := 3
const GRASS_CLOVER := 4
const DIRT := 5
const COBBLE := 6
const WATER_EDGE := 7
const WATER := 8
const WALL_WOOD := 9
const WALL_PLASTER := 10
const WALL_DOOR := 11
const WALL_WINDOW := 12
const ROOF_CLAY := 13
const ROOF_CLAY_RIDGE := 14
const ROOF_SLATE := 15
const ROOF_SLATE_RIDGE := 16
const ROOF_THATCH := 17
const ROOF_THATCH_RIDGE := 18
const ROOF_CHIMNEY := 19
const TREE := 20
const PINE := 21
const BUSH := 22
const BUSH_BERRY := 23
const FERN := 24
const SHRUB_FLOWER := 25
const WELL := 26
const FENCE := 27
const ROCK := 28
const BARREL := 29
const CRATE := 30
const CART := 31
const HAYSTACK := 32
const LANTERN := 33
const SIGNPOST := 34
const FLOWER_POT := 35
const STALL := 36
const DUMMY := 37
const TROUGH := 38
const LOGS := 39
const BENCH := 40
const SHADOW_BOTTOM := 41
const SHADOW_RIGHT := 42
const SHADOW_CORNER := 43
const SHADOW_PROP := 44
const EMPTY := 45
const WATER_BLOCK := 46
const BRIDGE := 47

const LEGEND := [".", "*", "g", "w", "c", "d", "b", "~", "A", "W", "P", "D", "n", "R", "p",
    "S", "s", "T", "t", "C", "X", "x", "u", "y", "f", "h", "#", "=", "o", "B", "K", "v",
    "H", "L", "i", "q", "M", "J", "r", "Z", "V", "_", "'", ",", ":", ".", "A", "j"]

# Bangunan mendapat bayangan memanjang di sisi kanan-bawah; pohon dan prop cukup
# satu blob kecil di bawahnya.
const BUILDING := [WALL_WOOD, WALL_PLASTER, WALL_DOOR, WALL_WINDOW, ROOF_CLAY,
    ROOF_CLAY_RIDGE, ROOF_SLATE, ROOF_SLATE_RIDGE, ROOF_THATCH, ROOF_THATCH_RIDGE, ROOF_CHIMNEY]

const SOFT_SHADE := [TREE, PINE, BUSH, BUSH_BERRY, SHRUB_FLOWER, FERN, WELL, BARREL, CRATE,
    CART, HAYSTACK, LANTERN, SIGNPOST, FLOWER_POT, STALL, DUMMY, TROUGH, LOGS, BENCH, ROCK]

const GROUND_VARIANTS := [GRASS, GRASS_FLOWER, GRASS_DARK, GRASS_WORN, GRASS_CLOVER]

# Prop buatan manusia, untuk laporan: pohon/semak/batu tidak dihitung di sini.
const HANDMADE := [WALL_WOOD, WALL_PLASTER, WALL_DOOR, WALL_WINDOW, ROOF_CLAY, ROOF_CLAY_RIDGE,
    ROOF_SLATE, ROOF_SLATE_RIDGE, ROOF_THATCH, ROOF_THATCH_RIDGE, ROOF_CHIMNEY, WELL, FENCE,
    BARREL, CRATE, CART, HAYSTACK, LANTERN, SIGNPOST, FLOWER_POT, STALL, DUMMY, TROUGH, LOGS,
    BENCH]

var _g: Array[int] = []
var _o: Array[int] = []
var _s: Array[int] = []
var _w: Array[int] = []
var _solid: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _lanterns: Array[Vector2i] = []
var _lit_cells: Array[Vector2i] = []

var portal_cell := Vector2i(19, 16)
var arrival_cell := Vector2i(20, 16)
var well_cell := Vector2i(23, 16)

func _atlas(idx: int) -> Vector2i:
    return Vector2i(idx % 8, int(idx / 8))

func _gi(x: int, y: int) -> int:
    return _g[y * W + x]

func _oi(x: int, y: int) -> int:
    return _o[y * W + x]

func _in(x: int, y: int) -> bool:
    return x >= 0 and y >= 0 and x < W and y < H

func _is_solid(idx: int) -> bool:
    return _solid.get(idx, false)

func _open(x: int, y: int) -> bool:
    if not _in(x, y):
        return false
    return not _is_solid(_oi(x, y))

func _putg(x: int, y: int, idx: int) -> void:
    _g[y * W + x] = idx

func _puto(x: int, y: int, idx: int) -> void:
    _o[y * W + x] = idx

func rectg(x0: int, y0: int, x1: int, y1: int, idx: int) -> void:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            _putg(x, y, idx)

func recto(x0: int, y0: int, x1: int, y1: int, idx: int) -> void:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            _puto(x, y, idx)

func _initialize() -> void:
    _rng.seed = 20261104
    # Array.shuffle() memakai RNG global.
    seed(20261104)

    var ts := load("res://village_tileset.tres") as TileSet
    if ts == null or ts.get_source_count() == 0:
        push_error("village_tileset.tres kosong/gagal dimuat, berhenti.")
        quit(1)
        return
    read_solidity(ts)

    _g.resize(W * H)
    _g.fill(GRASS)
    _o.resize(W * H)
    _o.fill(EMPTY)
    _s.resize(W * H)
    _s.fill(EMPTY)
    _w.resize(W * H)
    _w.fill(EMPTY)

    paint()
    dump()

    var scene := build_scene(ts)
    print("simpan scene: ", ResourceSaver.save(scene, "res://village.tscn"), " (0 = OK)")
    report()
    quit()

# Sumber kebenaran "ubin mana yang menghalangi" dibaca dari tileset-nya sendiri,
# bukan dari daftar konstanta kedua yang bisa diam-diam berbeda.
func read_solidity(ts: TileSet) -> void:
    var src := ts.get_source(0) as TileSetAtlasSource
    _solid.clear()
    for i in range(src.get_tiles_count()):
        var c := src.get_tile_id(i)
        var td := src.get_tile_data(c, 0)
        _solid[c.y * 8 + c.x] = td.get_collision_polygons_count(0) > 0

func paint() -> void:
    paint_ground()
    paint_forest_border()
    paint_pond()
    paint_stream()
    paint_roads()
    paint_houses()
    paint_extras()
    paint_scatter()
    paint_worn_edges()
    paint_shadows()

func paint_ground() -> void:
    for y in range(H):
        for x in range(W):
            var h := absi(hash_for(x, y)) % 100
            var idx := GRASS
            if h < 24:
                idx = GRASS_DARK
            elif h < 38:
                idx = GRASS_CLOVER
            elif h < 54:
                idx = GRASS_FLOWER
            _putg(x, y, idx)

# Hash per bercak 4x4 ubin dicampur variasi per sel: varian rumput datang sebagai
# tambalan, bukan bintik acak.
func hash_for(x: int, y: int) -> int:
    var px := x >> 2
    var py := y >> 2
    return (px * 73856093) ^ (py * 19349663) ^ ((x * 31 + y * 17) * 2654435761)

func paint_forest_border() -> void:
    for y in range(H):
        for x in range(W):
            if x < 2 or y < 2 or x >= W - 2 or y >= H - 2:
                _putg(x, y, GRASS)
                _puto(x, y, PINE if _rng.randf() < 0.34 else TREE)
    # Tepi dalam dirobek: hutan pembatas tidak lagi terbaca sebagai pagar lurus.
    for y in range(2, H - 2):
        for x in range(2, W - 2):
            if _oi(x, y) != EMPTY:
                continue
            var touching := _oi(x - 1, y) != EMPTY or _oi(x + 1, y) != EMPTY \
                or _oi(x, y - 1) != EMPTY or _oi(x, y + 1) != EMPTY
            if not touching:
                continue
            if _rng.randf() < 0.34:
                _putg(x, y, GRASS)
                _puto(x, y, PINE if _rng.randf() < 0.3 else TREE)
            elif _rng.randf() < 0.12:
                _putg(x, y, GRASS)
                _puto(x, y, BUSH_BERRY if _rng.randf() < 0.4 else BUSH)

func paint_pond() -> void:
    # Bentuk organik: radius dimodulasi hash, bukan persegi lagi.
    var cx := 34.0
    var cy := 5.5
    for y in range(2, 10):
        for x in range(27, 41):
            var dx := (x - cx) / 6.6
            var dy := (y - cy) / 3.4
            var wob := 1.0 + 0.28 * float(((x * 7 + y * 13) % 5) - 2) / 2.0
            if dx * dx + dy * dy <= wob * wob:
                _putg(x, y, DIRT)
                _putw(x, y, WATER_EDGE if y == 3 else WATER)
                _puto(x, y, WATER_BLOCK)
    _puto(27, 5, ROCK)
    _puto(27, 7, FERN)
    _puto(40, 4, ROCK)
    _puto(30, 9, TROUGH)
    _puto(31, 9, FERN)

# Sungai ke barat daya: keluar dari hutan, diseberangi jembatan di ujung gang
# penghubung, dan berhenti di bank timur. Visualnya di WaterLayer, solidnya
# WATER_BLOCK transparan di ObjectLayer supaya GridPath tetap menolak air.
func paint_stream() -> void:
    for x in range(2, 32):
        _putg(x, 25, DIRT)
        _putg(x, 26, DIRT)
        _putw(x, 25, WATER_EDGE)
        _putw(x, 26, WATER)
        _puto(x, 25, WATER_BLOCK)
        _puto(x, 26, WATER_BLOCK)
    # Jembatan segaris dengan gang utara-selatan.
    recto(21, 25, 22, 26, BRIDGE)
    rectg(21, 25, 22, 26, DIRT)
    # Bank: batu dan alang-alang, pagar pendek menahan kambing tidak ke air.
    _puto(19, 24, ROCK)
    _puto(24, 24, FERN)
    _puto(14, 27, ROCK)
    _puto(15, 27, FERN)
    _puto(28, 27, SHRUB_FLOWER)

func _putw(x: int, y: int, idx: int) -> void:
    _w[y * W + x] = idx

func paint_roads() -> void:
    rectg(2, 14, W - 3, 16, DIRT)
    rectg(2, 22, W - 3, 23, DIRT)
    rectg(21, 11, 22, 27, DIRT)
    # Jalur pantai selatan, menyambung ke ujung jembatan. Tanpa ini tepi hutan
    # yang dirobek acak menutup strip di antara sungai dan hutan selatan.
    rectg(4, 27, 31, 27, DIRT)
    rectg(16, 11, 27, 13, COBBLE)
    rectg(17, 14, 26, 17, COBBLE)
    clear_path_objects()
    _puto(well_cell.x, well_cell.y, WELL)

# Sisa hutan pembatas dan semak yang terpasang sebelum jalan tidak boleh menutup
# jalur; prop yang memang duduk di plaza ditambahkan setelah langkah ini.
func clear_path_objects() -> void:
    for y in range(H):
        for x in range(W):
            var o := _oi(x, y)
            # Air, blok air, dan jembatan memang sengaja duduk di atas tanah
            # jalan; yang boleh dibersihkan hanya sisa hutan dan semak.
            if o == WATER or o == WATER_EDGE or o == WATER_BLOCK or o == BRIDGE:
                continue
            if _gi(x, y) == DIRT or _gi(x, y) == COBBLE:
                _puto(x, y, EMPTY)

func paint_houses() -> void:
    # x, y, lebar, kedalaman, gaya atap (0 terakota / 1 slate / 2 ilalang), plester
    var specs := [
        [4, 6, 7, 4, 0, false], [12, 7, 5, 3, 2, false], [28, 7, 6, 4, 1, true],
        [35, 8, 5, 3, 0, false], [4, 17, 6, 4, 2, true], [12, 17, 7, 3, 0, false],
        [27, 18, 5, 3, 1, false], [34, 17, 6, 4, 0, true],
    ]
    for i in range(specs.size()):
        var s: Array = specs[i]
        build_house(int(s[0]), int(s[1]), int(s[2]), int(s[3]), int(s[4]), bool(s[5]), i)

func build_house(x0: int, y0: int, w: int, d: int, style: int, plaster: bool, idx: int) -> void:
    var ridge: int = [ROOF_CLAY_RIDGE, ROOF_SLATE_RIDGE, ROOF_THATCH_RIDGE][style]
    var roof: int = [ROOF_CLAY, ROOF_SLATE, ROOF_THATCH][style]
    var wall: int = WALL_PLASTER if plaster else WALL_WOOD

    recto(x0, y0, x0 + w - 1, y0, ridge)
    if d > 3:
        recto(x0, y0 + 1, x0 + w - 1, y0 + d - 2, roof)
    recto(x0, y0 + d - 1, x0 + w - 1, y0 + d - 1, wall)

    if d > 3 and idx % 2 == 0:
        _puto(x0 + w - 2, y0 + 1, ROOF_CHIMNEY)

    var door_x := x0 + 1 + (idx % maxi(w - 2, 1))
    _puto(door_x, y0 + d - 1, WALL_DOOR)
    if door_x + 2 < x0 + w:
        _puto(door_x + 2, y0 + d - 1, WALL_WINDOW)
    if w >= 7 and door_x - 2 >= x0:
        _puto(door_x - 2, y0 + d - 1, WALL_WINDOW)

    # Pot dan tong di sel yang mengapit dinding, tidak pernah di depan pintu.
    if _oi(x0 - 1, y0 + d - 1) == EMPTY:
        _puto(x0 - 1, y0 + d - 1, FLOWER_POT)
    if _oi(x0 + w, y0 + d - 1) == EMPTY and idx % 3 != 0:
        _puto(x0 + w, y0 + d - 1, BARREL if idx % 2 == 0 else CRATE)

func paint_extras() -> void:
    for x in range(4, W - 4, 6):
        _place_lantern(x, 13)
        _place_lantern(x + 3, 17)
    _place_lantern(17, 13)
    _place_lantern(26, 18)

    _puto(20, 21, SIGNPOST)

    _puto(17, 12, STALL)
    _puto(26, 12, STALL)
    _puto(23, 17, BENCH)
    _lit_cells.append(Vector2i(17, 12))
    _lit_cells.append(Vector2i(26, 12))

    _puto(10, 11, CART)
    _puto(29, 12, LOGS)
    _puto(30, 12, BARREL)
    _puto(5, 24, DUMMY)
    _puto(6, 24, LOGS)
    _puto(36, 12, HAYSTACK)

    fence_row(4, 12, 10)
    _puto(6, 12, EMPTY)
    _puto(5, 11, HAYSTACK)
    outline(33, 24, 39, 27)
    # Lubang masuk di sisi barat: sisi timur berbatasan langsung dengan hutan,
    # jadi pintu di sana tidak bisa dicapai dari jalan.
    _puto(33, 26, EMPTY)
    _puto(35, 25, HAYSTACK)
    _puto(37, 26, TROUGH)

func _place_lantern(x: int, y: int) -> void:
    if not _in(x, y) or _oi(x, y) != EMPTY:
        return
    _puto(x, y, LANTERN)
    _lanterns.append(Vector2i(x, y))

func fence_row(x0: int, y: int, x1: int) -> void:
    for x in range(x0, x1 + 1):
        if _oi(x, y) == EMPTY:
            _puto(x, y, FENCE)

func outline(x0: int, y0: int, x1: int, y1: int) -> void:
    fence_row(x0, y0, x1)
    fence_row(x0, y1, x1)
    for y in range(y0, y1 + 1):
        if _oi(x0, y) == EMPTY:
            _puto(x0, y, FENCE)
        if _oi(x1, y) == EMPTY:
            _puto(x1, y, FENCE)

func paint_scatter() -> void:
    for y in range(3, H - 3):
        for x in range(3, W - 3):
            if _oi(x, y) != EMPTY:
                continue
            # Semak tidak boleh tumbuh di tengah jalan atau plaza.
            if _gi(x, y) == DIRT or _gi(x, y) == COBBLE:
                continue
            if _near_door(x, y, 3):
                continue
            var r := _rng.randf()
            if r < 0.020:
                _puto(x, y, FERN)
            elif r < 0.036:
                _puto(x, y, BUSH)
            elif r < 0.044:
                _puto(x, y, SHRUB_FLOWER)
            elif r < 0.052:
                _puto(x, y, ROCK)
            elif r < 0.058 and (x < 7 or x > W - 8 or y > H - 8):
                _puto(x, y, PINE)

func paint_worn_edges() -> void:
    # Rumput aus satu ubin di sekeliling jalan, plaza, dan bangunan: memecah
    # batas keras antara dua warna rata.
    for y in range(H):
        for x in range(W):
            var here := _gi(x, y)
            if not (here in GROUND_VARIANTS) or here == GRASS_WORN:
                continue
            for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
                var nx: int = x + d.x
                var ny: int = y + d.y
                if not _in(nx, ny):
                    continue
                var g := _gi(nx, ny)
                if g == DIRT or g == COBBLE:
                    _putg(x, y, GRASS_WORN)
                    break
                # Hanya bangunan yang meninggalkan jejak rumput aus; pohon dan
                # semak tidak, kalau tidak hampir seluruh halaman jadi cokelat.
                if _oi(nx, ny) in BUILDING:
                    _putg(x, y, GRASS_WORN)
                    break

func paint_shadows() -> void:
    for y in range(H):
        for x in range(W):
            var o := _oi(x, y)
            if o == EMPTY or o == WATER_BLOCK or not _is_solid(o):
                continue
            if o in BUILDING:
                _shadow(SHADOW_BOTTOM, x, y + 1)
                _shadow(SHADOW_RIGHT, x + 1, y)
                _shadow(SHADOW_CORNER, x + 1, y + 1)
            elif o in SOFT_SHADE:
                _shadow(SHADOW_PROP, x, y + 1)

func _shadow(idx: int, x: int, y: int) -> void:
    if not _in(x, y) or _oi(x, y) != EMPTY:
        return
    _s[y * W + x] = idx

func _near_door(x: int, y: int, radius: int) -> bool:
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            var nx := x + dx
            var ny := y + dy
            if not _in(nx, ny):
                continue
            if _oi(nx, ny) == WALL_DOOR:
                return true
    return false

func report() -> void:
    var ground := {}
    for idx in _g:
        ground[idx] = int(ground.get(idx, 0)) + 1
    var open := 0
    for y in range(H):
        for x in range(W):
            if _open(x, y):
                open += 1
    print("ubin_terbuka=", open, " dari ", W * H, "  prop_dekorasi=", _count_props(),
        "  lampu=", _lanterns.size(), "  sumber_cahaya=", _lanterns.size() + _lit_cells.size() + 1)
    for idx in GROUND_VARIANTS:
        print("  dasar %s = %d ubin (%.1f%%)" % [LEGEND[idx], int(ground.get(idx, 0)),
            100.0 * int(ground.get(idx, 0)) / float(W * H)])

func _count_props() -> int:
    var n := 0
    for idx in _o:
        if idx in HANDMADE:
            n += 1
    return n

func dump() -> void:
    print("=== layer objek (. rumput, spasi jalan/plaza, huruf = objek) ===")
    for y in range(H):
        var line := ""
        for x in range(W):
            var o := _oi(x, y)
            if o == EMPTY or o == WATER_BLOCK:
                line += " " if _gi(x, y) == DIRT or _gi(x, y) == COBBLE else "."
            else:
                line += LEGEND[o]
        print("%02d %s" % [y, line])
    print("=== layer dasar ===")
    for y in range(H):
        var line := ""
        for x in range(W):
            line += LEGEND[_gi(x, y)]
        print("%02d %s" % [y, line])

func build_scene(ts: TileSet) -> PackedScene:
    var root := Node2D.new()
    root.name = "Village"
    root.set_script(load("res://village.gd"))

    var ground := make_layer("GroundLayer", ts, _g)
    root.add_child(ground)
    ground.owner = root
    var water := make_layer("WaterLayer", ts, _w)
    var shimmer := ShaderMaterial.new()
    shimmer.shader = load("res://shaders/water_shimmer.gdshader")
    water.material = shimmer
    root.add_child(water)
    water.owner = root

    var shadow := make_layer("ShadowLayer", ts, _s)
    root.add_child(shadow)
    shadow.owner = root
    var objects := make_layer("ObjectLayer", ts, _o)
    root.add_child(objects)
    objects.owner = root

    var night := CanvasModulate.new()
    night.name = "Dusk"
    night.color = Color(0.66, 0.64, 0.72)
    root.add_child(night)
    night.owner = root

    var arrive := Marker2D.new()
    arrive.name = "ArriveFromDungeon"
    root.add_child(arrive)
    arrive.owner = root
    arrive.global_position = objects.to_global(objects.map_to_local(arrival_cell))

    add_portal(root, objects)

    # Desa kini zona aman: tidak ada titik spawn dibuat, node-nya hanya memenuhi
    # kontrak peta.
    var points := Node2D.new()
    points.name = "SpawnPoints"
    root.add_child(points)
    points.owner = root

    add_lights(root, objects)
    add_people(root, objects)

    root.set("grid_layer", objects)
    root.set("spawn_points", points)
    root.set("arrival_point", arrive)

    var ps := PackedScene.new()
    print("pack village: ", ps.pack(root), " (0 = OK)")
    return ps

func make_layer(layer_name: String, ts: TileSet, data: Array[int]) -> TileMapLayer:
    var layer := TileMapLayer.new()
    layer.name = layer_name
    layer.tile_set = ts
    for y in range(H):
        for x in range(W):
            layer.set_cell(Vector2i(x, y), 0, _atlas(data[y * W + x]))
    return layer

func add_portal(root: Node, objects: TileMapLayer) -> void:
    var portal := Area2D.new()
    portal.name = "PortalToDungeon"
    portal.set_script(load("res://portal.gd"))
    portal.set("target_map_id", &"dungeon")
    portal.set("label", "Ke Dungeon")
    root.add_child(portal)
    portal.owner = root
    portal.global_position = objects.to_global(objects.map_to_local(portal_cell))

# Warga dan hewan. Titiknya dipilih tangan lalu divalidasi: sel yang tertutup
# air/tembok dilewati, jadi perubahan layout tidak bisa menaruh NPC di dalam
# dinding.
func add_people(root: Node, objects: TileMapLayer) -> void:
    var spots := [
        ["merchant", Vector2i(17, 11), 0.0],
        ["farmer", Vector2i(8, 13), 40.0],
        ["woman", Vector2i(20, 12), 44.0],
        ["child", Vector2i(24, 18), 36.0],
        ["elder", Vector2i(22, 18), 32.0],
        ["guard", Vector2i(18, 18), 56.0],
        ["man", Vector2i(30, 20), 48.0],
        ["woman2", Vector2i(13, 13), 40.0],
        ["hen", Vector2i(35, 26), 20.0],
        ["rooster", Vector2i(36, 25), 20.0],
        ["duck", Vector2i(31, 10), 18.0],
        ["goose", Vector2i(30, 10), 18.0],
        ["goat", Vector2i(34, 25), 22.0],
        ["sheep", Vector2i(37, 26), 22.0],
        ["dog", Vector2i(6, 20), 52.0],
        ["cat", Vector2i(28, 13), 44.0],
    ]
    var placed := 0
    for spec in spots:
        var name: String = spec[0]
        var cell: Vector2i = spec[1]
        var radius: float = spec[2]
        var spot := _find_open_near(cell, 4)
        if spot == Vector2i(-1, -1):
            print("  lewat: ", name, " tidak ada sel terbuka di sekitar ", cell)
            continue
        if spot != cell:
            print("  digeser: ", name, " dari ", cell, " ke ", spot)
        cell = spot
        # Hewan kecil digambar setengah ukuran: 24 px di grid 16 px terlalu besar
        # untuk ayam, dan texture_scale tidak memengaruhi bentuk tabrakan.
        var is_animal := name in ["hen", "rooster", "duck", "goose", "goat", "sheep", "dog", "cat"]
        var npc_scale := Vector2(0.7, 0.7) if is_animal else Vector2.ONE
        var npc := CharacterBody2D.new()
        npc.name = name.capitalize()
        npc.set_script(load("res://villager.gd"))
        npc.set("texture_path", "res://art/people/%s.png" % name)
        npc.set("wander_radius", radius)
        npc.set("speed", 15.0 if is_animal else 26.0)
        npc.scale = npc_scale
        # Urutan penting: posisi dulu (node belum di tree, jadi global == lokal),
        # baru add_child supaya _ready() merekam rumah yang benar, lalu owner —
        # owner yang di-set sebelum add_child ditolak Godot dan node-nya hilang
        # saat PackedScene.pack().
        npc.position = objects.to_global(objects.map_to_local(cell))
        root.add_child(npc)
        npc.owner = root
        placed += 1
    print("warga+hewan terpasang: ", placed, " dari ", spots.size())
    _add_shop_trigger(root, objects)

# Pemicu toko persis di lapak tempat pedagang berdiri.
func _add_shop_trigger(root: Node, objects: TileMapLayer) -> void:
    var trigger := Area2D.new()
    trigger.name = "ShopTrigger"
    trigger.set_script(load("res://shop_trigger.gd"))
    root.add_child(trigger)
    trigger.owner = root
    trigger.global_position = objects.to_global(objects.map_to_local(Vector2i(17, 12)))

# Cincin membesar: cari sel terbuka terdekat dari titik yang diinginkan, jadi
# perpindahan prop tidak membuat NPC hilang diam-diam.
func _find_open_near(from_cell: Vector2i, reach: int) -> Vector2i:
    for radius in range(0, reach + 1):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if max(absi(dx), absi(dy)) != radius:
                    continue
                var c := from_cell + Vector2i(dx, dy)
                if _in(c.x, c.y) and _open(c.x, c.y):
                    return c
    return Vector2i(-1, -1)

# Cahaya hangat di lampu jalan, dua lapak, dan sumur.
func add_lights(root: Node, objects: TileMapLayer) -> void:
    var tex := load("res://light_soft.png") as Texture2D
    var cells: Array[Vector2i] = []
    for c in _lanterns:
        cells.append(c)
    for c in _lit_cells:
        cells.append(c)
    cells.append(well_cell)
    for i in range(cells.size()):
        var light := PointLight2D.new()
        light.name = "Light%d" % (i + 1)
        light.texture = tex
        light.energy = 1.25
        light.texture_scale = 0.85
        light.color = Color(1.0, 0.86, 0.62)
        root.add_child(light)
        light.owner = root
        light.global_position = objects.to_global(objects.map_to_local(cells[i])) + Vector2(0, -6)
