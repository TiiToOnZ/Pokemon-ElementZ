"""Pixel checks for V3 native captures, including witnesses inside the beams."""
import json
import math
from pathlib import Path
from PIL import Image, ImageChops

here = Path(__file__).resolve().parent
root = here.parents[2]
captures = here / 'captures_v3'

def load(name):
    return Image.open(captures / (name + '.png')).convert('RGB')

def difference(name):
    return ImageChops.difference(load(name + '_with_rays'), load(name + '_without_rays'))

results = {}
for period in ('morning', 'day', 'sunset', 'night', 'rain', 'fog'):
    diff = difference(period)
    pixels = [diff.getpixel((x, y)) for y in range(240) for x in range(320)]
    changed = sum(any(pixel) for pixel in pixels)
    maximum = max(max(pixel) for pixel in pixels)
    if period == 'fog':
        assert changed == 0, f'Forbidden solar light: {period}'
    else:
        assert 100 < changed < 320 * 240 * .4, f'Invisible or fullscreen rays: {period}'
    results[period] = {'changed_pixels': changed, 'max_channel_difference': maximum,
                       'mean_channel_difference': sum(sum(p) for p in pixels) / (320 * 240 * 3)}
assert results['rain']['max_channel_difference'] < results['day']['max_channel_difference'] * .2
assert results['day']['max_channel_difference'] > 48  # preceding V3: 48
night_pixels = list(difference('night').getdata())
assert sum(p[2] for p in night_pixels) > sum(p[0] for p in night_pixels), 'Moonlight must be silver-blue'

protected = difference('protection')
uncovered = difference('uncovered_ground')
characters = {}
for name, x0, y0 in [('player_m_walk', 65, 140), ('0025', 166, 144)]:
    image = Image.open(root / 'graphics/characters' / (name + '.png')).convert('RGBA')
    tested = covered_by_beam = lit = maximum = 0
    for y in range(image.height // 4):
        for x in range(image.width // 4):
            if image.getpixel((x, y))[3] != 255:
                continue
            pos = (x0 + x, y0 + y)
            delta = max(protected.getpixel(pos))
            lit += delta > 0
            maximum = max(maximum, delta)
            covered_by_beam += any(uncovered.getpixel(pos))
            tested += 1
    assert covered_by_beam > 20, f'Protection test misses the beam: {name}'
    assert lit > 20 and maximum < 85, f'Missing or excessive character light: {name}'
    characters[name] = {'opaque_pixels_tested': tested, 'pixels_lit': lit,
                        'max_channel_difference': maximum}
results['characters'] = characters
ui_changed = 0
for y in range(96, 112):
    for x in range(320):
        assert protected.getpixel((x, y)) == (0, 0, 0), 'Ray on interface witness'
        ui_changed += any(uncovered.getpixel((x, y)))
assert ui_changed > 20, 'Interface test misses the beams'
results['ui'] = {'pixels_unchanged': 5120, 'pixels_lit_if_ui_hidden': ui_changed}
assert not difference('dialogue').crop((0, 96, 320, 112)).getbbox(), 'Ray on dialogue viewport'
results['dialogue_viewport_unchanged_pixels'] = 5120
assert difference('motion_00').tobytes() != difference('motion_10s').tobytes()
assert difference('motion_10s').tobytes() != difference('motion_30s').tobytes()

clouds = {}
for state in ('clear', 'partial', 'shadow', 'reappeared'):
    pixels = list(difference('cloud_' + state).getdata())
    clouds[state] = {'changed_pixels': sum(any(p) for p in pixels),
                     'total_difference': sum(sum(p) for p in pixels)}
assert clouds['shadow']['changed_pixels'] == 0
assert 0 < clouds['partial']['total_difference'] < clouds['clear']['total_difference']
assert clouds['reappeared']['changed_pixels'] > 100
results['cloud_cycle'] = clouds

# The measured native shader projection must match the CPU sampling formula,
# including negative origins, FogFix zoom, repeat and pixel-centre coordinates.
native = json.loads((here / 'native_v3_results.json').read_text())
hourly = {}
for hour, count in ((11, 5), (15, 10), (18, 6), (1, 3)):
    assert native['hourly'][str(hour)]['visible'] == count
    assert native['hourly'][str(hour)]['pool'] == 10
    pixels = list(difference(f'hour_{hour:02}').getdata())
    hourly[hour] = {'rays': count, 'changed_pixels': sum(any(p) for p in pixels),
                    'total_difference': sum(sum(p) for p in pixels)}
assert hourly[15]['changed_pixels'] > hourly[18]['changed_pixels'] > hourly[11]['changed_pixels']
assert hourly[15]['total_difference'] > hourly[18]['total_difference'] > hourly[11]['total_difference']
assert hourly[1]['changed_pixels'] > 100
results['hourly'] = hourly
projection = native['cloud_projection']
cloud_texture = Image.open(root / 'graphics/fogs/clouds.png').convert('RGBA')
projected = load('cloud_projection')
for y in range(240):
    for x in range(320):
        px = math.floor(projection['origin'][0] + (x + .5) / projection['zoom'][0]) % cloud_texture.width
        py = math.floor(projection['origin'][1] + (y + .5) / projection['zoom'][1]) % cloud_texture.height
        pixel = cloud_texture.getpixel((px, py))
        alpha = pixel[3] / 255 * projection['opacity'] / 255
        expected = tuple(round(255 * (1 - alpha) + value * alpha) for value in pixel[:3])
        assert max(abs(a - b) for a, b in zip(expected, projected.getpixel((x, y)))) <= 1
results['native_cloud_projection_pixels_verified'] = 320 * 240

crossing = []
hero = Image.open(root / 'graphics/characters/player_m_walk.png').convert('RGBA')
for index, x0 in enumerate((45, 65, 85)):
    diff = difference('player_crossing_' + str(index))
    lit = sum(any(diff.getpixel((x0 + x, 140 + y)))
              for y in range(hero.height // 4) for x in range(hero.width // 4)
              if hero.getpixel((x, y))[3] == 255)
    crossing.append(lit)
assert crossing[1] > 100 and crossing[1] > crossing[0] and crossing[1] > crossing[2]
results['player_crossing_lit_opaque_pixels'] = crossing

mask = Image.open(root / 'graphics/animations/bombance_ambiance/forest_sunlight.png').convert('RGBA')
assert mask.size == (80, 144)
for y in range(mask.height):
    for x in range(mask.width):
        pixel = mask.getpixel((x, y))
        assert pixel[:3] == (255, 255, 255), 'Dark fringe in transparent mask'
        if x in (0, mask.width - 1) or y in (0, mask.height - 1):
            assert pixel[3] == 0, 'Mask cropped at an opaque edge'
(here / 'ray_capture_checks.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
print(json.dumps(results, indent=2))
