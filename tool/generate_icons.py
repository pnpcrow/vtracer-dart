#!/usr/bin/env python3
"""Generate VTracer app icons for Android + desktop platforms.

Design: "raster -> vector". One circle split down the middle: the left
half is a colorful pixel mosaic (the raster image), the right half a
bezier wireframe with pen-tool anchors and handles (the vector path),
on a dark indigo gradient.

Every asset is derived from one parametric model so the raster PNGs and
the Android VectorDrawables stay visually identical. The VectorDrawable
uses fill-only paths (no strokes, no clip-paths) because some launchers
drop clipped/stroked elements of adaptive-icon foregrounds.

Run with no arguments to regenerate all icon assets in-place.
"""

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BASE = 1024          # master canvas
SS = 4               # supersampling factor

# ---------------------------------------------------------------- palette
BG_START = (55, 48, 163)    # indigo-ish top-left
BG_END = (2, 6, 23)         # near-black bottom-right
GLOW = (56, 189, 248)       # sky glow behind the glyph
CYAN = (34, 211, 238)       # mosaic gradient start
VIOLET = (139, 92, 246)     # mosaic gradient end
INK = (248, 250, 252)       # near-white arc / arrow / anchors

RADIUS = 300                # glyph circle on the 1024 canvas
GRID = 6                    # mosaic cells across the circle


