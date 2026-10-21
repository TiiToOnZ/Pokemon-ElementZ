"""Tiny procedural pixel-art mask, no input image and no blur: one shared 7x7 PNG."""
from pathlib import Path
from PIL import Image

image = Image.new('RGBA', (7, 7), (255, 255, 255, 0))
for y in range(7):
    for x in range(7):
        distance = (x - 3) ** 2 + (y - 3) ** 2
        alpha = {0: 255, 1: 82, 2: 30, 4: 12, 5: 4}.get(distance, 0)
        image.putpixel((x, y), (255, 255, 255, alpha))
target = Path(__file__).resolve().parents[3] / 'graphics/animations/bombance_ambiance/firefly.png'
image.save(target)
print(f'{target}: 7x7 RGBA, one opaque core pixel, transparent border')
