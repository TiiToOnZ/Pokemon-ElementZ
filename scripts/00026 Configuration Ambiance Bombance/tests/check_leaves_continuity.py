"""Check native PSDK captures/telemetry; never edit production settings."""
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = Path(__file__).with_name('captures_leaves_continuity')
data = json.loads((OUTPUT / 'results.json').read_text(encoding='utf-8'))
captures = {row['name']: row for row in data['captures'] if 'name' in row}
checks = 0


def check(condition, description):
    global checks
    assert condition, description
    checks += 1


for name, row in captures.items():
    check((OUTPUT / (name + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), name)
    if not row['particles']:
        continue
    check(len(row['particles']) == 24, name + ': fixed pool')
    cx, cy = [value / 8 for value in row['camera']]
    for p, sprite in zip(row['particles'], row['sprites']):
        check(abs(sprite[0] - (p[0] + math.sin(p[2]) * p[5] - cx)) <= .501, name + ': world X')
        check(abs(sprite[1] - (p[1] - cy)) <= .501, name + ': world Y')
        check(all(math.isfinite(value) for value in p), name + ': numeric state')

for kind in ['wild', 'trainer', 'flee', 'capture']:
    before, after = captures[kind + '_before'], captures[kind + '_first_return']
    delta = after['tick'] - before['tick']
    check(0 <= delta <= 1, kind + ': first map frame, no battle catch-up')
    check(after['visible'] >= 12, kind + ': already populated')
    check(len({s[1] // 60 for s in after['sprites'] if s[3] and 0 <= s[1] < 240}) >= 3,
          kind + ': several heights')
    for p, q in zip(before['particles'], after['particles']):
        check(p[3:11] == q[3:11], kind + ': same speed, drift, sway, appearance')
        check(abs(q[0] - p[0]) <= .15 and abs(q[1] - p[1]) <= .5, kind + ': no restart')

results = {row['battle']: row for row in data['captures'] if 'battle' in row}
check(results['wild']['result'] == results['trainer']['result'] == 0, 'native victories')
check(results['flee']['result'] == 1, 'native flee')
check(results['capture']['caught'], 'native successful capture')
check(results['defeat']['result'] == 2, 'native defeat')
check(captures['defeat_first_return']['map'] == 23 and not captures['defeat_first_return']['particles'],
      'defeat invalidates forest state')
for name in ['entry', 'normal_reentry']:
    row = captures[name]
    check(all(p[1] < row['camera'][1] / 8 for p in row['particles']), 'normal entry from above')
for name in ['motion_15', 'motion_30', 'motion_45']:
    row = captures[name]
    check(row['visible'] >= 15, 'stationary density')

for prev_name, name in [('motion_45', 'camera_right'), ('camera_right', 'camera_left'),
                        ('camera_left', 'camera_up'), ('camera_up', 'camera_down'),
                        ('camera_down', 'camera_diagonal'), ('camera_diagonal', 'camera_return')]:
    before, after = captures[prev_name], captures[name]
    delta = after['tick'] - before['tick']
    dx, dy = [(b - a) / 8 for a, b in zip(before['camera'], after['camera'])]
    check(dx != 0 or dy != 0, 'camera moved')
    verified = 0
    for p, q, a, b in zip(before['particles'], after['particles'], before['sprites'], after['sprites']):
        if abs(q[0] - p[0]) > .2 * delta or abs(q[1] - p[1]) > .5 * delta:
            continue  # A fully offscreen particle may have been recycled.
        check(abs(b[0] - a[0] + dx) <= 1 + .3 * delta, name + ': decor-relative X')
        check(abs(b[1] - a[1] + dy) <= 1 + .5 * delta, name + ': decor-relative Y')
        verified += 1
    check(verified >= 18, name + ': persistent trajectories')

integration = next(row for row in data['captures'] if 'transfers' in row)
check(integration['menu_dialogue_preserved'], 'menu and dialogue')
for row in integration['transfers']:
    check(row['pool'] == (24 if row['map'] == 35 else None), 'map isolation')
    if row['map'] in [36, 80]:
        check(row['weather'] == 'fog', 'native Fog unchanged')

check(hashlib.sha256((ROOT / 'graphics/animations/bombance_ambiance/enchanted_leaves.png').read_bytes()).hexdigest()
      == 'd1c29172272100a419fcdb13f85fcd867a1ef6e72c14454d1298d97ef3e97b8e', 'original leaf texture')
check(hashlib.sha256((ROOT / 'scripts/00026 Configuration Ambiance Bombance/00000 AmbiancesConfig.rb').read_bytes()).hexdigest()
      == 'abdd3eaf1b77b8777d03af67b4426a7ef79b4ca75d7a4df4ea3e790c577808fc', 'current custom settings preserved')
print(f'{checks} checks passed. Native mean: {data["performance"]["average_ms"]:.3f} ms/update.')
