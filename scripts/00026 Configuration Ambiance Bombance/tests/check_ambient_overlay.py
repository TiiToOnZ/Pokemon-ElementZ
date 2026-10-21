"""Verify native V6 captures, alignment and unchanged PNG/Tiled inputs."""
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).with_name('captures_ambient_overlay')
rows = json.loads((OUT / 'results.json').read_text(encoding='utf-8'))
captures = {r['name']: r for r in rows if 'name' in r}
checks = 0


def check(condition, description):
    global checks
    assert condition, description
    checks += 1


source = Image.open(ROOT / 'graphics/fogs/BourgGuignon_Light.png')
tiled = ET.parse(ROOT / 'Data/Tiled/Maps/023 BourgGuignon.tmx').getroot()
check(source.mode == 'RGBA', 'original RGBA')
check(source.size == (int(tiled.get('width')) * int(tiled.get('tilewidth')),
                      int(tiled.get('height')) * int(tiled.get('tileheight'))), 'full Tiled dimensions')
check(source.size == (2368, 1888), 'actual dimensions, not the obsolete 2048x1632 brief')
check(source.getchannel('A').getextrema() == (77, 233), 'unaltered alpha')
for node in tiled.iter():
    for axis in ('offsetx', 'offsety', 'x', 'y'):
        check(float(node.get(axis, 0)) == 0, 'no hidden Tiled offset')

expected = [0, 0, 64, 128, 128, 128, 128, 64, 0]
times = [720, 1140, 1200, 1230, 1380, 240, 420, 540, 660]
for index, (minute, opacity) in enumerate(zip(times, expected)):
    name = f'{index:02d}_{minute // 60:02d}h{minute % 60:02d}'
    before, after = captures[name + '_before'], captures[name + '_after']
    check(before['fog'] == after['fog'], 'native fog preserved in comparison')
    check(before['tone'] == after['tone'], 'native TJN preserved in comparison')
    check(after['minute'] == minute, 'requested TJN time')
    check((after['overlay'][2] if after['overlay'] else 0) == opacity, 'hourly opacity')
    a, b = [Image.open(OUT / (name + suffix + '.png')).convert('RGB') for suffix in ('_before', '_after')]
    difference = ImageChops.difference(a, b)
    check((difference.getbbox() is None) == (opacity == 0), 'day identical / active overlay visible')
    check(after['fog'][0] == 'clouds' and after['fog'][3:] == [90, [0.5, 0.5], 3000], 'native clouds intact')
    if opacity:
        x, y, _, zoom, width, height = after['overlay']
        check((width, height, zoom) == (2368, 1888, .5), 'native loaded texture and scale')
        check((x, y) == (-after['camera'][0] / 8, -after['camera'][1] / 8), 'world projection')

night = captures['04_23h00_after']
moved = captures['camera_moved_after']
for row in (night, moved):
    x, y, _, zoom, *_ = row['overlay']
    for tile_x, tile_y in ((49.4375, 41.5), (51.5, 41.5), (49.5, 43.3125)):
        sx, sy = round(tile_x * 16 + x), round(tile_y * 16 + y)
        pixel = source.getpixel((round(tile_x * 32), round(tile_y * 32)))
        check(pixel[0] == 255 and pixel[3] < 100, 'provided translucent window at decor coordinate')
        check(0 <= sx < 320 and 0 <= sy < 240, 'window stays in comparison view')

for name in ('battle_first_return', 'menu_return', 'reentry_night', 'loaded_night'):
    check(captures[name]['overlay'][2] == 128, name + ': immediate intensity')
check(captures['rain_clouds_after']['weather'] == 'rain', 'actual rain')
check(captures['rain_clouds_after']['fog'][0] == 'clouds', 'rain and independent clouds')
check(captures['linked_route_border']['map'] == 27, 'native MapLinker crossing')
check(captures['linked_route_border']['overlay'][1] > 0, 'overlay limited to Bourg side of border')
for row in rows:
    if 'transfer' in row:
        check(row['overlay'] == (row['transfer'] == 23), 'no overlay on unrelated maps')
        if row['transfer'] in (36, 80):
            check(row['weather'] == 'fog', 'haunted forest Fog unchanged')

metrics = {}
for name in ('04_23h00_before', '04_23h00_after'):
    image = Image.open(OUT / (name + '.png')).convert('L')
    metrics[name] = round(ImageStat.Stat(image).mean[0], 2)
check(metrics['04_23h00_after'] > 25, 'night screenshot is not an opaque black cover')
report = dict(checks=checks, night_average_luminance=metrics,
              source_sha256=hashlib.sha256((ROOT / 'graphics/fogs/BourgGuignon_Light.png').read_bytes()).hexdigest())
(OUT / 'checks.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))
