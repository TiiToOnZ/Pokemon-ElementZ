"""Check actual PSDK captures and canopy geometry; never edit image assets."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

from PIL import Image

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[2]
RUBY = Path(os.environ["LOCALAPPDATA"]) / "Programs/pokemon-studio/resources/psdk-binaries/ruby.exe"
CONFIG = BASE.parent / "00000 AmbiancesConfig.rb"
code = "require 'json';load ARGV[0];s=BombanceAmbiance::Settings;puts JSON.generate(map:s::MAPS[35],leaves:s::FALLING_LEAVES_PROFILES[:enchanted_leaves])"
settings = json.loads(subprocess.run([str(RUBY), "-e", code, str(CONFIG)], check=True, capture_output=True).stdout)
results = json.loads((BASE / "captures_enchanted/results.json").read_text())
captures = {c["capture"]: c for c in results["captures"]}
checks = []


def check(condition, message):
    assert condition, message
    checks.append(message)


fog_path = ROOT / "graphics/fogs/eterna-forest-style-fog2.png"
fog = Image.open(fog_path).convert("RGB")
for ray in settings["map"]["rays_positions"]:
    pixel = (round(ray["x"] * 32) % fog.width, round(ray["y"] * 32) % fog.height)
    check(fog.getpixel(pixel)[0] > 150, f"Ray foot inside native canopy opening: {ray['x']},{ray['y']}")

atlas = Image.open(ROOT / "graphics/animations/bombance_ambiance/enchanted_leaves.png").convert("RGBA")
size = settings["leaves"]["frame_size"]
check(atlas.size == (size * settings["leaves"]["variants"], size), "Shared atlas dimensions")
for index in range(settings["leaves"]["variants"]):
    alpha = atlas.crop((index * size, 0, (index + 1) * size, size)).getchannel("A")
    box = alpha.getbbox()
    check(box is not None and box[2] - box[0] <= 8 and box[3] - box[1] <= 8, f"Tiny transparent silhouette {index}")

original_fog = captures["01_original_fog"]["fog"]
for name, capture in captures.items():
    check(capture["fog"] == original_fog, f"Native fog retained: {name}")
    check(Image.open(BASE / "captures_enchanted" / (name + ".png")).size == (320, 240), f"Native 320x240: {name}")
    check(capture["rays"] in (0, None) if capture["period"] == "night" else True, f"No settled night sunlight: {name}")
    check(capture["fireflies"] in (0, None) if capture["period"] == "day" else True, f"No settled day fireflies: {name}")
    if capture["pool"] is not None:
        check(capture["pool"] == settings["leaves"]["count"], f"Fixed leaf pool: {name}")

motion = [captures[n]["leaves_positions"] for n in captures if "motion" in n]
check(len(motion) == 5 and all(a != b for a, b in zip(motion, motion[1:])), "Five successive native movement captures")
check(results["integration"]["menu_tick_unchanged"], "Native menu does not advance simulation")
check(results["integration"]["dialogue_above_map"], "Native dialogue above map viewport")
for transfer in results["integration"]["transfers"]:
    check(bool(transfer["leaves"]) == (transfer["map"] == 35), f"Native transfer cleanup: {transfer['map']}")

report = {"checks": len(checks), "passed": checks,
          "config_sha256": hashlib.sha256(CONFIG.read_bytes()).hexdigest(),
          "original_fog_sha256": hashlib.sha256(fog_path.read_bytes()).hexdigest(),
          "leaf_average_ms_instrumented": results["performance"]["average_ms"]}
(BASE / "enchanted_capture_checks.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(f"PASS: {len(checks)} native capture/geometry/resource checks")
