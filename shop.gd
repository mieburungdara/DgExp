extends CanvasLayer

## Panel toko pedagang. Item didefinisikan sebagai data, jadi menambah barang
## baru satu baris di ITEMS dan tidak perlu menyentuh tata letak.

const PRICE_HEAL := 30
const ATTACK_GAIN := 2
const ATTACK_STEP := 25
const ICON_DIR := "res://art/ui/"

const ITEMS := [
    {"id": "heal", "icon": "heart", "name": "Pulihkan HP",
        "desc": "Isi penuh nyawa karakter", "price": PRICE_HEAL},
    {"id": "attack", "icon": "sword", "name": "Serangan +%d" % ATTACK_GAIN,
        "desc": "Naik permanen, harga ikut naik tiap beli", "price": 50},
]

var _rows := {}          # id -> {price, buy, purse}
var _prices := {}        # id -> harga sekarang
var _status: Label


func _ready() -> void:
    layer = 6
    visible = false
    for item in ITEMS:
        _prices[item["id"]] = int(item["price"])
    _build()


func _build() -> void:
    var panel := PanelContainer.new()
    panel.name = "ShopPanel"
    panel.theme = UiTheme.build()
    panel.custom_minimum_size = Vector2(470, 0)
    add_child(panel)

    var box := VBoxContainer.new()
    panel.add_child(box)

    var head := HBoxContainer.new()
    box.add_child(head)

    var title := Label.new()
    title.text = "Pedagang Desa"
    title.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE)
    title.add_theme_color_override("font_color", UiTheme.GOLD)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)

    var close_button := Button.new()
    close_button.icon = _tex("close")
    close_button.flat = true
    close_button.tooltip_text = "Tutup (Esc)"
    close_button.pressed.connect(close_panel)
    head.add_child(close_button)

    var purse := HBoxContainer.new()
    box.add_child(purse)
    purse.add_child(_icon("coin"))
    var purse_label := Label.new()
    purse_label.name = "PurseLabel"
    purse_label.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
    purse.add_child(purse_label)

    for item in ITEMS:
        box.add_child(_make_row(item, purse_label))

    _status = Label.new()
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.custom_minimum_size = Vector2(430, 40)
    _status.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
    _status.add_theme_color_override("font_color", UiTheme.MUTED)
    box.add_child(_status)

    # Tidak dipanggil di sini: _ready anak autoload berjalan sebelum _ready
    # induknya, jadi Game.player belum terisi.
    Game.coins_changed.connect(func(_v: int) -> void: _refresh())


func _make_row(item: Dictionary, purse_label: Label) -> Control:
    var row := PanelContainer.new()
    var line := HBoxContainer.new()
    row.add_child(line)

    line.add_child(_icon(item["icon"]))

    var text := VBoxContainer.new()
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var name_label := Label.new()
    name_label.text = item["name"]
    name_label.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
    text.add_child(name_label)
    var desc := Label.new()
    desc.text = item["desc"]
    desc.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
    desc.add_theme_color_override("font_color", UiTheme.MUTED)
    text.add_child(desc)
    line.add_child(text)

    var price := Label.new()
    price.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
    line.add_child(price)

    var buy := Button.new()
    buy.text = "Beli"
    buy.custom_minimum_size = Vector2(86, 44)
    var id := String(item["id"])
    buy.pressed.connect(func() -> void: _buy(id))
    line.add_child(buy)

    _rows[id] = {"price": price, "buy": buy, "purse": purse_label}
    return row


func _refresh() -> void:
    for id in _rows:
        var r: Dictionary = _rows[id]
        var cost: int = _prices[id]
        var enough: bool = Game.coins >= cost
        r["price"].text = "%d" % cost
        r["price"].add_theme_color_override(
            "font_color", UiTheme.GOLD if enough else UiTheme.DANGER)
        r["buy"].disabled = not enough
        if id == "heal":
            var p: Node = Game.player
            if p != null and p.hp >= p.max_hp:
                r["buy"].disabled = true
        r["purse"].text = "Kamu punya %d koin" % Game.coins


func _buy(id: String) -> void:
    var cost: int = _prices[id]
    if Game.coins < cost:
        _status.text = "Koin kurang: butuh %d, kamu %d." % [cost, Game.coins]
        _refresh()
        return
    var p: Node = Game.player
    if id == "heal":
        if p.hp >= p.max_hp:
            _status.text = "HP sudah penuh."
            _refresh()
            return
        Game.spend_coins(cost)
        p.hp = p.max_hp
        p.hp_bar.update_hp(p.hp)
        p.hp_changed.emit(p.hp, p.max_hp)
        _status.text = "Nyawa dipulihkan."
    else:
        Game.spend_coins(cost)
        p.attack_damage += ATTACK_GAIN
        _prices[id] = cost + ATTACK_STEP
        _status.text = "Serangan naik jadi %d. Harga berikutnya %d koin." % [
            p.attack_damage, _prices[id]]
    _refresh()


func _icon(name: String) -> TextureRect:
    var tr := TextureRect.new()
    tr.texture = _tex(name)
    tr.custom_minimum_size = Vector2(34, 34)
    tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return tr


func _tex(name: String) -> Texture2D:
    return load(ICON_DIR + name + ".png") as Texture2D


func _center(panel: Control) -> void:
    var vp: Vector2 = get_viewport().get_visible_rect().size
    panel.position = Vector2((vp.x - panel.size.x) * 0.5, (vp.y - panel.size.y) * 0.5)


func open() -> void:
    visible = true
    _status.text = "Barang hari ini."
    _refresh()
    # Dijsentuhkan ke resized saja tidak cukup: panel sudah selesai diukur saat
    # dibangun, jadi sinyalnya sudah lewat dan posisinya tertinggal di 0,0.
    var panel := get_node("ShopPanel") as Control
    panel.reset_size()
    call_deferred("_center", panel)


func close_panel() -> void:
    visible = false


func price_of(id: String) -> int:
    return _prices[id]


func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if event.is_action_pressed("ui_cancel"):
        close_panel()
        get_viewport().set_input_as_handled()
