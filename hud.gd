extends CanvasLayer

## HUD bertema: bar status di atas, satu aksi di bawah. Daftar monster sengaja
## tidak ditampilkan — yang penting hanya "sasaran sekarang" satu baris, dan
## GRIND yang mencari serta menyerang sasaran terdekat. Semua kontrol dibangun
## dari kode supaya tata letaknya bisa diukur (report_geometry), bukan
## dikira-kira di inspector.

signal grind_pressed

const ICON_DIR := "res://art/ui/"

var _map_icon: TextureRect
var _map_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _coins_label: Label
var _kills_label: Label
var _status: Label
var _status_until := 0.0
var _compass: TextureRect
var _fade: ColorRect
var _flash: ColorRect
var _toasts: Array[Dictionary] = []
var _toast_root: Control

# CanvasLayer tidak punya properti theme (itu properti Control), jadi tema
# dipasang ke dua akar kontrol dan diwariskan ke seluruh anak mereka.
var _theme: Theme


func _ready() -> void:
    layer = 2
    _theme = UiTheme.build()

    _build_top_bar()
    _build_dock()
    # Toast dibuat sebelum overlay: label toast ditambahkan sebagai anak dari
    # node ini, jadi WarpFade yang dibuat belakangan selalu menutupinya.
    _toast_root = Control.new()
    _toast_root.name = "Toasts"
    _toast_root.theme = _theme
    _toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_toast_root)
    _full_rect(_toast_root)
    _build_overlay()


func _build_top_bar() -> void:
    var top := PanelContainer.new()
    top.name = "TopBar"
    top.theme = _theme
    top.set_anchors_preset(Control.PRESET_TOP_WIDE)
    top.offset_left = 8.0
    top.offset_top = 8.0
    top.offset_right = -8.0
    top.offset_bottom = 74.0
    add_child(top)

    var row := HBoxContainer.new()
    row.name = "Row"
    top.add_child(row)

    _map_icon = TextureRect.new()
    _map_icon.custom_minimum_size = Vector2(40, 40)
    _map_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _map_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    row.add_child(_map_icon)

    _map_label = Label.new()
    _map_label.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE)
    _map_label.add_theme_color_override("font_color", UiTheme.GOLD)
    _map_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(_map_label)

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(spacer)

    row.add_child(_icon("heart"))

    _hp_bar = ProgressBar.new()
    _hp_bar.custom_minimum_size = Vector2(170, 30)
    _hp_bar.show_percentage = false
    _hp_bar.max_value = 100
    row.add_child(_hp_bar)

    _hp_label = Label.new()
    _hp_label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
    row.add_child(_hp_label)

    row.add_child(_icon("coin"))
    _coins_label = Label.new()
    _coins_label.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
    _coins_label.add_theme_color_override("font_color", UiTheme.GOLD)
    _coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(_coins_label)

    row.add_child(_icon("skull"))
    _kills_label = Label.new()
    _kills_label.add_theme_font_size_override("font_size", UiTheme.FONT_CAPTION)
    _kills_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(_kills_label)


func _build_dock() -> void:
    var dock := PanelContainer.new()
    dock.name = "Dock"
    dock.theme = _theme
    dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    dock.offset_left = 8.0
    dock.offset_top = -120.0
    dock.offset_right = -8.0
    dock.offset_bottom = -8.0
    add_child(dock)

    var row := HBoxContainer.new()
    row.name = "Row"
    dock.add_child(row)

    var grind := Button.new()
    grind.name = "Grind"
    grind.text = "GRIND"
    grind.icon = _tex("target")
    grind.expand_icon = false
    grind.custom_minimum_size = Vector2(150, 92)
    grind.tooltip_text = "Cari dan serang monster terdekat di peta ini"
    grind.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE)
    grind.pressed.connect(func() -> void: grind_pressed.emit())
    row.add_child(grind)

    _status = Label.new()
    _status.name = "Status"
    _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.add_theme_font_size_override("font_size", UiTheme.FONT_CAPTION)
    _status.add_theme_color_override("font_color", UiTheme.MUTED)
    row.add_child(_status)

    _compass = TextureRect.new()
    _compass.name = "Compass"
    _compass.texture = _tex("arrow")
    _compass.custom_minimum_size = Vector2(56, 56)
    _compass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _compass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _compass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _compass.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _compass.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    # Rotasi terjadi terhadap pivot; tanpa ini panah berayun keluar dock
    # karena pivot default ada di sudut kiri-atas.
    _compass.pivot_offset = Vector2(28, 28)
    _compass.visible = false
    row.add_child(_compass)


