class_name GridPath
extends RefCounted

# Pathfinding langsung di atas TileMapLayer, tanpa navmesh perantara.
#
# Satu unit pencarian = satu ubin. Sebuah ubin layak dilalui kalau SELURUH kotak
# badan karakter yang ditempatkan di pusatnya masih berada di ubin lantai. Aturan
# "tetangga harus lantai" lebih kasar dan menutup lorong selebar 2 ubin, jadi tidak
# dipakai. Potongan sudut yang agresif dicegat nanti oleh validasi sapuan, bukan by
# membuang ubin dari grid.

const STEP := 1000            # biaya satu langkah lurus (integer, untuk bucket queue)
const DIAG_STEP := 1414       # biaya satu langkah diagonal
const BUCKET := 1000          # lebar ember antrean dalam satuan biaya
const SWEEP_STEP := 8.0       # jarak sampling validasi sapuan (px)
var _dx := PackedInt32Array([1, -1, 0, 0, 1, 1, -1, -1])
var _dy := PackedInt32Array([0, 0, 1, -1, 1, -1, 1, -1])

var _layer: TileMapLayer
var _clearance := Vector2(6, 6)
var _tile_size := Vector2(16, 16)
var _origin := Vector2.ZERO
var _base := Vector2i.ZERO
var _w := 0
var _h := 0
var _floor := PackedByteArray()     # 1 = ubin lantai (tidak punya polygon collision)
var _walk := PackedByteArray()      # 1 = ubin lantai yang muat badan
var _g := PackedInt32Array()
var _parent := PackedInt32Array()
var _seen := PackedInt32Array()
var _closed_at := PackedInt32Array()
var _epoch := 0
var _buckets: Array[PackedInt32Array] = []
var _touched: Array[int] = []
var _min_bucket := 0


func build(layer: TileMapLayer, clearance: Vector2) -> void:
    _layer = layer
    _clearance = clearance
    _walk = PackedByteArray()
    _floor = PackedByteArray()
    if _layer == null:
        return

    var step_x: Vector2 = _layer.map_to_local(Vector2i(1, 0)) - _layer.map_to_local(Vector2i(0, 0))
    var step_y: Vector2 = _layer.map_to_local(Vector2i(0, 1)) - _layer.map_to_local(Vector2i(0, 0))
    _tile_size = Vector2(step_x.x, step_y.y)
    _origin = _layer.map_to_local(Vector2i(0, 0)) - _tile_size * 0.5

    var used: Rect2i = _layer.get_used_rect()
    _base = used.position
    _w = used.size.x
    _h = used.size.y
    var total := maxi(_w * _h, 1)
    _floor.resize(total)
    _floor.fill(0)
    _walk.resize(total)
    _walk.fill(0)
    _g.resize(total)
    _parent.resize(total)
    _seen.resize(total)
    _seen.fill(-1)
    _closed_at.resize(total)
    _closed_at.fill(-1)
    _epoch = 0

    # Ember antrean dibatasi diagonal peta, bukan jumlah sel.
    var bucket_count := int(float(_w + _h) * float(STEP) / float(BUCKET)) + 8
    _buckets.resize(bucket_count)
    for bi in bucket_count:
        _buckets[bi] = PackedInt32Array()

    var floor_cells: Array[Vector2i] = []
    for cell in _layer.get_used_cells():
        var td := _layer.get_cell_tile_data(cell)
        if td == null or td.get_collision_polygons_count(0) > 0:
            continue
        var i := _index(cell)
        if i >= 0:
            _floor[i] = 1
            floor_cells.append(cell)

    for cell in floor_cells:
        var i := _index(cell)
        if _body_clear(_layer.to_global(_cell_center(cell))):
            _walk[i] = 1


func is_ready() -> bool:
    return _layer != null and _w > 0 and _walk.count(1) > 0


# True kalau titik dunia berada di dalam rect grid yang sedang dibangun. Dipakai
# untuk menolak target yang ternyata berada di peta lain.
func contains_world(world: Vector2) -> bool:
    return is_ready() and _index(_cell_of(world)) >= 0


func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
    if not is_ready():
        return PackedVector2Array()
    var start := _nearest_walkable(_cell_of(from_world))
    var goal := _nearest_walkable(_cell_of(to_world))
    if start < 0 or goal < 0:
        return PackedVector2Array()
    if start == goal:
        return PackedVector2Array([to_world])

    _epoch += 1
    _touched.clear()
    _min_bucket = 0
    var glx := goal % _w
    var gly := int(goal / _w)
    _g[start] = 0
    _parent[start] = start
    _seen[start] = _epoch
    var slx := start % _w
    var sly := int(start / _w)
    _push(start, _h_cost(slx, sly, glx, gly))
    var found := false

    # Aritmetika indeks di-inline. Pada grid 340x420 loop ini berjalan belasan ribu
    # kali per pencarian dan biaya pemanggilan fungsi GDScript dominan (terukur:
    # 52 ms -> jauh lebih kecil setelah inline).
    while true:
        var current := _pop()
        if current < 0:
            break
        if _closed_at[current] == _epoch:
            continue
        _closed_at[current] = _epoch
        if current == goal:
            found = true
            break
        var lx := current % _w
        var ly := int(current / _w)
        var base_cost: int = _g[current]
        for k in range(8):
            var nlx := lx + _dx[k]
            var nly := ly + _dy[k]
            if nlx < 0 or nly < 0 or nlx >= _w or nly >= _h:
                continue
            var next := nly * _w + nlx
            if _walk[next] == 0:
                continue
            var step_cost: int = base_cost + STEP
            if k > 3:
                # jangan memotong sudut dinding secara diagonal
                if _walk[ly * _w + nlx] == 0 or _walk[nly * _w + lx] == 0:
                    continue
                step_cost = base_cost + DIAG_STEP
            if _seen[next] == _epoch and _g[next] <= step_cost:
                continue
            _g[next] = step_cost
            _parent[next] = current
            _seen[next] = _epoch
            _push(next, step_cost + _h_cost(nlx, nly, glx, gly))

    for b in _touched:
        _buckets[b].resize(0)
    if not found:
        return PackedVector2Array()

    var cells: Array[Vector2i] = []
    var node := goal
    while true:
        cells.append(_cell_of_index(node))
        var par: int = _parent[node]
        if par == node:
            break
        node = par
    cells.reverse()

    var points := PackedVector2Array()
    for c in cells:
        points.append(_layer.to_global(_cell_center(c)))
    return _string_pull(_collapse(points))


