"""Pixel assertions on real LiteRGSS captures; no modified game images."""
import json
from pathlib import Path
from PIL import Image, ImageChops

here = Path(__file__).resolve().parent
root = here.parents[2]
captures = here / 'captures_v4'
native = json.loads((here / 'native_v4_results.json').read_text())

def load(name):
    return Image.open(captures / (name + '.png')).convert('RGB')

def difference(name):
    return ImageChops.difference(load(name + '_with_fireflies'), load(name + '_without_fireflies'))

results = {}
crop_x, crop_y = native['crop'][:2]
zones = [(int((z['x'] - crop_x) * 16), int((z['y'] - crop_y) * 16),
          int((z['x'] + z['width'] - crop_x) * 16), int((z['y'] + z['height'] - crop_y) * 16))
         for z in native['zones']]
for name in ('morning', 'day', 'sunset', 'night', 'rain', 'hardrain', 'fog', 'strong_winds',
             'night_motion_0', 'night_motion_2s', 'night_motion_6s'):
    diff = difference(name)
    changes = [(x, y, max(diff.getpixel((x, y)))) for y in range(240) for x in range(320)
               if any(diff.getpixel((x, y)))]
    for x, y, _ in changes:
        assert any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in zones), 'Escaped zone'
    if name in ('day', 'hardrain', 'strong_winds'):
        assert not changes, f'Forbidden particles: {name}'
    else:
        assert 10 < len(changes) < 21 * 49, f'Missing/oversized fireflies: {name}'
    results[name] = {'changed_pixels': len(changes), 'maximum_difference': max((p[2] for p in changes), default=0)}
assert results['night']['changed_pixels'] > results['sunset']['changed_pixels']
assert results['night']['maximum_difference'] > results['morning']['maximum_difference']
assert results['fog']['changed_pixels'] > 0
assert difference('night_motion_0').tobytes() != difference('night_motion_2s').tobytes()
assert difference('night_motion_2s').tobytes() != difference('night_motion_6s').tobytes()

for name in ('ui', 'dialogue'):
    assert not difference(name).crop(native['ui_band']).getbbox(), f'Particle over {name}'
assert difference('ui_uncovered').crop(native['ui_band']).getbbox(), 'UI witness misses particles'
results['ui_and_dialogue_pixels_unchanged'] = 2 * 320 * 16

mask = Image.open(root / 'graphics/animations/bombance_ambiance/firefly.png').convert('RGBA')
assert mask.size == (7, 7)
assert sum(mask.getpixel((x, y))[3] == 255 for y in range(7) for x in range(7)) == 1
assert all(mask.getpixel((x, y))[3] == 0 for y in range(7) for x in range(7) if x in (0, 6) or y in (0, 6))

# Exact normal-alpha composition; rounding tolerance covers 8-bit GPU blending.
expected = Image.new('RGB', (320, 240))
for x0, y0, opacity in native['alpha_witness']:
    for dy in range(7):
        for dx in range(7):
            x, y = int(x0) + dx - 3, int(y0) + dy - 3
            if not (0 <= x < 320 and 0 <= y < 240):
                continue
            alpha = mask.getpixel((dx, dy))[3]
            alpha = alpha if alpha == 255 else int(alpha * .65 + .5)
            alpha = alpha / 255 * opacity / 255
            background = expected.getpixel((x, y))
            expected.putpixel((x, y), tuple(round(bg * (1 - alpha) + fg * alpha)
                                           for bg, fg in zip(background, (250, 255, 150))))
delta = ImageChops.difference(expected, load('alpha_witness'))
maximum = max(v[1] for v in delta.getextrema())
assert maximum <= 3, f'Unexpected native blending: maximum error {maximum}'
results['native_alpha_maximum_rounding_error'] = maximum
(here / 'firefly_capture_checks.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
print(json.dumps(results, indent=2))
