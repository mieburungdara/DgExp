@tool
extends Node

# Sub-ubin per ubin untuk rasterisasi margin navmesh (2 -> 8px pada ubin 16px).
const SUBDIV := 2

# --- PENGATURAN ISAAC GENERATOR ---
@export_group("Map Settings")
@export var room_count: int = 15
@export var room_width: int = 13  # Lebar 1 ruangan (dalam tiles)
@export var room_height: int = 9  # Tinggi 1 ruangan (dalam tiles)
@export var corridor_gap: int = 4 # Jarak lorong antar ruangan (0 = nempel dinding)
@export var connection_width: int = 2 # Lebar pintu/lorong

@export_group("Navmesh")
# Setengah ukuran badan karakter + offset bentuk tabrakannya (CollisionShape2D player
# bergeser 1px ke atas dari titik badan), plus sedikit kelonggaran. Clearance 5 kurang,
# 8 sudah mulai menyesakkan lorong sempit; 6 paling halus terukur.
@export var nav_body_clearance: Vector2 = Vector2(6, 6)

@export_group("Tile Settings")
@export var tile_map_layer: TileMapLayer
@export var source_id: int = 0
@export var floor_atlas_coords: Array[Vector2i] = [Vector2i(1, 1)] # Daftar ubin lantai untuk variasi

@export_subgroup("Wall Sisi")
@export var wall_t_atlas_coord: Vector2i = Vector2i(1, 0) # Top
@export var wall_b_atlas_coord: Vector2i = Vector2i(1, 2) # Bottom
@export var wall_l_atlas_coord: Vector2i = Vector2i(0, 1) # Left
@export var wall_r_atlas_coord: Vector2i = Vector2i(2, 1) # Right

@export_subgroup("Wall Sudut")
@export var wall_tl_atlas_coord: Vector2i = Vector2i(0, 0) # Top Left
@export var wall_tr_atlas_coord: Vector2i = Vector2i(2, 0) # Top Right
@export var wall_bl_atlas_coord: Vector2i = Vector2i(0, 2) # Bottom Left
@export var wall_br_atlas_coord: Vector2i = Vector2i(2, 2) # Bottom Right

@export_group("Game Data")
@export var level_data: DungeonLevelData # Drag & Drop file .tres ke sini

@export_group("Actions")
@export var generate_btn: bool = false:
    set(value):
        if value:
            generate_dungeon()
        generate_btn = false

@export var clear_btn: bool = false:
    set(value):
        if value:
            clear_map()
        clear_btn = false

# --- DATA ---
var room_grid: Dictionary = {} # (Vector2i) -> bool. Menyimpan posisi LOGIS (0,0), (1,0) dsb.

# TileMapLayer didaftarkan lewat group supaya karakter bisa membangun grid jalurnya
# tanpa perlu jalur node yang di-hardcode.
func _ready() -> void:
    if tile_map_layer:
        tile_map_layer.add_to_group("dungeon_grid")

func generate_dungeon():
    if not tile_map_layer:
        print("Error: TileMapLayer belum di-assign!")
        return
        
    print("Generating Isaac-Style Dungeon...")
    clear_map()
    room_grid.clear()
    
    # Override setting dari Level Data jika ada
    var target_room_count = room_count
    if level_data and level_data.override_room_count > 0:
        target_room_count = level_data.override_room_count
    
    # 1. GENERATE LAYOUT (Virtual Grid)
    var current_pos = Vector2i(0, 0)
    room_grid[current_pos] = true # Start Room
    
    # Queue untuk Breadth-First Expansion (atau Random Walker)
    var rooms_created = 1
    var max_loops = 1000
    var loops = 0
    
    while rooms_created < target_room_count and loops < max_loops:
        loops += 1
        
        # Pick random existing room
        var existing_keys = room_grid.keys()
        var pick = existing_keys.pick_random()
        
        # Pick random direction
        var dir = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT].pick_random()
        var target = pick + dir
        
        # Cek apakah target kosong
        if not room_grid.has(target):
            # Kondisi tambahan: Jangan buat ruangan yang terlalu "padat" (terlalu banyak tetangga)
            var neighbor_count = count_neighbors(target)
            if neighbor_count <= 1: 
                room_grid[target] = true
                rooms_created += 1
    
    print("Layout selesai. Total Room: ", rooms_created)
    
    # 2. GAMBAR KE TILEMAP
    draw_map()

    # 3. BAKE ULANG NAVMESH (wajib, kalau tidak pathfinding memakai mesh lama)
    rebake_navmesh()

    # 4. SPAWN OBJECTS (Boss, Portal, Enemy)
    # Hapus object lama, TAPI jangan sentuh NavigationRegion2D: TileMapLayer adalah
    # cucunya, jadi perbandingan langsung dengan tile_map_layer tidak akan pernah cocok.
    _free_generated_children()
        
    if level_data:
        spawn_objects()
    else:
        print("Warning: Level Data belum di-assign, tidak ada object yang di-spawn.")
