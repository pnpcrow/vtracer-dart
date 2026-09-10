"""Launcher-style preview sheet for the generated VTracer icons."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image, ImageDraw

from generate_icons import (BASE, glyph, paint_primitives, recolor,
                            render, scale_primitives)

CELL = 200
PAD = 28
COLS = 4


def masked(img, mode):
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    if mode == "circle":
        d.ellipse([0, 0, img.size[0] - 1, img.size[1] - 1], fill=255)
    else:
        d.rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1],
                            radius=int(img.size[0] * 0.27), fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out


def foreground(size, scale):
    img = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    paint_primitives(img, scale_primitives(glyph(), scale), size * 4 / BASE)
    return img.resize((size, size), Image.LANCZOS)


def monochrome(size, scale):
    img = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    paint_primitives(img, scale_primitives(recolor(glyph(), (255, 255, 255)),
                                           scale), size * 4 / BASE, mono=True)
    return img.resize((size, size), Image.LANCZOS)


tiles = []
S = 432
fg, bg = foreground(S, 0.92), render(S, kind="fullbleed")
adaptive = Image.alpha_composite(bg, fg)
themed = Image.alpha_composite(Image.new("RGBA", (S, S), (122, 141, 71, 255)),
                               monochrome(S, 0.92))

for name, img in [
    ("adaptive circle", masked(adaptive, "circle")),
    ("adaptive squircle", masked(adaptive, "squircle")),
    ("legacy square", render(S)),
    ("legacy round", render(S, kind="round")),
    ("themed (API 33+)", masked(themed, "circle")),
    ("web maskable", render(S, kind="fullbleed", glyph_scale=1.05)),
    ("48px", render(48, detail=False)),
    ("24px", render(24, detail=False)),
]:
    img = img.resize((CELL, CELL), Image.LANCZOS) if img.size[0] == S else img
    tiles.append((name, img))

W = COLS * (CELL + PAD) + PAD
rows = (len(tiles) + COLS - 1) // COLS
sheet = Image.new("RGBA", (W, rows * (CELL + PAD + 18) + PAD), (24, 24, 28, 255))
d = ImageDraw.Draw(sheet)
for i, (name, img) in enumerate(tiles):
    x = PAD + (i % COLS) * (CELL + PAD)
    y = PAD + (i // COLS) * (CELL + PAD + 18)
    sheet.paste(img, (x, y), img)
    d.text((x + 2, y + CELL + 2), name, fill=(220, 220, 225, 255))
out = Path(__file__).resolve().parents[1] / "build/icon_preview/sheet.png"
out.parent.mkdir(parents=True, exist_ok=True)
sheet.save(out)
print(f"wrote {out}")