def lerp_color(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def hexc(c):
    return "#{:02X}{:02X}{:02X}".format(*c)


# ---------------------------------------------------------------- model
def glyph(detail=True):
    """Primitives (1024-space) describing the glyph, centred at (512, 512).

    Kinds (all rendered as plain fills on every backend):
      ("cell", x, y, w, h, color)              mosaic cell
      ("arc", cx, cy, r, width, a0, a1, col)   stroked arc, deg cw from 3h
      ("dot", cx, cy, r, col, filled)          anchor point
      ("line", x0, y0, x1, y1, w, col)         round-cap handle stem
    """
    cx, cy = 512, 512
    P = list(mosaic_cells(cx, cy, RADIUS, GRID))
    P.append(("arc", cx, cy, RADIUS, 16 if detail else 24, -90, 90, INK))
    if detail:
        th = math.radians(45)
        px, py = cx + RADIUS * math.cos(th), cy - RADIUS * math.sin(th)
        tx, ty = math.sin(th), math.cos(th)  # tangent direction
        hl = round(RADIUS * 0.40)
        for sign in (-1, 1):
            hx, hy = px + sign * hl * tx, py + sign * hl * ty
            P.append(("line", px, py, hx, hy, 8, INK))
            P.append(("dot", hx, hy, 11, INK, False))
        P.append(("dot", px, py, 13, INK, True))
        # quiet anchor dots along the smooth half of the path
        for a in (0, 60, -60):
            t2 = math.radians(a)
            P.append(("dot", cx + RADIUS * math.cos(t2),
                      cy - RADIUS * math.sin(t2), 10, INK, True))
    return P


def mosaic_cells(cx, cy, r, n, seed=7, slices=6):
    """Pixel cells tiling the left half-disc, as ("cell", ...) primitives.

    Fully-covered cells become one rect. Boundary cells are sliced into
    strips that follow the arc -- columns where the arc runs flat (near
    the top/bottom), rows where it runs steep (near the leftmost point)
    -- which keeps the shape crisp and reinforces the pixel look. Cell
    colours follow a cyan->violet gradient with per-cell jitter, like a
    quantized image.
    """
    cell = 2 * r / n
    rng = random.Random(seed)
    out = []
    for i in range(n):
        for j in range(n):
            x, y = cx - r + i * cell, cy - r + j * cell
            ccx, ccy = x + cell / 2, y + cell / 2
            if ccx > cx:    # right of the chord belongs to the vector half
                continue
            corners = [(x, y), (x + cell, y), (x + cell, y + cell), (x, y + cell)]
            dists = [math.hypot(px - cx, py - cy) for px, py in corners]
            if min(dists) > r:
                continue
            t = min(1.0, max(0.0, (ccx - (cx - r)) / (2 * r)))
            jitter = rng.uniform(0.86, 1.06)
            col = tuple(min(255, round(c * jitter))
                        for c in lerp_color(CYAN, VIOLET, t))
            g = cell * 0.09
            if max(dists) <= r:
                out.append(("cell", x + g / 2, y + g / 2,
                            cell - g, cell - g, col))
                continue

            def emit(xa, xb, ya, yb, xg0, xg1, yg0, yg1):
                w, h = xb - xa - xg0 - xg1, yb - ya - yg0 - yg1
                if w <= cell * 0.02 or h <= cell * 0.02:
                    return
                out.append(("cell", xa + xg0, ya + yg0, w, h, col))

            if cx - ccx > 0.707 * r:
                # steep arc zone: horizontal strips clipped in x by the arc;
                # gaps only on the cell's own edges, strips butt together
                for k in range(slices):
                    ya, yb = y + cell * k / slices, y + cell * (k + 1) / slices
                    ym = (ya + yb) / 2
                    if abs(ym - cy) >= r:
                        continue
                    xh = math.sqrt(r * r - (ym - cy) ** 2)
                    emit(max(x, cx - xh), min(x + cell, cx), ya, yb,
                         g / 2, g / 2, g / 2 if k == 0 else 0,
                         g / 2 if k == slices - 1 else 0)
            else:
                # flat arc zone: vertical columns clipped in y by the arc
                for k in range(slices):
                    xa, xb = x + cell * k / slices, x + cell * (k + 1) / slices
                    xm = (xa + xb) / 2
                    if xm > cx or abs(xm - cx) >= r:
                        continue
                    yh = math.sqrt(r * r - (xm - cx) ** 2)
                    emit(xa, xb, max(y, cy - yh), min(y + cell, cy + yh),
                         g / 2 if k == 0 else 0, g / 2 if k == slices - 1 else 0,
                         g / 2, g / 2)
    return out


def scale_primitives(P, s):
    """Scale the glyph about the canvas centre (adaptive/maskable layers)."""
    def pt(p):
        return (512 + (p[0] - 512) * s, 512 + (p[1] - 512) * s)

    out = []
    for p in P:
        k = p[0]
        if k == "cell":
            _, x, y, w, h, col = p
            out.append(("cell", 512 + (x - 512) * s, 512 + (y - 512) * s,
                        w * s, h * s, col))
        elif k == "arc":
            _, cx, cy, r, w, a0, a1, col = p
            ncx, ncy = pt((cx, cy))
            out.append(("arc", ncx, ncy, r * s, w * s, a0, a1, col))
        elif k == "dot":
            _, cx, cy, r, col, filled = p
            ncx, ncy = pt((cx, cy))
            out.append(("dot", ncx, ncy, r * s, col, filled))
        elif k == "line":
            _, x0, y0, x1, y1, w, col = p
            n0, n1 = pt((x0, y0)), pt((x1, y1))
            out.append(("line", n0[0], n0[1], n1[0], n1[1], w * s, col))
    return out


def recolor(P, col):
    out = []
    for p in P:
        if p[0] == "dot":
            out.append(p[:4] + (col,) + (p[5],))
        else:
            out.append(p[:-1] + (col,))
    return out


# ---------------------------------------------------------------- raster
def paint_primitives(img, P, ss, mono=False):
    draw = ImageDraw.Draw(img)
    for p in P:
        k = p[0]
        if k == "cell":
            _, x, y, w, h, col = p
            draw.rectangle([x * ss, y * ss, (x + w) * ss, (y + h) * ss],
                           fill=INK if mono else col)
        elif k == "arc":
            _, cx, cy, r, w, a0, a1, col = p
            bb = [(cx - r) * ss, (cy - r) * ss, (cx + r) * ss, (cy + r) * ss]
            draw.arc(bb, start=a0, end=a1,
                     fill=INK if mono else col, width=round(w * ss))
        elif k == "dot":
            _, cx, cy, r, col, filled = p
            bb = [(cx - r) * ss, (cy - r) * ss, (cx + r) * ss, (cy + r) * ss]
            if filled:
                draw.ellipse(bb, fill=INK if mono else col)
            else:
                draw.ellipse(bb, outline=INK if mono else col,
                             width=round(7 * ss))
        elif k == "line":
            _, x0, y0, x1, y1, w, col = p
            col = INK if mono else col
            draw.line([x0 * ss, y0 * ss, x1 * ss, y1 * ss], fill=col,
                      width=round(w * ss))
            for hx, hy in ((x0, y0), (x1, y1)):
                rr = w / 2
                draw.ellipse([(hx - rr) * ss, (hy - rr) * ss,
                              (hx + rr) * ss, (hy + rr) * ss], fill=col)


def background(w, h, rounded_radius=None):
    """Dark diagonal gradient (+soft glow); optionally rounded-rect alpha."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    t = 0.62 * (xx / max(w - 1, 1)) + 0.38 * (yy / max(h - 1, 1))
    rgb = np.zeros((h, w, 3), np.float64)
    for i in range(3):
        rgb[..., i] = BG_START[i] + (BG_END[i] - BG_START[i]) * t
    d = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    a = (np.clip(1 - d, 0, 1) ** 2.2 * 42 / 255)[..., None]
    rgb = rgb * (1 - a) + np.array(GLOW, np.float64) * a
    img = Image.fromarray(np.uint8(np.clip(rgb, 0, 255)), "RGB").convert("RGBA")
    if rounded_radius is not None:
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, w - 1, h - 1], radius=rounded_radius, fill=255)
        img.putalpha(mask)
    return img


def render(size, detail=True, kind="square", glyph_scale=1.0):
    """Master render. kind: square | round | fullbleed | transparent."""
    px = size * SS
    if kind == "square":
        img = background(px, px, rounded_radius=round(px * 0.21))
    elif kind == "round":
        img = background(px, px)
        mask = Image.new("L", (px, px), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, px - 1, px - 1], fill=255)
        img.putalpha(mask)
    elif kind == "fullbleed":
        img = background(px, px)
    else:
        img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    P = glyph(detail=detail)
    if glyph_scale != 1.0:
        P = scale_primitives(P, glyph_scale)
    paint_primitives(img, P, px / BASE)
    return img.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------- vector
def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s if s else "0"


def path_cell(x, y, w, h):
    return f"M{fmt(x)},{fmt(y)}h{fmt(w)}v{fmt(h)}h-{fmt(w)}z"


def path_circle(cx, cy, r):
    return (f"M{fmt(cx - r)},{fmt(cy)}a{fmt(r)},{fmt(r)} 0 1,0 {fmt(2 * r)},0"
            f"a{fmt(r)},{fmt(r)} 0 1,0 -{fmt(2 * r)},0z")


def arc_polygon(cx, cy, r, w, a0, a1):
    """Annular sector equivalent of a stroked arc (fill-only shape)."""
    n = max(8, int(abs(a1 - a0) / 6))
    ro, ri = r + w / 2, r - w / 2
    pts = []
    for i in range(n + 1):
        t = math.radians(a0 + (a1 - a0) * i / n)
        pts.append((cx + ro * math.cos(t), cy + ro * math.sin(t)))
    for i in range(n, -1, -1):
        t = math.radians(a0 + (a1 - a0) * i / n)
        pts.append((cx + ri * math.cos(t), cy + ri * math.sin(t)))
    return pts


def capsule_polygon(x0, y0, x1, y1, w):
    """Round-cap line segment as a fill-only polygon.

    Parametrised in the segment frame (u along, n across): the start cap
    sweeps t=90..270 around P0, the end cap t=270..450 around P1.
    """
    dx, dy = x1 - x0, y1 - y0
    dist = math.hypot(dx, dy)
    ux, uy = dx / dist, dy / dist
    nx, ny = -uy, ux
    hw = w / 2
    pts = []
    for tdeg in list(range(90, 271, 30)) + list(range(270, 451, 30)):
        t = math.radians(tdeg)
        cx_, cy_ = (x0, y0) if tdeg <= 270 else (x1, y1)
        pts.append((cx_ + hw * (math.cos(t) * ux + math.sin(t) * nx),
                    cy_ + hw * (math.cos(t) * uy + math.sin(t) * ny)))
    return pts


def polygon_path(pts):
    return "M" + "L".join(f"{fmt(x)},{fmt(y)}" for x, y in pts) + "z"


def vector_elements(P, force_color=None):
    out = []
    for p in P:
        k = p[0]
        col = force_color or (p[4] if k == "dot" else p[-1])
        if k == "cell":
            _, x, y, w, h, _ = p
            out.append(f'<path android:pathData="{path_cell(x, y, w, h)}" '
                       f'android:fillColor="{hexc(col)}"/>')
        elif k == "arc":
            _, cx, cy, r, w, a0, a1, _ = p
            pts = arc_polygon(cx, cy, r, w, a0, a1)
            out.append(f'<path android:pathData="{polygon_path(pts)}" '
                       f'android:fillColor="{hexc(col)}"/>')
        elif k == "dot":
            _, cx, cy, r, _, filled = p
            if filled:
                out.append(f'<path android:pathData="{path_circle(cx, cy, r)}"'
                           f' android:fillColor="{hexc(col)}"/>')
            else:
                out.append(f'<path android:fillType="evenOdd" '
                           f'android:pathData="{path_circle(cx, cy, r + 3.5)} '
                           f'{path_circle(cx, cy, max(r - 3.5, 1))}" '
                           f'android:fillColor="{hexc(col)}"/>')
        elif k == "line":
            _, x0, y0, x1, y1, w, _ = p
            pts = capsule_polygon(x0, y0, x1, y1, w)
            out.append(f'<path android:pathData="{polygon_path(pts)}" '
                       f'android:fillColor="{hexc(col)}"/>')
    return out


def vector_drawable(P, force_color=None, scale=1.0, translate=0.0,
                    viewport=108):
    s = viewport / BASE * scale
    body = "\n        ".join(vector_elements(P, force_color))
    group = ""
    if scale != 1.0 or translate:
        group = (f'\n    <group android:scaleX="{s:.6f}" '
                 f'android:scaleY="{s:.6f}" '
                 f'android:translateX="{translate:.4f}" '
                 f'android:translateY="{translate:.4f}">'
                 f'\n        {body}\n    </group>')
        body = ""
    return ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp"\n'
            f'    android:viewportWidth="{viewport}" '
            f'android:viewportHeight="{viewport}">{group or chr(10) + "    " + body}\n</vector>\n')


def adaptive_background_vector():
    return ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    xmlns:aapt="http://schemas.android.com/aapt"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n'
            '    <path android:pathData="M0,0h108v108h-108z">\n'
            '        <aapt:attr name="android:fillColor">\n'
            '            <gradient\n'
            '                android:type="linear"\n'
            '                android:startX="0" android:startY="0"\n'
            '                android:endX="108" android:endY="108"\n'
            f'                android:startColor="{hexc(BG_START)}"\n'
            f'                android:endColor="{hexc(BG_END)}"/>\n'
            '        </aapt:attr>\n'
            '    </path>\n'
            '</vector>\n')


# ---------------------------------------------------------------- outputs
ANDROID_RES = (ROOT / "apps/vtracer_android/android/app/src/main/res")
DESKTOP = ROOT / "apps/vtracer_app"

# adaptive foreground: glyph fits the 66dp safe zone of the 108dp viewport
FG_SCALE = 0.92
MASKABLE_SCALE = 1.05

DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144,
             "xxxhdpi": 192}


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"  wrote {path.relative_to(ROOT)}")


def write_text(text, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"  wrote {path.relative_to(ROOT)}")


def gen_android():
    print("Android:")
    write_text(adaptive_background_vector(),
               ANDROID_RES / "drawable/ic_launcher_background.xml")
    fg = scale_primitives(glyph(), FG_SCALE)
    mono = scale_primitives(recolor(glyph(), INK), FG_SCALE)
    t = 54 - 512 * (108 / BASE * FG_SCALE)
    write_text(vector_drawable(fg, scale=FG_SCALE, translate=t),
               ANDROID_RES / "drawable/ic_launcher_foreground.xml")
    write_text(vector_drawable(mono, force_color=INK, scale=FG_SCALE,
                               translate=t),
               ANDROID_RES / "drawable/ic_launcher_monochrome.xml")
    for name in ("ic_launcher", "ic_launcher_round"):
        write_text(
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n',
            ANDROID_RES / f"mipmap-anydpi-v26/{name}.xml")
    for dpi, size in DENSITIES.items():
        save(render(size, detail=(size >= 96)),
             ANDROID_RES / f"mipmap-{dpi}/ic_launcher.png")
        save(render(size, kind="round", detail=(size >= 96)),
             ANDROID_RES / f"mipmap-{dpi}/ic_launcher_round.png")


def gen_windows():
    import io
    import struct
    print("Windows ICO:")
    sizes = [16, 20, 24, 32, 48, 64, 128, 256]

    def bmp_entry(img):
        """Classic DIB entry (safe for LoadImage / title-bar icons)."""
        w, h = img.size
        data = img.tobytes()
        stride = w * 4
        px = bytearray()
        for row in range(h - 1, -1, -1):     # DIBs are bottom-up BGRA
            line = bytearray(data[row * stride:(row + 1) * stride])
            line[0::4], line[2::4] = line[2::4], line[0::4]
            px += line
        header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0,
                             len(px), 0, 0, 0, 0)
        mask_stride = ((w + 31) // 32) * 4   # unused 1bpp mask, all opaque
        mask = b"\x00" * (mask_stride * h)
        return header + bytes(px) + mask

    entries, blobs = [], b""
    offset = 6 + 16 * len(sizes)
    for s in sizes:
        img = render(s, detail=(s >= 48))
        if s <= 64:
            blob = bmp_entry(img)
        else:
            with io.BytesIO() as bio:
                img.save(bio, "PNG")
                blob = bio.getvalue()
        entries.append((s, len(blob), offset))
        blobs += blob
        offset += len(blob)
    out = bytearray()
    out += (0).to_bytes(2, "little") + (1).to_bytes(2, "little") \
        + len(sizes).to_bytes(2, "little")
    for s, nbytes, off in entries:
        dim = 0 if s >= 256 else s
        out += dim.to_bytes(1, "little") + dim.to_bytes(1, "little") \
            + (0).to_bytes(1, "little") + (0).to_bytes(1, "little") \
            + (1).to_bytes(2, "little") + (32).to_bytes(2, "little") \
            + nbytes.to_bytes(4, "little") + off.to_bytes(4, "little")
    out += blobs
    path = DESKTOP / "windows/runner/resources/app_icon.ico"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)
    print(f"  wrote {path.relative_to(ROOT)} ({len(out)} bytes, "
          f"{len(sizes)} sizes)")


def gen_macos():
    print("macOS:")
    # Big Sur template: 824px art centred in a 1024 canvas with margin
    art = render(824, detail=True)
    canvas = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
    canvas.paste(art, ((BASE - 824) // 2,) * 2, art)
    for s in (16, 32, 64, 128, 256, 512, 1024):
        save(canvas.resize((s, s), Image.LANCZOS),
             DESKTOP / f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{s}.png")


def gen_web():
    print("Web:")
    save(render(16, detail=False), DESKTOP / "web/favicon.png")
    for s in (192, 512):
        save(render(s, detail=True), DESKTOP / f"web/icons/Icon-{s}.png")
        save(render(s, kind="fullbleed", glyph_scale=MASKABLE_SCALE, detail=True),
             DESKTOP / f"web/icons/Icon-maskable-{s}.png")


def main():
    gen_android()
    gen_windows()
    gen_macos()
    gen_web()
    print("done.")


if __name__ == "__main__":
    main()
