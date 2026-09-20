"""Generate the actual iOS AppIcon asset and Android adaptive-icon resources from the
Stilltime logo mark, using the same ring/glow recipe as render_logo.py.

Run after changing the logo, or once to bootstrap the icon assets:
    python generate_app_icons.py

iOS: writes Stilltime/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (opaque, full-bleed
square -- Apple applies its own corner mask, and the App Store icon must not carry an alpha
channel, so this is deliberately NOT the rounded/transparent-corner icon render_logo.py makes).

Android (minSdk 26, so adaptive icons alone are sufficient -- no legacy fallback density set is
needed): writes a foreground-only ring mark per mipmap density, inset well within Android's
66%-diameter safe zone since the OS applies its own mask/shape, plus the adaptive-icon XML and
a solid background color matching the icon's own background.
"""
import os
from PIL import Image, ImageDraw

from render_logo import LIME, BG, ring_layer, with_glow

ROOT = os.path.dirname(os.path.abspath(__file__))
STILLTIME_DIR = os.path.dirname(ROOT)
KIT_ROOT = os.path.dirname(STILLTIME_DIR)
ANDROID_RES = os.path.join(KIT_ROOT, "Android", "stilltime", "src", "main", "res")

IOS_APPICON_DIR = os.path.join(STILLTIME_DIR, "Assets.xcassets", "AppIcon.appiconset")
IOS_CATALOG_DIR = os.path.join(STILLTIME_DIR, "Assets.xcassets")

ANDROID_DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}


def make_ios_icon(path, size=1024):
    """Full-bleed opaque square: same radial background + ring as render_logo.make_icon,
    but without the rounded-rect mask (Apple rounds the icon itself) and flattened to RGB
    (Apple's App Store validation rejects a large app icon that carries an alpha channel)."""
    bg = Image.new("RGB", (size, size), BG)
    bd = ImageDraw.Draw(bg)
    cx, cy = size / 2, size * 0.38
    inner = (22, 36, 44)
    outer = BG
    steps = 120
    max_r = size * 0.78
    for i in range(steps, 0, -1):
        t = i / steps
        col = tuple(int(inner[k] + (outer[k] - inner[k]) * t) for k in range(3))
        r = max_r * t
        bd.ellipse([cx - r, cy - r * 0.92, cx + r, cy + r * 0.92], fill=col)

    ring = ring_layer(size, r=size * 150 / 512, width=int(size * 20 / 512), frac=0.72, color=LIME + (255,))
    ring = with_glow(ring, blur=size * 10 / 512)

    icon = bg.convert("RGBA")
    icon.alpha_composite(ring)
    icon = icon.convert("RGB")
    icon.save(path, "PNG")
    print("saved", path)


def write_ios_appicon():
    os.makedirs(IOS_APPICON_DIR, exist_ok=True)
    make_ios_icon(os.path.join(IOS_APPICON_DIR, "AppIcon-1024.png"))

    catalog_contents = '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    with open(os.path.join(IOS_CATALOG_DIR, "Contents.json"), "w") as f:
        f.write(catalog_contents)

    appicon_contents = (
        '{\n'
        '  "images" : [\n'
        '    {\n'
        '      "filename" : "AppIcon-1024.png",\n'
        '      "idiom" : "universal",\n'
        '      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n'
        '    }\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n'
    )
    with open(os.path.join(IOS_APPICON_DIR, "Contents.json"), "w") as f:
        f.write(appicon_contents)
    print("saved", os.path.join(IOS_CATALOG_DIR, "Contents.json"))
    print("saved", os.path.join(IOS_APPICON_DIR, "Contents.json"))


def make_android_foreground(path, size):
    """Ring mark only, transparent background, inset well inside the 66%-diameter safe
    zone Android guarantees stays visible after the launcher applies its own icon shape."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    r = size / 2 * 0.29
    width = max(2, round(size * 0.05))
    ring = ring_layer(size, r=r, width=width, frac=0.72, color=LIME + (255,))
    ring = with_glow(ring, blur=size * 10 / 512, gain=0.9)
    img.alpha_composite(ring)
    img.save(path, "PNG")


def write_android_adaptive_icon():
    for density, size in ANDROID_DENSITIES.items():
        mipmap_dir = os.path.join(ANDROID_RES, f"mipmap-{density}")
        os.makedirs(mipmap_dir, exist_ok=True)
        path = os.path.join(mipmap_dir, "ic_launcher_foreground.png")
        make_android_foreground(path, size)
        print("saved", path)

    values_dir = os.path.join(ANDROID_RES, "values")
    os.makedirs(values_dir, exist_ok=True)
    bg_hex = "#%02X%02X%02X" % BG
    with open(os.path.join(values_dir, "ic_launcher_background.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            f'    <color name="ic_launcher_background">{bg_hex}</color>\n'
            '</resources>\n'
        )

    anydpi_dir = os.path.join(ANDROID_RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi_dir, exist_ok=True)
    adaptive_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi_dir, name), "w") as f:
            f.write(adaptive_xml)
        print("saved", os.path.join(anydpi_dir, name))


if __name__ == "__main__":
    write_ios_appicon()
    write_android_adaptive_icon()
