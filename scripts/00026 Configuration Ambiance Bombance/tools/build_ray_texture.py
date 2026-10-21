"""Deterministic pixel-art mask: irregular shaft and soft ground pool.

No input image, blur filter or runtime generation. Two-pixel sampling; white
RGB everywhere avoids dark fringes. The anchor and body size match SunRays.
"""
import math
from pathlib import Path
from PIL import Image

def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)

pixels = []
for y in range(72):
    for x in range(40):
        px, py = x * 2 + 0.5, y * 2 + 0.5
        t = (py - 16) / 108
        center = 40 + 1.2 * math.sin(py * .075) + .65 * math.sin(py * .19 + .8)
        half_width = 4.5 + 7.5 * max(0, min(1, t))
        half_width *= 1 + .07 * math.sin(py * .17 + 1.3)
        edge = smooth((1 - abs(px - center) / half_width) / .65)
        taper = smooth(t / .22) * smooth((1.06 - t) / .30)
        striation = .82 + .10 * math.sin(px * .51 + py * .014) + .08 * math.sin(px * .93)
        shaft = 225 * edge * taper * striation
        ellipse = ((px - 40) / 25) ** 2 + ((py - 124) / 9) ** 2
        irregular = 1 + .08 * math.sin(px * .32) + .05 * math.cos(py * .47)
        pool = 80 * smooth((1 - ellipse * irregular) / .8)
        pixels.append((255, 255, 255, round(max(shaft, pool))))
image = Image.new('RGBA', (40, 72))
image.putdata(pixels)
image = image.resize((80, 144), Image.Resampling.NEAREST)
target = Path(__file__).resolve().parents[3] / 'graphics/animations/bombance_ambiance/forest_sunlight.png'
target.parent.mkdir(parents=True, exist_ok=True)
image.save(target)
print(f'{target}: 80x144 RGBA, max alpha {max(p[3] for p in pixels)}')
