"""Render Stilltime logo assets deterministically with PIL.
Outputs: icon (rounded-square app icon, 1024px), full lockup (transparent + dark bg).
"""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

LIME = (194, 247, 77)
BG = (9, 17, 22)
MUTED = (179, 190, 196)
WHITE = (255, 255, 255)

FONT_BOLD = "C:/Windows/Fonts/segoeuib.ttf"
FONT_SEMI = "C:/Windows/Fonts/segoeuib.ttf"


def ring_layer(size, r, width, frac, color, track_alpha=38):
    """Return an RGBA image with track ring + colored arc (frac = fraction filled)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, track_alpha), width=width)
    # arc from -90deg going clockwise frac of circle, with round caps
    start = -90.0
    end = start + 360.0 * frac
    d.arc([c - r, c - r, c + r, c + r], start=start, end=end, fill=color, width=width)
    # round caps: dots at both arc ends
    for ang in (start, end):
        x = c + r * math.cos(math.radians(ang))
        y = c + r * math.sin(math.radians(ang))
        d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=color)
    return img


def with_glow(layer, blur, gain=1.0):
    """Composite a blurred copy under the layer for bloom."""
    glow = layer.filter(ImageFilter.GaussianBlur(blur))
    if gain != 1.0:
        a = glow.getchannel("A").point(lambda v: int(v * gain))
        glow.putalpha(a)
    base = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    base.alpha_composite(glow)
    base.alpha_composite(layer)
    return base


# ---------------------------------------------------------------- icon ----
def make_icon(path, size=1024, radius_ratio=116 / 512):
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # radial-gradient rounded background (numpy-free: concentric ellipses)
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bg)
    cx, cy = size / 2, size * 0.38
    inner = (22, 36, 44)
    outer = BG
    steps = 120
    max_r = size * 0.78
    for i in range(steps, 0, -1):
        t = i / steps
        col = tuple(int(inner[k] + (outer[k] - inner[k]) * t) for k in range(3)) + (255,)
        r = max_r * t
        bd.ellipse([cx - r, cy - r * 0.92, cx + r, cy + r * 0.92], fill=col)

    # rounded-rect mask
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size, size], radius=size * radius_ratio, fill=255)
    icon.paste(bg, (0, 0), mask)

    # ring with bloom
    ring = ring_layer(size, r=size * 150 / 512, width=int(size * 20 / 512), frac=0.72, color=LIME + (255,))
    ring = with_glow(ring, blur=size * 10 / 512)
    icon.alpha_composite(ring)
    icon.save(path)
    print("saved", path)


# ------------------------------------------------------ full lockup -------
def draw_tracked_text(base, xy, text, font, fill, tracking):
    """Draw text with letter tracking (tracking in px added after each glyph)."""
    d = ImageDraw.Draw(base)
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill)
        bbox = d.textbbox((x, y), ch, font=font)
        x = bbox[2] + tracking
    return x  # final pen position


def make_lockup(path, dark_bg=False, scale=4):
    W, H = 312 * scale, 40 * scale
    img = Image.new("RGBA", (W, H), BG + (255,) if dark_bg else (0, 0, 0, 0))

    # small ring mark (matches site header)
    ring_size = 30 * scale
    ring = ring_layer(ring_size, r=13 * scale, width=int(2.4 * scale), frac=0.72, color=LIME + (255,))
    ring = with_glow(ring, blur=2.0 * scale)
    img.alpha_composite(ring, (2 * scale, 5 * scale))

    # wordmark
    f_word = ImageFont.truetype(FONT_BOLD, 15 * scale)
    d = ImageDraw.Draw(img)
    x0, y0 = 46 * scale, 6 * scale
    end_x = draw_tracked_text(img, (x0, y0), "STILLTIME", f_word, WHITE + (255,), 6.9 * scale)

    # tagline
    f_tag = ImageFont.truetype(FONT_SEMI, 7 * scale)
    draw_tracked_text(img, (47 * scale, 26 * scale), "A QUIETER PHONE. A BRIGHTER YOU.", f_tag, MUTED + (255,), 2.55 * scale)

    img.save(path)
    print("saved", path, "text ends at x =", round(end_x / scale, 1), "of", W // scale)


import os
out = os.path.dirname(os.path.abspath(__file__))
make_icon(os.path.join(out, "stilltime-icon-512.png"))
make_lockup(os.path.join(out, "stilltime-logo-transparent.png"), dark_bg=False)
make_lockup(os.path.join(out, "stilltime-logo-dark.png"), dark_bg=True)