func count_neighbors(pos: Vector2i) -> int:
    var count = 0
    for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
        if room_grid.has(pos + dir):
            count += 1
    return count

func draw_map():
    # FASE 1: Gambar semua Ruangan
    for grid_pos in room_grid.keys():
        var start_x = grid_pos.x * (room_width + corridor_gap)
        var start_y = grid_pos.y * (room_height + corridor_gap)
        create_single_room(start_x, start_y, grid_pos)

    # FASE 2: Gambar Koneksi (Jebol Dinding)
    for grid_pos in room_grid.keys():
        var start_x = grid_pos.x * (room_width + corridor_gap)
        var start_y = grid_pos.y * (room_height + corridor_gap)
        create_connections(start_x, start_y, grid_pos)

# Bangun satu NavigationPolygon dari sel lantai yang punya nav polygon di layer 0.
# Navmesh harus satu region dan semua titik sudut polygon harus bertemu persis:
# Godot menyambungkan polygon hanya lewat tepi yang vertex-nya sama, jadi T-junction
# (satu baris lebar bertemu beberapa baris sempit) membuat jalur terputus.
func rebake_navmesh() -> void:
    var region := get_node_or_null("NavigationRegion2D") as NavigationRegion2D
    if region == null or tile_map_layer == null:
        print("Warning: NavigationRegion2D / TileMapLayer tidak ada, navmesh tidak di-bake.")
        return

    var step_x: Vector2 = tile_map_layer.map_to_local(Vector2i(1, 0)) - tile_map_layer.map_to_local(Vector2i(0, 0))
    var step_y: Vector2 = tile_map_layer.map_to_local(Vector2i(0, 1)) - tile_map_layer.map_to_local(Vector2i(0, 0))

    var walk := {}
    for cell in tile_map_layer.get_used_cells():
        var td := tile_map_layer.get_cell_tile_data(cell)
        if td != null and td.get_navigation_polygon(0) != null:
            walk[cell] = true

    # Navmesh harus menyisakan ruang aman sebesar badan karakter di SEMUA arah,
    # termasuk diagonal. Erosi per-ubin tidak melindungi sudut diagonal dan menutup
    # lorong sempit, jadi area jalan diraster pada sub-ubin.
    var tile_v := Vector2(step_x.x, step_y.y)
    var sub_v: Vector2 = tile_v / float(SUBDIV)
    var origin: Vector2 = tile_map_layer.map_to_local(Vector2i(0, 0)) - tile_v * 0.5
    var xs_by_row := {}
    for cell in walk:
        for sy in range(SUBDIV):
            for sx in range(SUBDIV):
                var mid: Vector2 = origin + (Vector2(cell) * SUBDIV + Vector2(sx, sy) + Vector2(0.5, 0.5)) * sub_v
                if not _body_fits(mid, origin, tile_v, walk):
                    continue
                var sub_row: int = cell.y * SUBDIV + sy
                if not xs_by_row.has(sub_row):
                    xs_by_row[sub_row] = []
                xs_by_row[sub_row].append(cell.x * SUBDIV + sx)

    var spans := {}
    for y in xs_by_row:
        xs_by_row[y].sort()
        spans[y] = _to_spans(xs_by_row[y])

    # Potong tiap baris di semua batas segmen tetangga, diulang sampai stabil:
    # satu potongan baru di baris y memaksa potongan lanjutan di baris y-1 / y+1.
    var segments := {}
    for y in spans:
        segments[y] = spans[y]
    var changed := true
    var guard := 0
    while changed and guard < 4000:
        changed = false
        guard += 1
        for y in segments:
            var cuts := {}
            for src in [y - 1, y, y + 1]:
                if segments.has(src):
                    for s in segments[src]:
                        cuts[s[0]] = true
                        cuts[s[1] + 1] = true
            var points: Array = cuts.keys()
            points.sort()
            var out: Array = []
            for s in segments[y]:
                var a: int = s[0]
                for c in points:
                    if c <= a or c > s[1] + 1:
                        continue
                    out.append([a, c - 1])
                    a = c
            if out.size() != segments[y].size():
                changed = true
            segments[y] = out

    var outlines: Array[PackedVector2Array] = []
    var verts := PackedVector2Array()
    var polys: Array[PackedInt32Array] = []
    var vert_index := {}
    var ys: Array = segments.keys()
    ys.sort()
    for y in ys:
        for s in segments[y]:
            var corners := PackedVector2Array([
                _sub_corner(origin, sub_v, s[0], y, false, false),
                _sub_corner(origin, sub_v, s[1], y, true, false),
                _sub_corner(origin, sub_v, s[1], y, true, true),
                _sub_corner(origin, sub_v, s[0], y, false, true),
            ])
            var idx := PackedInt32Array([])
            for c in corners:
                var key := "%d_%d" % [roundi(c.x * 1000.0), roundi(c.y * 1000.0)]
                if not vert_index.has(key):
                    vert_index[key] = verts.size()
                    verts.append(c)
                idx.append(vert_index[key])
            outlines.append(PackedVector2Array([corners[0], corners[1], corners[2], corners[3]]))
            polys.append(idx)

    var poly := NavigationPolygon.new()
    poly.vertices = verts
    poly.polygons = polys
    poly.outlines = outlines
    region.navigation_polygon = poly
    tile_map_layer.navigation_enabled = false
    print("Navmesh di-bake: %d polygon, %d vertex." % [poly.polygons.size(), poly.vertices.size()])

