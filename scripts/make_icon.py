"""Generates Bobbly's 1024x1024 app icon (opaque PNG, no alpha) with Pillow.

A friendly fishing-float ("bobber") face on a dark pond background, using the
UI theme's colors: page 0x0B1F27/0x13303A, pond 0x5BC2B5, float 0xFF8552.
Usage: python make_icon.py <output.png>
"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4            # supersampling factor
N = 1024 * S

def hexrgb(h):
    return ((h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF)

BG_TOP, BG_BOTTOM = hexrgb(0x13303A), hexrgb(0x0B1F27)
POND, FLOAT, CREAM, INK = hexrgb(0x5BC2B5), hexrgb(0xFF8552), hexrgb(0xF4F1E8), hexrgb(0x0B1F27)

img = Image.new("RGB", (N, N), BG_BOTTOM)
d = ImageDraw.Draw(img)

# Vertical background gradient.
for y in range(N):
    t = y / (N - 1)
    c = tuple(round(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3))
    d.line([(0, y), (N, y)], fill=c)

# Water ripples under the float.
cx, cy, r = N // 2, int(N * 0.47), int(N * 0.27)
for k, (w, alpha) in enumerate([(0.78, 0.55), (0.98, 0.32)]):
    rw, rh = int(N * w / 2), int(N * 0.055 * (1 + k * 0.45))
    ry = int(N * 0.80) + k * int(N * 0.03)
    col = tuple(round(POND[i] * alpha + BG_BOTTOM[i] * (1 - alpha)) for i in range(3))
    d.ellipse([cx - rw, ry - rh, cx + rw, ry + rh], outline=col, width=int(N * 0.012))

# Antenna (the float's stick).
d.rounded_rectangle([cx - N * 0.018, cy - r - N * 0.12, cx + N * 0.018, cy - r + N * 0.02],
                    radius=int(N * 0.018), fill=CREAM)
d.ellipse([cx - N * 0.035, cy - r - N * 0.155, cx + N * 0.035, cy - r - N * 0.085], fill=FLOAT)

# Body: orange top half, teal bottom half, cream band.
box = [cx - r, cy - r, cx + r, cy + r]
d.pieslice(box, 180, 360, fill=FLOAT)
d.pieslice(box, 0, 180, fill=POND)
band = int(N * 0.028)
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).ellipse(box, fill=255)
bandimg = Image.new("RGB", (N, N), CREAM)
bandmask = Image.new("L", (N, N), 0)
ImageDraw.Draw(bandmask).rectangle([0, cy - band, N, cy + band], fill=255)
img.paste(bandimg, (0, 0), Image.composite(bandmask, Image.new("L", (N, N), 0), mask))

# Face on the teal half: two eyes and a smile.
ex, ey, er = int(r * 0.36), cy + int(r * 0.30), int(N * 0.032)
for sx in (-1, 1):
    d.ellipse([cx + sx * ex - er, ey - er, cx + sx * ex + er, ey + er], fill=INK)
    d.ellipse([cx + sx * ex - er * 0.35 + er * 0.25, ey - er * 0.65,
               cx + sx * ex + er * 0.35 + er * 0.25, ey - er * 0.0], fill=CREAM)
sm = int(r * 0.30)
d.arc([cx - sm, ey - sm * 0.2, cx + sm, ey + sm * 1.1], 20, 160, fill=INK, width=int(N * 0.02))

# Cheeks.
ck = int(N * 0.028)
for sx in (-1, 1):
    x = cx + sx * int(r * 0.62)
    col = tuple(round(FLOAT[i] * 0.55 + POND[i] * 0.45) for i in range(3))
    d.ellipse([x - ck, ey + int(r * 0.12) - ck * 0.6, x + ck, ey + int(r * 0.12) + ck * 0.6], fill=col)

out = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
out.save(sys.argv[1], "PNG", optimize=True)
print("wrote", sys.argv[1], out.size, out.mode)
