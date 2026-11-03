#!/usr/bin/env python3
"""Pembangkit aset desa: village_tiles.png + village_tileset.tres.

Satu sumber kebenaran untuk daftar tile: atlas PNG, tileset .tres, dan blok
konstanta GDScript yang dicetak ke stdout semuanya diambil dari TILES di bawah,
jadi indeks tidak bisa berbeda antar file. Jalankan:

    python tools/build_village_art.py

Aset sumber (hasil imagegen, disimpan di vibe_images/) dipakai sebagai master:
lembar ground/rumah dan lembar prop. Varian rumput, atap, cerobong, dan tile
bayangan diturunkan secara deterministik dari master itu.
"""
from PIL import Image, ImageDraw, ImageFilter
import os, sys

GROUND_SHEET = "vibe_images/village_tiles_raw_1793732478596_8fc33765.png"
PROPS_SHEET = "vibe_images/village_props_raw_1793734848434_aeb5da23.png"
OUT_ATLAS = "village_tiles.png"
OUT_TRES = "village_tileset.tres"

COLS = 8
CELL = 32  # ukuran tile di atlas; Godot menampilkannya pada grid 16 px

# (nama, solid?) — urutan menentukan indeks atlas.
TILES = [
    ("grass", False), ("grass_flower", False), ("grass_dark", False),
    ("grass_worn", False), ("grass_clover", False), ("dirt", False),
    ("cobble", False), ("water_edge", True),
    ("water", True), ("wall_wood", True), ("wall_plaster", True),
    ("wall_door", True), ("wall_window", True), ("roof_clay", True),
    ("roof_clay_ridge", True), ("roof_slate", True),
    ("roof_slate_ridge", True), ("roof_thatch", True),
    ("roof_thatch_ridge", True), ("roof_chimney", True), ("tree", True),
    ("pine", True), ("bush", True), ("bush_berry", True),
    ("fern", False), ("shrub_flower", True), ("well", True), ("fence", True),
    ("rock", True), ("barrel", True), ("crate", True), ("cart", True),
    ("haystack", True), ("lantern", True), ("signpost", True),
    ("flower_pot", True), ("stall", True), ("dummy", True), ("trough", True),
    ("logs", True), ("bench", True),
    ("shadow_bottom", False), ("shadow_right", False), ("shadow_corner", False),
    ("shadow_prop", False), ("empty", False),
]

NAME_TO_IDX = {name: i for i, (name, _) in enumerate(TILES)}

gmed_target = (140, 138, 53)  # diisi ulang di build(), dipakai soften_glow


def cell(sheet, col, row):
    return sheet.crop((col * 256, row * 256, (col + 1) * 256, (row + 1) * 256)).resize(
        (CELL, CELL), Image.BOX)


def shift(img, delta, mask=None):
    """Geser warna seluruh pixel (atau pixel yang lolos mask) sebesar delta."""
    out = Image.new("RGBA", img.size)
    px = img.convert("RGBA").load()
    op = out.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, a = px[x, y]
            if mask is None or mask(r, g, b):
                r = max(0, min(255, r + delta[0]))
                g = max(0, min(255, g + delta[1]))
                b = max(0, min(255, b + delta[2]))
            op[x, y] = (r, g, b, a)
    return out