## Layer umpan balik: vignette saat kena serang, toast koin, dan fade saat
## warp. Semua di CanvasLayer ini supaya tidak ikut terpengaruh zoom kamera.
func _build_overlay() -> void:
    _flash = ColorRect.new()
    _flash.name = "DamageFlash"
    _flash.color = Color(0.85, 0.12, 0.10, 0.0)
    _flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_flash)
    _full_rect(_flash)

    _fade = ColorRect.new()
    _fade.name = "WarpFade"
    _fade.color = Color(0.0, 0.0, 0.0, 0.0)
    _fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_fade)
    _full_rect(_fade)


func _full_rect(c: Control) -> void:
    c.set_anchors_preset(Control.PRESET_FULL_RECT)
    c.offset_left = 0.0
    c.offset_top = 0.0
    c.offset_right = 0.0
    c.offset_bottom = 0.0


func _icon(name: String) -> TextureRect:
    var tr := TextureRect.new()
    tr.texture = _tex(name)
    tr.custom_minimum_size = Vector2(30, 30)
    tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return tr


func _tex(name: String) -> Texture2D:
    return load(ICON_DIR + name + ".png") as Texture2D


func set_map(title: String, icon: String) -> void:
    _map_label.text = title
    _map_icon.texture = _tex(icon)
    visible = true


func set_coins(value: int) -> void:
    _coins_label.text = str(value)


func set_kills(value: int) -> void:
    _kills_label.text = str(value)


func set_hp(hp: int, max_hp: int) -> void:
    _hp_bar.max_value = max_hp
    _hp_bar.value = hp
    _hp_bar.add_theme_stylebox_override("fill", UiTheme.hp_fill(float(hp) / float(max_hp)))
    _hp_label.text = "%d/%d" % [hp, max_hp]


## Pesan singkat (mis. "tidak ada sasaran") yang ditimpa baris sasaran lagi
## setelah beberapa detik.
func flash(message: String, seconds: float = 2.5) -> void:
    _status.text = message
    _status_until = Time.get_ticks_msec() / 1000.0 + seconds


func status_text() -> String:
    return _status.text


## Toast singkat di posisi dunia (mis. "+10 koin" tempat monster jatuh).
func toast(text: String, world_pos: Vector2, color: Color = UiTheme.GOLD) -> void:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.9))
    label.add_theme_constant_override("outline_size", 6)
    _toast_root.add_child(label)
    _toasts.append({"node": label, "world": world_pos, "age": 0.0})
    label.position = world_to_view(world_pos)


## Posisi dunia -> koordinat layar HUD. get_canvas_transform() sudah
## memetakan dunia ke layar; memakai affine_inverse() malah membalik
## arahnya sehingga toast jatuh jauh di luar viewport.
func world_to_view(world_pos: Vector2) -> Vector2:
    return get_viewport().get_canvas_transform() * world_pos


## Kedip vignette merah; dipanggil shell saat HP player berkurang.
func flash_damage() -> void:
    _flash.color.a = 0.42


func fade_out(seconds: float = 0.16) -> void:
    _fade.visible = true
    var tween := create_tween()
    tween.tween_property(_fade, "color:a", 1.0, seconds)


func fade_in(seconds: float = 0.22) -> void:
    var tween := create_tween()
    tween.tween_property(_fade, "color:a", 0.0, seconds)
    tween.tween_callback(_fade.hide)


