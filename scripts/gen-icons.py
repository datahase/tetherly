#!/usr/bin/env python3
"""Generates every app icon size from the brand sources in design/brand/ (Pillow only). Deterministic; re-run after
changing a source. Outputs: macOS AppIcon.appiconset, Android launcher mipmaps + adaptive layers, README logos.
`--web` regenerates only the website icons (favicon.ico, icon.png, apple-icon.png)."""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "design", "brand")
DARK_BG = (30, 26, 23)  # sampled from mark-dark-source.png

def squircle(size, n=5.0, inset=0.0):
    """Superellipse mask (continuous-corner squircle), supersampled for smooth edges."""
    s = size * 4
    m = Image.new("L", (s, s), 0)
    r = s / 2 * (1 - inset)
    c = s / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        ct, st = math.cos(t), math.sin(t)
        pts.append((c + r * abs(ct) ** (2 / n) * (1 if ct >= 0 else -1), c + r * abs(st) ** (2 / n) * (1 if st >= 0 else -1)))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)

def mac_icon():
    src = Image.open(os.path.join(SRC, "mac-tile-source.png")).convert("RGBA")
    # Tile spans roughly x 102..1150, y 107..1140; crop square on it and re-mask to drop the speckled fringe.
    cx, cy, side = 626, 622, 1030
    tile = src.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)).resize((824, 824), Image.LANCZOS)
    tile.putalpha(squircle(824, inset=0.012))
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (100, 112), squircle(824, inset=0.012))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(tile, (100, 100))
    out = os.path.join(ROOT, "apps", "macos", "Tetherly", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out, exist_ok=True)
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            canvas.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
            images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(out, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
    with open(os.path.join(os.path.dirname(out), "Contents.json"), "w") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)
    canvas.save(os.path.join(ROOT, "design", "brand", "mac-app-icon-1024.png"))

def mark_on_transparent():
    """Keys the dark background out of mark-dark-source.png → mark with alpha (soft edge from luminance distance)."""
    src = Image.open(os.path.join(SRC, "mark-dark-source.png")).convert("RGB")
    out = Image.new("RGBA", src.size)
    sp, op = src.load(), out.load()
    for y in range(src.size[1]):
        for x in range(src.size[0]):
            r, g, b = sp[x, y]
            d = max(abs(r - DARK_BG[0]), abs(g - DARK_BG[1]), abs(b - DARK_BG[2]))
            a = 0 if d < 18 else 255 if d > 60 else int((d - 18) / 42 * 255)
            op[x, y] = (r, g, b, a)
    return out.crop(out.getbbox())

