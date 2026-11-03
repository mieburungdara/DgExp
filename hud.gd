extends CanvasLayer

## HUD bertema: bar status di atas, dock aksi di bawah. Semua kontrol dibuat di
## kode supaya tata letaknya bisa diukur (lihat report_geometry), bukan
## dikira-kira di inspector — versi lama punya 10 tombol yang butuh 690 px di
## wadah 429 px dan menutupi arena permainan.

signal grind_pressed
signal target_pressed(monster: Node)

const ICON_DIR := "res://art/ui/"
const CHIP_W := 112.0
const CHIP_H := 52.0
const CHIP_COLS := 5
const MAX_CHIPS := 10

var _map_icon: TextureRect
var _map_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _coins_label: Label
var _kills_label: Label
var _header: Label
var _chips: GridContainer
var _monsters: Array[Node] = []
var _chip_cache := {}


# CanvasLayer tidak punya properti theme (itu properti Control), jadi tema
# dipasang ke dua akar kontrol dan diwariskan ke seluruh anak mereka.
var _theme: Theme


func _ready() -> void:
    layer = 2
    _theme = UiTheme.build()

    _build_top_bar()
    _build_dock()


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
    dock.offset_top = -168.0
    dock.offset_right = -8.0
    dock.offset_bottom = -8.0
    add_child(dock)

    var row := HBoxContainer.new()
    row.name = "Row"
    dock.add_child(row)

    var grind := Button.new()
    grind.text = "GRIND"
    grind.icon = _tex("target")
    grind.expand_icon = false
    grind.custom_minimum_size = Vector2(110, 110)
    grind.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE)
    grind.pressed.connect(func() -> void: grind_pressed.emit())
    row.add_child(grind)

    var column := VBoxContainer.new()
    column.name = "TargetColumn"
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(column)

    _header = Label.new()
    _header.add_theme_font_size_override("font_size", UiTheme.FONT_CAPTION)
    _header.add_theme_color_override("font_color", UiTheme.MUTED)
    column.add_child(_header)

    _chips = GridContainer.new()
    _chips.name = "Chips"
    _chips.columns = CHIP_COLS
    column.add_child(_chips)


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


func set_monsters(monsters: Array) -> void:
    _monsters.clear()
    for m in monsters:
        _monsters.append(m)
    _rebuild_chips()


func _rebuild_chips() -> void:
    for child in _chips.get_children():
        _chips.remove_child(child)
        child.queue_free()
    _chip_cache.clear()

    var shown := mini(_monsters.size(), MAX_CHIPS)
    for i in range(shown):
        var m := _monsters[i]
        var chip := Button.new()
        chip.name = "Chip%d" % (i + 1)
        chip.custom_minimum_size = Vector2(CHIP_W, CHIP_H)
        chip.icon = _tex("skull")
        chip.expand_icon = false
        chip.add_theme_font_size_override("font_size", UiTheme.FONT_CAPTION)
        var bound := m
        chip.pressed.connect(func() -> void:
            if is_instance_valid(bound):
                target_pressed.emit(bound))
        _chips.add_child(chip)
        _chip_cache[chip.get_instance_id()] = m

    var extra := _monsters.size() - shown
    var caption := "SASARAN %d" % _monsters.size()
    if extra > 0:
        caption += "  (+%d di luar layar)" % extra
    _header.text = caption
    _refresh_chip_labels()


## Teks chip diperbarui terpisah dari pembuatannya: HP monster berubah terus,
## tapi membangun ulang tombol tiap 0,5 detik membuang koneksi dan membebaskan
## node yang sedang dipegang player.
func _refresh_chip_labels() -> void:
    for child in _chips.get_children():
        var chip := child as Button
        if chip == null:
            continue
        var m = _chip_cache.get(chip.get_instance_id())
        if m == null or not is_instance_valid(m):
            chip.text = "—"
            continue
        chip.text = "%s %d" % [_short_name(m.get("monster_name")), int(m.get("hp"))]


func _short_name(full) -> String:
    if full == null:
        return "Monster"
    var parts := String(full).split(" ")
    return String(parts[0]).substr(0, 5)


func _process(_delta: float) -> void:
    _refresh_chip_labels()


func chip_count() -> int:
    return _chips.get_child_count()


func caption() -> String:
    return _header.text


func report_geometry() -> void:
    var vp: Vector2 = get_viewport().get_visible_rect().size
    var top := get_node("TopBar") as Control
    var dock := get_node("Dock") as Control
    print("viewport=%.0fx%.0f" % [vp.x, vp.y])
    print("  TopBar  y=%.0f..%.0f tinggi=%.0f" % [top.position.y, top.position.y + top.size.y, top.size.y])
    print("  Dock    y=%.0f..%.0f tinggi=%.0f" % [dock.position.y, dock.position.y + dock.size.y, dock.size.y])
    var count: int = _chips.get_child_count()
    var rows: int = int(ceilf(count / float(CHIP_COLS)))
    print("  chip    %d x %.0f px, %d baris -> baris penuh butuh lebar %.0f, tersedia %.0f" % [
        count, CHIP_W, rows, (CHIP_W + 6.0) * CHIP_COLS, _chips.size.x])
    print("  arena bersih = %.0f px (%.1f%% dari tinggi)" % [
        dock.position.y - (top.position.y + top.size.y),
        100.0 * (dock.position.y - (top.position.y + top.size.y)) / vp.y])
    print("  header='%s'" % _header.text)