func fade_alpha() -> float:
    return _fade.color.a


## Baris sasaran dibaca sendiri dari player tiap frame: jaraknya berubah terus
## saat mengejar, dan memberi tahunya lewat sinyal berarti shell harus tahu
## setiap langkah player.
func _process(delta: float) -> void:
    _step_toasts(delta)
    _step_compass()
    if _flash.color.a > 0.0:
        _flash.color.a = maxf(0.0, _flash.color.a - delta * 2.6)

    if _status_until > 0.0:
        if float(Time.get_ticks_msec()) / 1000.0 < _status_until:
            return
        _status_until = 0.0

    var game := get_parent()
    var p = game.get("player")
    if p == null:
        _status.text = ""
        return
    var m = p.get("target_monster")
    if m == null or not is_instance_valid(m):
        var here: int = game.call("monsters_here")
        if here > 0:
            _status.text = "%d monster di peta ini — tekan GRIND." % here
        else:
            _status.text = "Peta ini aman, tidak ada sasaran."
        _status.add_theme_color_override("font_color", UiTheme.MUTED)
        return
    var dist: float = p.global_position.distance_to(m.global_position)
    _status.text = "Sasaran: %s  HP %d  jarak %.0f px" % [
        String(m.get("monster_name")), int(m.get("hp")), dist]
    _status.add_theme_color_override("font_color", UiTheme.GOLD if dist > 24.0 else UiTheme.GOOD)


func _step_toasts(delta: float) -> void:
    var keep: Array[Dictionary] = []
    for t in _toasts:
        var node: Label = t["node"]
        if not is_instance_valid(node):
            continue
        t["age"] += delta
        node.modulate.a = clampf(1.0 - t["age"] / 1.1, 0.0, 1.0)
        # Posisi dunia disimpan, view dihitung ulang tiap frame: toast tetap
        # menempel di tempat monster jatuh walaupun kamera bergerak.
        var rise: float = 34.0 * float(t["age"])
        node.position = world_to_view(t["world"] - Vector2(0.0, rise / 3.0))
        if t["age"] < 1.1:
            keep.append(t)
        else:
            node.queue_free()
    _toasts = keep


func _step_compass() -> void:
    var game := get_parent()
    var p = game.get("player")
    if p == null:
        _compass.visible = false
        return
    var m = p.get("target_monster")
    if m == null or not is_instance_valid(m):
        _compass.visible = false
        return
    _compass.visible = true
    # CanvasLayer tidak ikut zoom kamera, jadi arah harus diputar terhadap
    # rotasi kamera: tanpa ini kompas berputar salah saat kamera di-zoom/rotasi.
    var camera := get_viewport().get_camera_2d()
    var cam_rot: float = camera.global_rotation if camera != null else 0.0
    # Ikon menghadap ke atas, jadi 90 derajat harus dikoreksi.
    _compass.rotation = (m.global_position - p.global_position).angle() - cam_rot + PI * 0.5


## Diuji dari harness: sudut panah harus sama dengan arah dunia ke sasaran,
## dikurangi rotasi kamera.
func compass_angle() -> float:
    return _compass.rotation


func report_geometry() -> void:
    var vp: Vector2 = get_viewport().get_visible_rect().size
    var top := get_node("TopBar") as Control
    var dock := get_node("Dock") as Control
    print("viewport=%.0fx%.0f" % [vp.x, vp.y])
    print("  TopBar  y=%.0f..%.0f tinggi=%.0f" % [top.position.y, top.position.y + top.size.y, top.size.y])
    print("  Dock    y=%.0f..%.0f tinggi=%.0f" % [dock.position.y, dock.position.y + dock.size.y, dock.size.y])
    print("  arena bersih = %.0f px (%.1f%% dari tinggi)" % [
        dock.position.y - (top.position.y + top.size.y),
        100.0 * (dock.position.y - (top.position.y + top.size.y)) / vp.y])
    print("  status='%s'" % _status.text)
