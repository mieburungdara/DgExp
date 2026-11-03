extends CanvasLayer

## Panel toko pedagang. Dibangun dari kode supaya satu file memuat seluruh
## tata letaknya; dibuka oleh ShopTrigger di lapak desa dan ditutup tombol
## Tutup atau Esc.

const PRICE_HEAL := 30
const PRICE_ATTACK_FIRST := 50
const PRICE_ATTACK_STEP := 25
const ATTACK_GAIN := 2

var _panel: PanelContainer
var _status: Label
var _heal_button: Button
var _attack_button: Button
var _attack_price := PRICE_ATTACK_FIRST


func _ready() -> void:
    layer = 5
    visible = false

    _panel = PanelContainer.new()
    _panel.position = Vector2(200, 470)
    _panel.size = Vector2(320, 300)
    add_child(_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 10)
    _panel.add_child(box)

    var title := Label.new()
    title.text = "Pedagang Desa"
    title.add_theme_font_size_override("font_size", 30)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(title)

    _heal_button = Button.new()
    _heal_button.custom_minimum_size = Vector2(280, 64)
    _heal_button.text = "Pulihkan HP  (%d koin)" % PRICE_HEAL
    _heal_button.pressed.connect(_on_heal_pressed)
    box.add_child(_heal_button)

    _attack_button = Button.new()
    _attack_button.custom_minimum_size = Vector2(280, 64)
    _attack_button.text = "Serangan +%d  (%d koin)" % [ATTACK_GAIN, _attack_price]
    _attack_button.pressed.connect(_on_attack_pressed)
    box.add_child(_attack_button)

    var close_button := Button.new()
    close_button.custom_minimum_size = Vector2(280, 48)
    close_button.text = "Tutup"
    close_button.pressed.connect(close)
    box.add_child(close_button)

    _status = Label.new()
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.custom_minimum_size = Vector2(280, 60)
    _status.add_theme_font_size_override("font_size", 20)
    box.add_child(_status)

    # Tidak dipanggil di sini: _ready anak autoload berjalan sebelum _ready
    # induknya, jadi Game.player belum terisi.
    Game.coins_changed.connect(_refresh)


func open() -> void:
    visible = true
    _refresh(Game.coins)


func close() -> void:
    visible = false


func _refresh(coins: int) -> void:
    var p: Node = Game.player
    if p == null:
        return
    _status.text = "Koin: %d\nHP: %d/%d   Serangan: %d" % [
        coins, p.hp, p.max_hp, p.attack_damage]
    _heal_button.disabled = coins < PRICE_HEAL or p.hp >= p.max_hp
    _attack_button.disabled = coins < _attack_price


func _on_heal_pressed() -> void:
    var p: Node = Game.player
    if Game.coins < PRICE_HEAL:
        _status.text = "Koin kurang: butuh %d, kamu %d." % [PRICE_HEAL, Game.coins]
        return
    if p.hp >= p.max_hp:
        _status.text = "HP sudah penuh."
        return
    Game.spend_coins(PRICE_HEAL)
    p.hp = p.max_hp
    p.hp_bar.update_hp(p.hp)
    _refresh(Game.coins)


func _on_attack_pressed() -> void:
    var p: Node = Game.player
    if Game.coins < _attack_price:
        _status.text = "Koin kurang: butuh %d, kamu %d." % [_attack_price, Game.coins]
        return
    Game.spend_coins(_attack_price)
    p.attack_damage += ATTACK_GAIN
    _attack_price += PRICE_ATTACK_STEP
    _attack_button.text = "Serangan +%d  (%d koin)" % [ATTACK_GAIN, _attack_price]
    _refresh(Game.coins)


func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if event.is_action_pressed("ui_cancel"):
        close()
        get_viewport().set_input_as_handled()