func _to_spans(xs: Array) -> Array:
    var spans: Array = []
    var a: int = xs[0]
    var b: int = xs[0]
    for i in range(1, xs.size() + 1):
        var x: int = xs[i] if i < xs.size() else b + 2
        if x == b + 1:
            b = x
            continue
        spans.append([a, b])
        a = x
        b = x
    return spans

func _sub_corner(origin: Vector2, sub_v: Vector2, sx: int, sy: int, right: bool, bottom: bool) -> Vector2:
    var p := origin + Vector2(sx, sy) * sub_v
    if right:
        p.x += sub_v.x
    if bottom:
        p.y += sub_v.y
    return p

# Badan karakter harus seluruhnya di dalam ubin lantai, tidak hanya titik tengahnya.
func _body_fits(center: Vector2, origin: Vector2, tile_v: Vector2, walk: Dictionary) -> bool:
    var r := Rect2(center - nav_body_clearance, nav_body_clearance * 2.0)
    var c0 := Vector2i(floori((r.position.x - origin.x) / tile_v.x), floori((r.position.y - origin.y) / tile_v.y))
    var c1 := Vector2i(floori((r.end.x - origin.x - 0.001) / tile_v.x), floori((r.end.y - origin.y - 0.001) / tile_v.y))
    for cy in range(c0.y, c1.y + 1):
        for cx in range(c0.x, c1.x + 1):
            if not walk.has(Vector2i(cx, cy)):
                return false
    return true

func get_random_floor() -> Vector2i:
    # Cek override dari Level Data dulu
    if level_data and level_data.override_floor_atlas.size() > 0:
        return level_data.override_floor_atlas.pick_random()
        
    if floor_atlas_coords.size() > 0:
        return floor_atlas_coords.pick_random()
    return Vector2i(1, 1)

func create_single_room(start_x: int, start_y: int, grid_pos: Vector2i):
    for x in range(room_width):
        for y in range(room_height):
            var tile_pos = Vector2i(start_x + x, start_y + y)
            
            # 1. CEK SUDUT (Corners)
            if x == 0 and y == 0:
                tile_map_layer.set_cell(tile_pos, source_id, wall_tl_atlas_coord)
            elif x == room_width - 1 and y == 0:
                tile_map_layer.set_cell(tile_pos, source_id, wall_tr_atlas_coord)
            elif x == 0 and y == room_height - 1:
                tile_map_layer.set_cell(tile_pos, source_id, wall_bl_atlas_coord)
            elif x == room_width - 1 and y == room_height - 1:
                tile_map_layer.set_cell(tile_pos, source_id, wall_br_atlas_coord)
            
            # 2. CEK SISI (Sides)
            elif y == 0:
                tile_map_layer.set_cell(tile_pos, source_id, wall_t_atlas_coord)
            elif y == room_height - 1:
                tile_map_layer.set_cell(tile_pos, source_id, wall_b_atlas_coord)
            elif x == 0:
                tile_map_layer.set_cell(tile_pos, source_id, wall_l_atlas_coord)
            elif x == room_width - 1:
                tile_map_layer.set_cell(tile_pos, source_id, wall_r_atlas_coord)
            
            # 3. LANTAI
            else:
                tile_map_layer.set_cell(tile_pos, source_id, get_random_floor())

