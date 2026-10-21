"""Build the V2 periodic alpha mask; deterministic, no image input or AI asset.

Toroidal Gaussian patches + low-frequency waves. The math is periodic in both
axes, so there is no non-periodic blur/crop at the edges. Two-pixel sampling
keeps the texture compatible with the logical pixel grid. Requires Pillow.
"""
import math
import random
from pathlib import Path
from PIL import Image

rng = random.Random(270026)
width, height = 160, 120
patches = [(rng.random() * width, rng.random() * height,
            rng.uniform(13, 35), rng.uniform(10, 27), rng.uniform(.35, .9))
           for _ in range(11)]
values = []
for y in range(height):
    for x in range(width):
        value = 0.0
        for cx, cy, sx, sy, weight in patches:
            dx = min(abs(x - cx), width - abs(x - cx))
            dy = min(abs(y - cy), height - abs(y - cy))
            value += weight * math.exp(-.5 * ((dx / sx) ** 2 + (dy / sy) ** 2))
        value += .07 * math.sin(2 * math.pi * (x / width + 2 * y / height) + 1.7)
        values.append(value)
low = sorted(values)[int(len(values) * .30)]
high = max(values)
alpha = [round(255 * max(0, (v - low) / (high - low)) ** 1.35) for v in values]
im = Image.new('RGBA', (width, height))
im.putdata([(255, 255, 255, a) for a in alpha])
im = im.resize((320, 240), Image.Resampling.NEAREST)
target = Path(__file__).resolve().parents[3] / 'graphics/animations/bombance_ambiance/diffuse.png'
target.parent.mkdir(parents=True, exist_ok=True)
im.save(target)
print(f'{target}: 320x240 RGBA, alpha 0..{max(alpha)}, mean {sum(alpha)/len(alpha):.2f}')
