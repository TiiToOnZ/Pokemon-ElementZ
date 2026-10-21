"""Pixel checks on the native V2 fixture; requires Pillow, no game writes."""
import json
from pathlib import Path
from PIL import Image, ImageChops

here = Path(__file__).resolve().parent
root = here.parents[2]
captures = here / 'captures_v2'

def load(name):
    return Image.open(captures / f'{name}.png').convert('RGB')

results = {}
for period in ('morning', 'day', 'sunset', 'night'):
    on, off = load(period), load(period + '_without_light')
    differences = list(ImageChops.difference(on, off).getdata())
    changed = sum(any(pixel) for pixel in differences)
    assert changed > 100, f'{period}: light invisible'
    results[period] = {
        'changed_pixels': changed,
        'max_channel_difference': max(max(pixel) for pixel in differences),
        'mean_channel_difference': sum(sum(pixel) for pixel in differences) / (320 * 240 * 3),
    }

on, off = load('protection_with_light'), load('protection_without_light')
assert on.crop((0, 224, 320, 240)).tobytes() == off.crop((0, 224, 320, 240)).tobytes()
protected = 0
for name, x0, y0 in [('player_m_walk', 146, 112), ('0025', 171, 116)]:
    character = Image.open(root / 'graphics/characters' / f'{name}.png').convert('RGBA')
    for y in range(character.height // 4):
        for x in range(character.width // 4):
            if character.getpixel((x, y))[3] == 255:
                pos = (x0 + x, y0 + y)
                assert on.getpixel(pos) == off.getpixel(pos), f'Character light overlap: {name} {pos}'
                protected += 1
results['protected_opaque_character_pixels'] = protected
results['protected_ui_pixels'] = 320 * 16
assert load('motion_00').tobytes() != load('motion_10s').tobytes()
assert load('motion_10s').tobytes() != load('motion_30s').tobytes()

# Periodic mask boundary gradients must be ordinary gradients, not a seam.
mask = Image.open(root / 'graphics/animations/bombance_ambiance/diffuse.png').getchannel('A')
edge_x = max(abs(mask.getpixel((0, y)) - mask.getpixel((319, y))) for y in range(240))
edge_y = max(abs(mask.getpixel((x, 0)) - mask.getpixel((x, 239))) for x in range(320))
internal_x = max(abs(mask.getpixel((x, y)) - mask.getpixel((x - 1, y))) for y in range(240) for x in range(1, 320))
internal_y = max(abs(mask.getpixel((x, y)) - mask.getpixel((x, y - 1))) for y in range(1, 240) for x in range(320))
assert edge_x <= internal_x and edge_y <= internal_y
results['mask_max_boundary_gradient_xy'] = [edge_x, edge_y]
results['mask_max_internal_gradient_xy'] = [internal_x, internal_y]
(here / 'capture_checks.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
print(json.dumps(results, indent=2))
