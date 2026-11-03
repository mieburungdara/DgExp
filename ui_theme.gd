class_name UiTheme
extends RefCounted

## Tema gelap satu-satunya untuk seluruh UI. Dibangun dari kode, bukan file
## .tres, supaya token warna tinggal satu tempat dan tidak bisa berbeda antara
## HUD, dock, dan panel toko.

const BG := Color(0.086, 0.098, 0.129, 0.92)
const BG_SOFT := Color(0.125, 0.141, 0.180, 0.94)
const EDGE := Color(0.302, 0.263, 0.180)
const GOLD := Color(0.886, 0.702, 0.231)
const TEXT := Color(0.929, 0.922, 0.878)
const MUTED := Color(0.620, 0.627, 0.616)
const DANGER := Color(0.851, 0.310, 0.278)
const GOOD := Color(0.420, 0.722, 0.361)

const FONT_CAPTION := 17
const FONT_TITLE := 30
const FONT_BODY := 21
const FONT_SMALL := 15


static func build() -> Theme:
    var t := Theme.new()

    var panel := box(BG, EDGE, 4, 10)
    t.set_stylebox("panel", "PanelContainer", panel)
    t.set_stylebox("panel", "Panel", panel)

    t.set_stylebox("normal", "Button", box(BG_SOFT, EDGE, 3, 10, 6))
    t.set_stylebox("hover", "Button", box(Color(0.19, 0.22, 0.28, 0.96), GOLD, 3, 10, 6))
    t.set_stylebox("pressed", "Button", box(Color(0.07, 0.08, 0.10, 0.96), GOLD, 3, 10, 6))
    t.set_stylebox("disabled", "Button", box(Color(0.10, 0.11, 0.13, 0.80), Color(0.20, 0.20, 0.22), 3, 10, 6))
    t.set_color("font_color", "Button", TEXT)
    t.set_color("font_hover_color", "Button", GOLD)
    t.set_color("font_pressed_color", "Button", GOLD)
    t.set_color("font_disabled_color", "Button", MUTED)
    t.set_font_size("font_size", "Button", FONT_BODY)

    t.set_color("font_color", "Label", TEXT)
    t.set_font_size("font", "Label", FONT_BODY)

    var bar_bg := box(Color(0.05, 0.06, 0.08, 0.95), Color(0.22, 0.20, 0.15), 2, 2, 2)
    t.set_stylebox("background", "ProgressBar", bar_bg)
    t.set_stylebox("fill", "ProgressBar", box(GOLD, Color(0.35, 0.26, 0.08), 2, 2, 2))
    t.set_color("font_color", "ProgressBar", TEXT)
    t.set_font_size("font", "ProgressBar", FONT_SMALL)

    t.set_constant("separation", "HBoxContainer", 8)
    t.set_constant("separation", "VBoxContainer", 8)
    t.set_constant("h_separation", "GridContainer", 6)
    t.set_constant("v_separation", "GridContainer", 6)

    return t


static func box(bg: Color, border: Color, radius: int, margin: int, vmargin: int = -1) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.border_color = border
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(radius)
    sb.content_margin_left = margin
    sb.content_margin_right = margin
    sb.content_margin_top = margin if vmargin < 0 else vmargin
    sb.content_margin_bottom = margin if vmargin < 0 else vmargin
    return sb


## Bar HP memakai warna yang berubah menurut sisa nyawa, jadi tidak ikut tema
## umum.
static func hp_fill(ratio: float) -> StyleBoxFlat:
    var col := GOOD
    if ratio < 0.25:
        col = DANGER
    elif ratio < 0.6:
        col = Color(0.90, 0.62, 0.20)
    return box(col, Color(0, 0, 0, 0.5), 2, 2, 2)
