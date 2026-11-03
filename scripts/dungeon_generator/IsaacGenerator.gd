@tool
extends Node


# --- PENGATURAN ISAAC GENERATOR ---
@export_group("Map Settings")
@export var room_count: int = 15
@export var room_width: int = 13  # Lebar 1 ruangan (dalam tiles)
@export var room_height: int = 9  # Tinggi 1 ruangan (dalam tiles)
@export var corridor_gap: int = 4 # Jarak lorong antar ruangan (0 = nempel dinding)
@export var connection_width: int = 2 # Lebar pintu/lorong

@export_group("Spawn Points")
@export var spawn_point_count: int = 12 # Berapa titik spawn dibuat dari ubin lantai
@export var spawn_min_spacing: int = 6 # Jarak minimum antar titik spawn, dalam ubin


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

# Dipakai untuk memeriksa kelayakan ubin spawn. Harus Array[Vector2i] agar hasil
# penjumlahan tetap bertipe, bukan Variant.
const _NEIGHBOR_DIRS: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

# TileMapLayer didaftarkan lewat group supaya karakter bisa membangun grid jalurnya
# tanpa perlu jalur node yang di-hardcode.
func _ready() -> void:
    if tile_map_layer:
        tile_map_layer.add_to_group("dungeon_grid")
    # Saat main scene dijalankan, SpawnPoints masih kosong di file. Diisi sekarang
    # supaya monster punya tempat muncul tanpa harus menekan Generate dulu.
    if not Engine.is_editor_hint():
        fill_spawn_points()

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

    # 3. TITIK SPAWN dari ubin lantai yang baru digambar
    fill_spawn_points()

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


# SpawnPoints diisi dari ubin lantai supaya monster selalu muncul di tempat yang
# bisa diinjak, dan titik-titiknya ikut berpindah setiap dungeon digenerate ulang.
func fill_spawn_points() -> void:
    var holder := get_node_or_null("NavigationRegion2D/SpawnPoints")
    if holder == null or tile_map_layer == null:
        print("Warning: NavigationRegion2D/SpawnPoints tidak ada, titik spawn tidak dibuat.")
        return

    for old in holder.get_children():
        holder.remove_child(old)
        old.free()

    var open_cells: Array[Vector2i] = []
    for cell in tile_map_layer.get_used_cells():
        if _is_open_cell(cell):
            open_cells.append(cell)

    open_cells.shuffle()
    var chosen: Array[Vector2i] = []
    for c in open_cells:
        if chosen.size() >= spawn_point_count:
            break
        var far_enough := true
        for k in chosen:
            if Vector2(c - k).length() < float(spawn_min_spacing):
                far_enough = false
                break
        if far_enough:
            chosen.append(c)

    for i in chosen.size():
        var marker := Marker2D.new()
        marker.name = "Spawn%d" % (i + 1)
        holder.add_child(marker)
        if Engine.is_editor_hint():
            marker.owner = get_tree().edited_scene_root
        marker.global_position = tile_map_layer.to_global(tile_map_layer.map_to_local(chosen[i]))

    print("Titik spawn dibuat: %d dari %d ubin layak." % [chosen.size(), open_cells.size()])


# Ubin lantai yang tetangga orthogonalnya juga lantai: badan slime (circle radius 8)
# tidak boleh menumpuk dinding pada saat di-spawn.
func _is_open_cell(cell: Vector2i) -> bool:
    for d in _NEIGHBOR_DIRS:
        var c: Vector2i = cell + d
        if tile_map_layer.get_cell_source_id(c) == -1:
            return false
        var td := tile_map_layer.get_cell_tile_data(c)
        if td == null or td.get_collision_polygons_count(0) > 0:
            return false
    return true