def android_icons(mark):
    res = os.path.join(ROOT, "apps", "android", "app", "src", "main", "res")
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    # Adaptive foreground: 108dp canvas; launcher masks show a 72dp circle and guarantee only the 66dp safe zone, so the mark stays ≤50dp.
    def layer(dp_canvas, dp_mark, img):
        s = round(dp_canvas * scale)
        c = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        m = round(dp_mark * scale)
        w, h = img.size
        k = m / max(w, h)
        r = img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
        c.alpha_composite(r, ((s - r.size[0]) // 2, (s - r.size[1]) // 2))
        return c
    mono = Image.new("RGBA", mark.size, (255, 255, 255, 255))
    mono.putalpha(mark.getchannel("A"))
    for name, scale in dens.items():
        d = os.path.join(res, f"mipmap-{name}")
        os.makedirs(d, exist_ok=True)
        layer(108, 50, mark).save(os.path.join(d, "ic_launcher_foreground.png"))
        layer(108, 50, mono).save(os.path.join(d, "ic_launcher_monochrome.png"))
        # Legacy (pre-adaptive launchers): full square and circle on the brand dark background.
        s = round(48 * scale)
        legacy = Image.new("RGBA", (s, s), DARK_BG + (255,))
        legacy.alpha_composite(layer(48, 30, mark))
        rounded = Image.new("L", (s * 4, s * 4), 0)
        ImageDraw.Draw(rounded).rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=s * 4 // 6, fill=255)
        sq = legacy.copy(); sq.putalpha(rounded.resize((s, s), Image.LANCZOS)); sq.save(os.path.join(d, "ic_launcher.png"))
        circ = Image.new("L", (s * 4, s * 4), 0)
        ImageDraw.Draw(circ).ellipse((0, 0, s * 4 - 1, s * 4 - 1), fill=255)
        rd = legacy.copy(); rd.putalpha(circ.resize((s, s), Image.LANCZOS)); rd.save(os.path.join(d, "ic_launcher_round.png"))
    os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
    xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""
    for n in ("ic_launcher", "ic_launcher_round"):
        with open(os.path.join(res, "mipmap-anydpi-v26", f"{n}.xml"), "w") as f:
            f.write(xml)
    with open(os.path.join(res, "values", "ic_launcher_background.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#1E1A17</color>\n</resources>\n')
    # Play Store style 512px preview, for docs.
    big = Image.new("RGBA", (512, 512), DARK_BG + (255,))
    k = 300 / max(mark.size)
    m = mark.resize((round(mark.size[0] * k), round(mark.size[1] * k)), Image.LANCZOS)
    big.alpha_composite(m, ((512 - m.size[0]) // 2, (512 - m.size[1]) // 2))
    big.save(os.path.join(ROOT, "design", "brand", "android-icon-512.png"))

def menu_bar_icon(mark):
    """macOS menu bar template image: black + alpha, 18pt canvas, mark fitted to 16pt; macOS tints it."""
    out = os.path.join(ROOT, "apps", "macos", "Tetherly", "Assets.xcassets", "MenuBarIcon.imageset")
    os.makedirs(out, exist_ok=True)
    black = Image.new("RGBA", mark.size, (0, 0, 0, 255))
    black.putalpha(mark.getchannel("A"))
    images = []
    for scale in (1, 2, 3):
        s, m = 18 * scale, 16 * scale
        c = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        k = m / max(black.size)
        r = black.resize((round(black.size[0] * k), round(black.size[1] * k)), Image.LANCZOS)
        c.alpha_composite(r, ((s - r.size[0]) // 2, (s - r.size[1]) // 2))
        name = f"menubar@{scale}x.png"
        c.save(os.path.join(out, name))
        images.append({"idiom": "universal", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(out, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"},
                   "properties": {"template-rendering-intent": "template"}}, f, indent=2)

def ios_assets(mark):
    """iOS: one opaque 1024 icon (dark tile like Android's adaptive icon) plus launch and accent colors."""
    cat = os.path.join(ROOT, "apps", "ios", "TetherlyiOS", "Assets.xcassets")
    icon_dir = os.path.join(cat, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)
    tile = Image.new("RGB", (1024, 1024), DARK_BG)
    k = 560 / max(mark.size)
    m = mark.resize((round(mark.size[0] * k), round(mark.size[1] * k)), Image.LANCZOS)
    tile.paste(m, ((1024 - m.size[0]) // 2, (1024 - m.size[1]) // 2), m)
    tile.save(os.path.join(icon_dir, "icon-1024.png"))
    with open(os.path.join(icon_dir, "Contents.json"), "w") as f:
        json.dump({"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon-1024.png"}],
                   "info": {"version": 1, "author": "xcode"}}, f, indent=2)
    def color(name, light, dark):
        d = os.path.join(cat, f"{name}.colorset")
        os.makedirs(d, exist_ok=True)
        comp = lambda h: {"color-space": "srgb", "components": {"red": f"0x{h[0:2]}", "green": f"0x{h[2:4]}", "blue": f"0x{h[4:6]}", "alpha": "1.000"}}
        with open(os.path.join(d, "Contents.json"), "w") as f:
            json.dump({"colors": [{"idiom": "universal", "color": comp(light)},
                                  {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "color": comp(dark)}],
                       "info": {"version": 1, "author": "xcode"}}, f, indent=2)
    color("LaunchBackground", "FBF7EE", "1C1814")
    color("AccentColor", "C2510A", "FD6B0B")
    with open(os.path.join(cat, "Contents.json"), "w") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)
    # Brand mark for in-app use (transparent).
    mk = os.path.join(cat, "BrandMark.imageset")
    os.makedirs(mk, exist_ok=True)
    for scale in (1, 2, 3):
        s = 64 * scale
        c = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        kk = s * 0.9 / max(mark.size)
        r = mark.resize((round(mark.size[0] * kk), round(mark.size[1] * kk)), Image.LANCZOS)
        c.alpha_composite(r, ((s - r.size[0]) // 2, (s - r.size[1]) // 2))
        c.save(os.path.join(mk, f"mark@{scale}x.png"))
    with open(os.path.join(mk, "Contents.json"), "w") as f:
        json.dump({"images": [{"idiom": "universal", "scale": f"{x}x", "filename": f"mark@{x}x.png"} for x in (1, 2, 3)],
                   "info": {"version": 1, "author": "xcode"}}, f, indent=2)

def readme_logos():
    out = os.path.join(ROOT, "docs", "assets")
    os.makedirs(out, exist_ok=True)
    for src, dst in (("mark-light-source.png", "logo-light.png"), ("mark-dark-source.png", "logo-dark.png"), ("mark-3d-source.png", "logo-3d.png")):
        Image.open(os.path.join(SRC, src)).convert("RGBA").resize((320, 320), Image.LANCZOS).save(os.path.join(out, dst), optimize=True)

def web_icons(mark):
    """Website: the dark tile, which reads on light and dark browser tabs. Small sizes use a larger mark to stay legible."""
    out = os.path.join(ROOT, "apps", "web", "src", "app")
    def tile(size, frac, rounded=True):
        t = Image.new("RGBA", (size, size), DARK_BG + (255,))
        k = size * frac / max(mark.size)
        m = mark.resize((round(mark.size[0] * k), round(mark.size[1] * k)), Image.LANCZOS)
        t.alpha_composite(m, ((size - m.size[0]) // 2, (size - m.size[1]) // 2))
        if rounded:
            t.putalpha(squircle(size))
        return t
    small = [tile(n, 0.74) for n in (16, 32, 48)]
    small[-1].save(os.path.join(out, "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)], append_images=small[:-1])
    tile(512, 0.62).save(os.path.join(out, "icon.png"), optimize=True)
    tile(180, 0.58, rounded=False).convert("RGB").save(os.path.join(out, "apple-icon.png"), optimize=True)  # iOS rounds it

mark = mark_on_transparent()
if "--web" in sys.argv:
    web_icons(mark)
else:
    mac_icon()
    android_icons(mark)
    menu_bar_icon(mark)
    ios_assets(mark)
    readme_logos()
    web_icons(mark)
print("ok")