func create_connections(start_x: int, start_y: int, grid_pos: Vector2i):
    var center_offset = -int(connection_width / 2)
    
    # 1. KONEKSI KANAN (RIGHT)
    if room_grid.has(grid_pos + Vector2i.RIGHT):
        var wall_right_x = start_x + room_width - 1
        var center_y = start_y + (room_height / 2)
        var start_draw_x = wall_right_x - 1
        var end_draw_x = wall_right_x + corridor_gap + 1
        
        for x in range(start_draw_x, end_draw_x + 1):
            for w in range(connection_width):
                var y = center_y + center_offset + w
                var pos = Vector2i(x, y)
                tile_map_layer.set_cell(pos, -1) 
                tile_map_layer.set_cell(pos, source_id, get_random_floor())
            
            if x > wall_right_x and x < wall_right_x + corridor_gap + 1:
                # Dinding Atas Lorong (Wall Top)
                tile_map_layer.set_cell(Vector2i(x, center_y + center_offset - 1), source_id, wall_t_atlas_coord)
                # Dinding Bawah Lorong (Wall Bottom)
                tile_map_layer.set_cell(Vector2i(x, center_y + center_offset + connection_width), source_id, wall_b_atlas_coord)

    # 2. KONEKSI BAWAH (DOWN)
    if room_grid.has(grid_pos + Vector2i.DOWN):
        var center_x = start_x + (room_width / 2)
        var wall_bottom_y = start_y + room_height - 1
        var start_draw_y = wall_bottom_y - 1
        var end_draw_y = wall_bottom_y + corridor_gap + 1
        
        for y in range(start_draw_y, end_draw_y + 1):
            for w in range(connection_width):
                var x = center_x + center_offset + w
                var pos = Vector2i(x, y)
                tile_map_layer.set_cell(pos, -1)
                tile_map_layer.set_cell(pos, source_id, get_random_floor())
        
            if y > wall_bottom_y and y < wall_bottom_y + corridor_gap + 1:
                # Dinding Kiri Lorong (Wall Left)
                tile_map_layer.set_cell(Vector2i(center_x + center_offset - 1, y), source_id, wall_l_atlas_coord)
                # Dinding Kanan Lorong (Wall Right)
                tile_map_layer.set_cell(Vector2i(center_x + center_offset + connection_width, y), source_id, wall_r_atlas_coord)

func spawn_objects():
    # 1. Cari Ruang Terjauh (Boss Room / End Room)
    var max_dist = -1.0
    var furthest_room = Vector2i(0, 0)
    
    for pos in room_grid.keys():
        var dist = pos.length_squared() # Jarak dari (0,0) kuadrat
        if dist > max_dist:
            max_dist = dist
            furthest_room = pos
            
    print("Ruang Terjauh di grid: ", furthest_room)
    
    # 2. Spawn Boss
    if level_data.boss_scene:
        var boss_pos = get_room_center_world(furthest_room)
        var boss = level_data.boss_scene.instantiate()
        boss.position = boss_pos
        add_child(boss)
        
        if Engine.is_editor_hint():
            boss.owner = get_tree().edited_scene_root
        print("Boss Spawned di ", boss_pos)
        
    # 3. Spawn Portal
    if level_data.portal_scene:
        var portal_pos = get_room_center_world(furthest_room)
        
        # Jika ada Boss, Portal digeser dikit
        if level_data.boss_scene:
            portal_pos += Vector2(0, -50) 
            
        var portal = level_data.portal_scene.instantiate()
        portal.position = portal_pos
        add_child(portal)
        if Engine.is_editor_hint():
            portal.owner = get_tree().edited_scene_root

func get_room_center_world(grid_pos: Vector2i) -> Vector2:
    # Hitung posisi tile pojok kiri atas ruangan
    var start_x = grid_pos.x * (room_width + corridor_gap)
    var start_y = grid_pos.y * (room_height + corridor_gap)
    
    # Hitung tengah dalam tile
    var center_tile_x = start_x + (room_width / 2.0)
    var center_tile_y = start_y + (room_height / 2.0)
    
    # Konversi ke World Position (Pixel)
    var tile_size = tile_map_layer.tile_set.tile_size
    
    return Vector2(center_tile_x * tile_size.x, center_tile_y * tile_size.y)

func clear_map():
    if tile_map_layer:
        tile_map_layer.clear()

    # Clear spawned objects (children) tapi jangan hapus TileMapLayer-nya sendiri
    _free_generated_children()

# Hanya buang anak yang bukan bagian dari subtree peta (NavigationRegion2D/TileMapLayer).
func _free_generated_children() -> void:
    for child in get_children():
        if child == tile_map_layer or child.is_ancestor_of(tile_map_layer):
            continue
        child.queue_free()
