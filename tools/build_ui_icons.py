#!/usr/bin/env python3
"""Ikon UI 16x16 untuk HUD dan toko desa.

Digambar dari data (bukan imagegen) supaya tiap ikon punya palet dan ketebalan
garis yang sama, dan bisa dibangkitkan ulang kalau warnanya perlu diubah.
Semua ikon diberi outline gelap 1 px supaya tetap terbaca di atas panel gelap
maupun di atas rumput.
"""
from PIL import Image, ImageDraw
import os

OUT = "art/ui"
S = 16

INK = (24, 22, 28)
GOLD = (226, 178, 58)
GOLD_DARK = (150, 108, 30)
RED = (198, 62, 58)
RED_DARK = (126, 32, 34)
STEEL = (150, 162, 178)
STEEL_DARK = (86, 96, 112)
CLAY = (216, 107, 59)
GREEN = (104, 158, 72)
BONE = (226, 222, 208)
BLUE = (74, 132, 190)


def canvas():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def outline(img):
    """Tinta gelap 1 px di sekeliling bentuk, tanpa menutupi pixel aslinya."""
    src = img.load()
    out = img.copy()
    op = out.load()
    for y in range(S):
        for x in range(S):
            if src[x, y][3] > 0:
                continue
            near = False
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < S and 0 <= ny < S and src[nx, ny][3] > 128:
                        near = True
            if near:
                op[x, y] = (INK[0], INK[1], INK[2], 255)
    return out


def coin():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse((2, 2, 13, 13), fill=GOLD, outline=GOLD_DARK)
    d.ellipse((4, 4, 11, 11), outline=GOLD_DARK)
    d.line((7, 5, 7, 10), fill=GOLD_DARK)
    d.line((6, 6, 8, 6), fill=GOLD_DARK)
    d.point((4, 4), fill=(255, 236, 170))
    return img


def heart(empty=False):
    img = canvas()
    d = ImageDraw.Draw(img)
    fill = (70, 62, 70) if empty else RED
    shade = (44, 40, 48) if empty else RED_DARK
    d.rectangle((3, 4, 12, 9), fill=fill)
    d.rectangle((4, 3, 7, 10), fill=fill)
    d.rectangle((8, 3, 11, 10), fill=fill)
    d.polygon([(3, 9), (12, 9), (7, 14)], fill=fill)
    d.line((3, 9, 7, 14), fill=shade)
    d.point((5, 5), fill=(255, 150, 140) if not empty else (96, 90, 96))
    return img


def sword():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.line((4, 12, 12, 4), fill=STEEL, width=2)
    d.line((5, 11, 11, 5), fill=(206, 216, 230))
    d.line((3, 11, 5, 13), fill=GOLD, width=2)
    d.point((2, 14), fill=GOLD_DARK)
    d.point((12, 3), fill=(236, 244, 252))
    return img


def skull():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.rectangle((3, 3, 12, 9), fill=BONE)
    d.rectangle((4, 10, 11, 11), fill=BONE)
    d.point((5, 12), fill=BONE)
    d.point((10, 12), fill=BONE)
    d.rectangle((5, 5, 6, 7), fill=INK)
    d.rectangle((9, 5, 10, 7), fill=INK)
    d.point((7, 9), fill=INK)
    d.point((8, 9), fill=INK)
    return img


def portal():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse((3, 1, 12, 14), fill=(28, 40, 74), outline=STEEL)
    d.ellipse((5, 3, 10, 12), outline=(122, 196, 226))
    d.point((7, 6), fill=(190, 236, 250))
    d.point((8, 9), fill=(150, 210, 240))
    d.rectangle((2, 14, 13, 15), fill=(96, 98, 104))
    return img


def stall():
    img = canvas()
    d = ImageDraw.Draw(img)
    for i, x in enumerate(range(1, 15, 2)):
        d.rectangle((x, 2, x + 1, 5), fill=(242, 240, 236) if i % 2 else CLAY)
    d.line((1, 6, 14, 6), fill=RED_DARK)
    d.rectangle((3, 7, 12, 12), fill=(122, 82, 44))
    d.rectangle((4, 8, 11, 9), fill=(154, 108, 60))
    d.point((6, 11), fill=GOLD)
    d.point((9, 11), fill=GREEN)
    return img


def maptile(kind):
    img = canvas()
    d = ImageDraw.Draw(img)
    d.rectangle((2, 3, 13, 13), fill=(122, 82, 44) if kind == "dungeon" else GREEN)
    if kind == "dungeon":
        d.rectangle((4, 5, 11, 12), fill=(64, 72, 92))
        d.rectangle((6, 8, 9, 12), fill=(26, 30, 40))
        d.point((7, 6), fill=STEEL_DARK)
    else:
        d.polygon([(4, 12), (8, 5), (12, 12)], fill=CLAY)
        d.rectangle((6, 9, 10, 12), fill=(214, 202, 170))
        d.point((8, 11), fill=(122, 82, 44))
    return img


def target():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse((2, 2, 13, 13), outline=GOLD)
    d.ellipse((5, 5, 10, 10), outline=GOLD_DARK)
    d.point((7, 7), fill=GOLD)
    d.point((8, 8), fill=GOLD)
    return img


def close():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.line((3, 3, 12, 12), fill=BONE, width=2)
    d.line((12, 3, 3, 12), fill=BONE, width=2)
    return img


def build():
    os.makedirs(OUT, exist_ok=True)
    icons = {
        "coin": coin(),
        "heart": heart(),
        "heart_empty": heart(True),
        "sword": sword(),
        "skull": skull(),
        "portal": portal(),
        "stall": stall(),
        "map_dungeon": maptile("dungeon"),
        "map_village": maptile("village"),
        "target": target(),
        "close": close(),
    }
    z = 6
    sheet = Image.new("RGB", (4 * (S * z + 8), ((len(icons) + 3) // 4) * (S * z + 18)), (32, 34, 42))
    for i, (name, img) in enumerate(icons.items()):
        art = outline(img)
        art.save("%s/%s.png" % (OUT, name))
        col, row = i % 4, i // 4
        x = col * (S * z + 8)
        y = row * (S * z + 18)
        sheet.paste(Image.new("RGB", (S * z, S * z), (120, 116, 96)), (x, y))
        rgb = Image.new("RGB", art.size, (0, 0, 0))
        rgb.paste(art, (0, 0), art)
        sheet.paste(rgb.resize((S * z, S * z), Image.NEAREST), (x, y))
        d = ImageDraw.Draw(sheet)
        d.text((x, y + S * z + 2), name, fill=(220, 220, 220))
    sheet.save(".tmp/vil/icons_sheet.png")
    print("ikon dibuat:", ", ".join(icons.keys()))


if __name__ == "__main__":
    build()