func _h_cost(lx: int, ly: int, glx: int, gly: int) -> int:
    var dx := absi(lx - glx)
    var dy := absi(ly - gly)
    # tie-break 0,1%: di antara node berbiaya sama, yang lebih dekat tujuan didahulukan
    return int((maxf(dx, dy) + 0.41421356 * minf(dx, dy)) * float(STEP) * 1.001)


func _push(key: int, f: int) -> void:
    var b := clampi(int(f / BUCKET), 0, _buckets.size() - 1)
    if _buckets[b].size() == 0:
        _touched.append(b)
    _buckets[b].append(key)
    if b < _min_bucket:
        _min_bucket = b


func _pop() -> int:
    while _min_bucket < _buckets.size():
        var bucket := _buckets[_min_bucket]
        while bucket.size() > 0:
            var key: int = bucket[bucket.size() - 1]
            bucket.remove_at(bucket.size() - 1)
            return key
        _min_bucket += 1
    return -1


func _index(cell: Vector2i) -> int:
    var lx := cell.x - _base.x
    var ly := cell.y - _base.y
    if lx < 0 or ly < 0 or lx >= _w or ly >= _h:
        return -1
    return ly * _w + lx


func _cell_of_index(i: int) -> Vector2i:
    return _base + Vector2i(i % _w, int(i / _w))


func _cell_of(world: Vector2) -> Vector2i:
    var local := _layer.to_local(world)
    return Vector2i(
        floori((local.x - _origin.x) / _tile_size.x),
        floori((local.y - _origin.y) / _tile_size.y))


func _cell_center(cell: Vector2i) -> Vector2:
    return _origin + (Vector2(cell) + Vector2(0.5, 0.5)) * _tile_size


func _nearest_walkable(cell: Vector2i) -> int:
    var i := _index(cell)
    if i >= 0 and _walk[i] == 1:
        return i
    for radius in range(1, 6):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if max(absi(dx), absi(dy)) != radius:
                    continue
                var candidate := _index(cell + Vector2i(dx, dy))
                if candidate >= 0 and _walk[candidate] == 1:
                    return candidate
    return -1


# Kotak badan di titik dunia ini harus seluruhnya berada di atas ubin lantai.
func _body_clear(center_world: Vector2) -> bool:
    var local := _layer.to_local(center_world)
    var r := Rect2(local - _clearance, _clearance * 2.0)
    var c0x := floori((r.position.x - _origin.x) / _tile_size.x)
    var c0y := floori((r.position.y - _origin.y) / _tile_size.y)
    var c1x := floori((r.end.x - _origin.x - 0.001) / _tile_size.x)
    var c1y := floori((r.end.y - _origin.y - 0.001) / _tile_size.y)
    for cy in range(c0y, c1y + 1):
        for cx in range(c0x, c1x + 1):
            var i := _index(Vector2i(cx, cy))
            if i < 0 or _floor[i] == 0:
                return false
    return true


# Titik grid yang segaris dibuang dulu; validasi sapuan yang mahal hanya perlu
# dijalankan pada titik belok.
func _collapse(points: PackedVector2Array) -> PackedVector2Array:
    if points.size() < 3:
        return points
    var kept := PackedVector2Array([points[0]])
    for i in range(1, points.size() - 1):
        var a: Vector2 = kept[kept.size() - 1]
        var b: Vector2 = points[i]
        var c: Vector2 = points[i + 1]
        if (b - a) != (c - b):
            kept.append(b)
    kept.append(points[points.size() - 1])
    return kept


func _string_pull(points: PackedVector2Array) -> PackedVector2Array:
    if points.size() < 3:
        return points
    var kept := PackedVector2Array([points[0]])
    var i := 1
    while i < points.size():
        var best := i
        while best + 1 < points.size() and _sweep_clear(kept[kept.size() - 1], points[best + 1]):
            best += 1
        kept.append(points[best])
        i = best + 1
    return kept


func _sweep_clear(a: Vector2, b: Vector2) -> bool:
    var seg := b - a
    var dist := seg.length()
    if dist <= 0.001:
        return true
    var steps := ceili(dist / SWEEP_STEP)
    for s in range(1, steps):
        if not _body_clear(a + seg * (s / float(steps))):
            return false
    return _body_clear(b)
