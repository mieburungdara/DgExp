#!/usr/bin/env python3
"""Potong lembar karakter desa menjadi sprite siap pakai di art/people/.

Latar magenta dibuang, tiap sel di-crop ke bounding box karakternya, lalu
diseragamkan: orang dewasa 24x32, hewan 16x16, kaki selalu rata dengan tepi
bawah kanvas supaya posisi node = posisi kaki.
"""
from PIL import Image
import os, sys

SHEET = ".arsip/village_master/village_people_raw_1793740413892_cc86239b.png"
OUT = "art/people"
CELL = 256

ADULTS = ["merchant", "farmer", "woman", "child", "elder", "guard", "man", "woman2"]
SMALL = ["hen", "rooster", "duck", "goose", "goat", "sheep", "dog", "cat"]
NAMES = ADULTS + SMALL

ADULT_BOX = (24, 32)
SMALL_BOX = (16, 16)


def is_magenta(r, g, b):
    # Jarak kuadrat ke (255,0,255) dengan kelonggaran tepi anti-alias.
    return (255 - r) ** 2 + g ** 2 + (255 - b) ** 2 < 90 ** 2


def cutout(cell):
    px = cell.load()
    out = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    op = out.load()
    for y in range(cell.size[1]):
        for x in range(cell.size[0]):
            r, g, b = px[x, y][:3]
            if is_magenta(r, g, b):
                continue
            # Busur kecil di sekitar pixel magenta: buang halo ungu.
            halo = False
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < cell.size[0] and 0 <= ny < cell.size[1]:
                        nr, ng, nb = px[nx, ny][:3]
                        if is_magenta(nr, ng, nb) and (r + g + b) > 240 and abs(r - b) < 60:
                            halo = True
            if halo:
                continue
            op[x, y] = (r, g, b, 255)
    return out


def normalize(img, box, animal):
    """Skala integer lalu tempel dengan kaki rata bawah, pusat horizontal."""
    bbox = img.getbbox()
    if bbox is None:
        sys.exit("sel kosong, tidak ada karakter untuk dipotong")
    sprite = img.crop(bbox)
    # Skala integer: pembesaran non-integer menghancurkan pixel art.
    scale = min(box[0] // max(sprite.size[0], 1), box[1] // max(sprite.size[1], 1))
    if scale < 1:
        # Terlanjur besar: turunkan dengan BOX (area average), bukan nearest.
        w = box[0]
        h = max(1, int(round(sprite.size[1] * (w / float(sprite.size[0])))))
        if h > box[1]:
            h = box[1]
            w = max(1, int(round(sprite.size[0] * (h / float(sprite.size[1])))))
        sprite = sprite.resize((w, h), Image.BOX)
    else:
        sprite = sprite.resize((sprite.size[0] * scale, sprite.size[1] * scale), Image.NEAREST)
    out = Image.new("RGBA", box, (0, 0, 0, 0))
    x = (box[0] - sprite.size[0]) // 2
    y = box[1] - sprite.size[1]
    out.paste(sprite, (x, y), sprite)
    return out


def build():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGB")
    rows = []
    for i, name in enumerate(NAMES):
        col, row = i % 4, i // 4
        cell = sheet.crop((col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL))
        animal = name in SMALL
        box = SMALL_BOX if animal else ADULT_BOX
        spr = normalize(cutout(cell), box, animal)
        path = "%s/%s.png" % (OUT, name)
        spr.save(path)
        rows.append((name, spr.size, animal))
    for name, size, animal in rows:
        print("%-9s %dx%d %s" % (name, size[0], size[1], "hewan" if animal else "warga"))
    # kontak sheet untuk dilihat cepat
    z = 4
    prev = Image.new("RGB", (4 * (ADULT_BOX[0] + 4) * z, 4 * (ADULT_BOX[1] + 4) * z), (34, 36, 44))
    for i, name in enumerate(NAMES):
        col, row = i % 4, i // 4
        spr = Image.open("%s/%s.png" % (OUT, name))
        bg = Image.new("RGB", spr.size, (120, 116, 96))
        bg.paste(spr, (0, 0), spr)
        prev.paste(bg.resize((spr.size[0] * z, spr.size[1] * z), Image.NEAREST),
                   (col * (ADULT_BOX[0] + 4) * z, row * (ADULT_BOX[1] + 4) * z))
    prev.save(".tmp/vil/people_cut.png")


if __name__ == "__main__":
    build()