def median_color(img):
    px = img.load()
    buckets = {}
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            key = tuple(v // 16 for v in px[x, y][:3])
            buckets[key] = buckets.get(key, 0) + 1
    best = max(buckets.items(), key=lambda kv: kv[1])[0]
    tot = [0, 0, 0]
    n = 0
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            c = px[x, y][:3]
            if tuple(v // 16 for v in c) == best:
                tot[0] += c[0]
                tot[1] += c[1]
                tot[2] += c[2]
                n += 1
    return tuple(t // n for t in tot)


def grass_match(tile, ground_median, prop_median):
    """Samakan rumput latar prop sheet dengan rumput ground tile, prop dibiarkan."""
    delta = tuple(ground_median[i] - prop_median[i] for i in range(3))
    def is_grass(r, g, b):
        return abs(r - prop_median[0]) < 34 and abs(g - prop_median[1]) < 34 and abs(b - prop_median[2]) < 34
    return shift(tile, delta, is_grass)


def recolored(img, mapping):
    """Peta hue kasar: ubah pixel yang dekat warna sumber ke warna tujuan."""
    out = Image.new("RGBA", img.size)
    src = img.convert("RGBA").load()
    op = out.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, a = src[x, y]
            for (from_c, to_c, tol) in mapping:
                if max(abs(r - from_c[0]), abs(g - from_c[1]), abs(b - from_c[2])) < tol:
                    op[x, y] = (to_c[0], to_c[1], to_c[2], a)
                    break
            else:
                op[x, y] = (r, g, b, a)
    return out


def shadow(kind):
    """Tile bayangan: hitam semi-transparan, tepi melembung, arah cahaya kiri atas."""
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind == "prop":
        d.ellipse((5, 9, 27, 26), fill=(0, 0, 0, 96))
        img = img.filter(ImageFilter.GaussianBlur(1.4))
    elif kind == "bottom":
        d.rectangle((0, 2, CELL, CELL), fill=(0, 0, 0, 104))
        d.rectangle((0, 0, CELL, 3), fill=(0, 0, 0, 52))
        img = img.filter(ImageFilter.GaussianBlur(1.6))
    elif kind == "right":
        d.rectangle((2, 0, CELL, CELL), fill=(0, 0, 0, 104))
        d.rectangle((0, 0, 3, CELL), fill=(0, 0, 0, 52))
        img = img.filter(ImageFilter.GaussianBlur(1.6))
    else:  # corner
        d.rectangle((2, 2, CELL, CELL), fill=(0, 0, 0, 118))
        img = img.filter(ImageFilter.GaussianBlur(1.6))
    return img


def soften_glow(img):
    """Kurangi cahaya yang sudah dipanggang di tile: biarkan PointLight2D yang
    mengerjakan, kalau tidak halo tile terlihat seperti kotak kuning."""
    out = Image.new("RGBA", img.size)
    src = img.convert("RGBA").load()
    op = out.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, a = src[x, y]
            if r > 170 and g > 150 and b < 130:
                k = 0.45
                r = int(r * k + gmed_target[0] * (1 - k))
                g = int(g * k + gmed_target[1] * (1 - k))
                b = int(b * k + gmed_target[2] * (1 - k))
            op[x, y] = (r, g, b, a)
    return out


def key_grass(tile, ref, hard=52, soft=74):
    """Buang latar rumput dari tile objek supaya tanah di layer dasar terlihat.
    Tanpa ini, prop yang ditaruh di tepi jalan tampil sebagai kotak hijau."""
    out = Image.new("RGBA", tile.size)
    src = tile.convert("RGB").load()
    op = out.load()
    for y in range(tile.size[1]):
        for x in range(tile.size[0]):
            c = src[x, y]
            d = max(abs(c[i] - ref[i]) for i in range(3))
            if d <= hard:
                a = 0
            elif d >= soft:
                a = 255
            else:
                a = int(255 * (d - hard) / float(soft - hard))
            op[x, y] = (c[0], c[1], c[2], a)
    return out


def build():
    ground = Image.open(GROUND_SHEET).convert("RGB")
    props = Image.open(PROPS_SHEET).convert("RGB")

    t = {}
    # --- dasar dari ground sheet (4x4) ---
    t["grass"] = cell(ground, 0, 0)
    t["grass_flower"] = cell(ground, 1, 0)
    # jalan tanah mulus: interior patch tanah di sel (2,0)
    t["dirt"] = ground.crop((2 * 256 + 70, 60, 2 * 256 + 190, 180)).resize((CELL, CELL), Image.BOX)
    t["cobble"] = cell(ground, 3, 0)
    t["wall_wood"] = cell(ground, 0, 1)
    t["wall_plaster"] = cell(ground, 1, 1)
    t["roof_clay"] = cell(ground, 2, 1)
    t["roof_clay_ridge"] = cell(ground, 3, 1)
    # pintu (sel 0 baris 2) dan jendela (sel 1 baris 2)
    t["wall_door"] = cell(ground, 0, 2)
    t["wall_window"] = cell(ground, 1, 2)
    t["tree"] = cell(ground, 2, 2)
    t["bush"] = cell(ground, 3, 2)
    t["well"] = cell(ground, 0, 3)
    t["fence"] = cell(ground, 1, 3)
    t["rock"] = cell(ground, 2, 3)
    t["water_edge"] = cell(ground, 3, 3)
    t["water"] = ground.crop((3 * 256 + 16, 3 * 256 + 96, 3 * 256 + 240, 3 * 256 + 250)).resize(
        (CELL, CELL), Image.BOX)

    # --- varian rumput, diturunkan dari tile rumput dasar ---
    global gmed_target
    gmed = median_color(t["grass"])
    gmed_target = gmed
    t["grass_dark"] = shift(t["grass"], (-16, -12, -14))
    t["grass_worn"] = Image.blend(t["grass"], t["dirt"], 0.45)
    clover = t["grass"].convert("RGB").copy()
    d = ImageDraw.Draw(clover)
    # Sebaran hash, bukan pola linear: pola linear terbaca sebagai garis diagonal.
    for i in range(30):
        x = ((i * 137 + 61) % 31) + 1
        y = ((i * 89 + 17) % 29) + 2
        d.point((x, y), fill=(158, 180, 96))
        d.point(((x + 2) % CELL, (y + 1) % CELL), fill=(142, 166, 84))
    t["grass_clover"] = clover

    # --- varian atap: recolor dari atap terakota ---
    clay = (216, 107, 59)
    t["roof_slate"] = recolored(t["roof_clay"], [(clay, (112, 124, 142), 46)])
    t["roof_slate_ridge"] = recolored(t["roof_clay_ridge"], [(clay, (112, 124, 142), 46)])
    t["roof_thatch"] = recolored(t["roof_clay"], [(clay, (198, 160, 78), 46)])
    t["roof_thatch_ridge"] = recolored(t["roof_clay_ridge"], [(clay, (198, 160, 78), 46)])
    chimney = t["roof_clay"].convert("RGBA")
    d = ImageDraw.Draw(chimney)
    d.rectangle((18, 6, 25, 16), fill=(126, 120, 128, 255))
    d.rectangle((18, 6, 25, 9), fill=(92, 88, 98, 255))
    d.rectangle((20, 8, 23, 10), fill=(40, 38, 44, 255))
    d.point((22, 4), fill=(214, 214, 214, 150))
    d.point((24, 2), fill=(214, 214, 214, 96))
    t["roof_chimney"] = chimney

    # Rumput latar tile yang berasal dari ground sheet (sumur, semak, pagar,
    # batu) punya tone sendiri (132,131,48) yang berbeda dari tile rumput polos,
    # jadi hutan pembatas terbaca sebagai papan catur. Samakan ke tone ground.
    sheet_grass = median_color(t["bush"])
    for name in ("well", "bush", "fence", "rock", "tree", "water_edge"):
        t[name] = grass_match(t[name], gmed, sheet_grass)
    # Sumur, semak, pagar, batu, dan pinus berdiri di atas rumput: latarnya
    # dipotong agar tanah asli di bawahnya tetap terlihat.
    for name in ("well", "bush", "fence", "rock"):
        t[name] = key_grass(t[name], gmed)

    # --- prop sheet, rumput latarnya disamakan dengan tile rumput ground ---
    pmed = median_color(cell(props, 0, 0))
    prop_order = [
        (0, 0, "barrel"), (1, 0, "crate"), (2, 0, "cart"), (3, 0, "haystack"),
        (0, 1, "lantern"), (1, 1, "signpost"), (2, 1, "flower_pot"), (3, 1, "stall"),
        (0, 2, "dummy"), (1, 2, "trough"), (2, 2, "logs"), (3, 2, "bench"),
        (0, 3, "bush_berry"), (1, 3, "fern"), (2, 3, "pine"), (3, 3, "shrub_flower"),
    ]
    for col, row, name in prop_order:
        tile = grass_match(cell(props, col, row), gmed, pmed)
        t[name] = key_grass(tile, gmed)

    # --- tile kosong transparan: dipakai layer objek supaya sel yang tidak
    # berisi objek tetap tercatat ada (GridPath membaca layer itu) ---
    t["empty"] = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))

    # --- bayangan ---
    t["shadow_prop"] = shadow("prop")
    t["shadow_bottom"] = shadow("bottom")
    t["shadow_right"] = shadow("right")
    t["shadow_corner"] = shadow("corner")

    rows = (len(TILES) + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))
    missing = []
    for name, _solid in [(n, s) for n, s in TILES]:
        idx = NAME_TO_IDX[name]
        if name not in t:
            missing.append(name)
            continue
        x = (idx % COLS) * CELL
        y = (idx // COLS) * CELL
        atlas.paste(t[name].convert("RGBA"), (x, y))
    if missing:
        sys.exit("tile belum dibuat: %s" % missing)

    atlas.save(OUT_ATLAS)
    write_tres(atlas, rows)
    write_consts()
    preview(atlas)
    print("atlas %s %d tile (%dx%d), solid=%d" % (
        OUT_ATLAS, len(TILES), atlas.size[0], atlas.size[1],
        sum(1 for _, s in TILES if s)))


def write_tres(atlas, rows):
    lines = [
        '[gd_resource type="TileSet" load_steps=3 format=3]',
        "",
        '[ext_resource type="Texture2D" path="res://village_tiles.png" id="1_village"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_village"]',
        'texture = ExtResource("1_village")',
        'texture_region_size = Vector2i(%d, %d)' % (CELL, CELL),
    ]
    poly = 'PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)'
    for idx, (name, solid) in enumerate(TILES):
        c, r = idx % COLS, idx // COLS
        key = "%d:%d/0" % (c, r)
        lines.append("%s = 0" % key)
        if solid:
            lines.append("%s/physics_layer_0/polygon_0/points = %s" % (key, poly))
    lines += [
        "",
        "[resource]",
        "tile_size = Vector2i(16, 16)",
        "physics_layer_0/collision_layer = 1",
        "physics_layer_0/collision_mask = 0",
        'sources/0 = SubResource("TileSetAtlasSource_village")',
    ]
    with open(OUT_TRES, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_consts():
    print("\n// ---- salin ke tools/build_village.gd ----")
    for idx, (name, solid) in enumerate(TILES):
        print("const %s := %d%s" % (name.upper(), idx, "  # solid" if solid else ""))
    print("// ----------------------------------------\n")


def preview(atlas):
    base = Image.new("RGB", atlas.size, (24, 26, 32))
    for y in range(atlas.size[1]):
        for x in range(atlas.size[0]):
            c = atlas.getpixel((x, y))
            if c[3] < 255:
                checker = (x // 8 + y // 8) % 2
                bg = (70, 70, 80) if checker else (48, 48, 56)
                c = tuple(int(c[3] * c[i] / 255 + (255 - c[3]) * bg[i] / 255) for i in range(3))
            base.putpixel((x, y), c[:3])
    os.makedirs(".tmp/vil", exist_ok=True)
    base.resize((atlas.size[0] * 4, atlas.size[1] * 4), Image.NEAREST).save(".tmp/vil/atlas_new.png")


if __name__ == "__main__":
    build()
