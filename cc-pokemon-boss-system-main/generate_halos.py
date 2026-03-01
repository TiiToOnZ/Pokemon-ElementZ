"""Generate 6 boss halo spritesheets (768x384, 8x4 grid, 96x96 frames) - Full aura.

Full-frame aura that covers the entire sprite with oscillating edges
on left, right and top sides. Bottom is anchored at the Pokemon's feet.
"""
import math
from PIL import Image, ImageFilter

FRAME_W, FRAME_H = 96, 128
COLS, ROWS = 8, 4
TOTAL_FRAMES = COLS * ROWS
SHEET_W, SHEET_H = FRAME_W * COLS, FRAME_H * ROWS
OUTPUT_DIR = "../../graphics/interface/battle/boss"


def make_sheet(frames):
    sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        col, row = i % COLS, i // COLS
        sheet.paste(frame, (col * FRAME_W, row * FRAME_H))
    return sheet


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def simple_noise(x, y, seed=0):
    """Simple hash-based pseudo noise in [0, 1]."""
    n = int(x * 374761 + y * 668265 + seed * 1013904223) & 0x7FFFFFFF
    n = (n >> 13) ^ n
    n = (n * (n * n * 60493 + 19990303) + 1376312589) & 0x7FFFFFFF
    return n / 0x7FFFFFFF


def smooth_noise(x, y, seed=0):
    """Interpolated noise for smoother results."""
    ix, iy = int(math.floor(x)), int(math.floor(y))
    fx, fy = x - ix, y - iy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    n00 = simple_noise(ix, iy, seed)
    n10 = simple_noise(ix + 1, iy, seed)
    n01 = simple_noise(ix, iy + 1, seed)
    n11 = simple_noise(ix + 1, iy + 1, seed)
    nx0 = n00 + (n10 - n00) * fx
    nx1 = n01 + (n11 - n01) * fx
    return nx0 + (nx1 - nx0) * fy


def fbm(x, y, seed=0, octaves=4, lacunarity=2.0, gain=0.5):
    """Fractal Brownian Motion - multiple octaves of noise for organic shapes."""
    value = 0.0
    amplitude = 1.0
    frequency = 1.0
    max_val = 0.0
    for _ in range(octaves):
        value += amplitude * smooth_noise(x * frequency, y * frequency, seed)
        max_val += amplitude
        amplitude *= gain
        frequency *= lacunarity
    return value / max_val


def generate_aura(frame_idx, total, palette, config):
    """Generate one frame of an elliptical aura with oscillating edges.

    Base shape is an ellipse (wider than tall, anchored at bottom-center).
    The boundary oscillates with sine waves + FBM noise for organic edges.
    Large soft fade zone eliminates hard borders.

    palette: list of (r, g, b) from core (bright) to edge (dark)
    config: dict with aura parameters
    """
    S = 2  # supersampling factor
    W, H = FRAME_W * S, FRAME_H * S
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pixels = img.load()

    t = frame_idx / total  # animation phase [0, 1)
    phase = t * 2 * math.pi
    seed = config.get("seed", 42)
    time_speed = config.get("time_speed", 3.0)
    core_alpha = config.get("core_alpha", 255)

    # ── Circular time offsets for seamless looping ──
    # Using cos/sin traces a circle in noise space: frame 0 == frame total
    cx = math.cos(phase) * config.get("noise_scroll", 2.0)
    cy = math.sin(phase) * config.get("noise_scroll", 2.0)

    # ── Ellipse shape ──
    # Radii as fraction of frame half-size
    # rx=0.9 means the ellipse nearly touches left/right edges
    # ry=0.85 means it reaches 85% of frame height from the bottom
    rx = config.get("radius_x", 0.90)
    ry = config.get("radius_y", 0.85)

    # ── Edge oscillation ──
    edge_amp = config.get("edge_amplitude", 0.15)       # oscillation amplitude on boundary
    edge_freq = config.get("edge_frequency", 4.0)       # oscillation frequency (per full angle)
    noise_strength = config.get("noise_strength", 0.10)  # FBM distortion on boundary
    noise_scroll = config.get("noise_scroll", 2.0)       # noise scroll speed

    # ── Taper (flame/teardrop shape) ──
    taper_strength = config.get("taper_strength", 0.85)   # 0=ellipse, 1=full taper to point
    taper_power = config.get("taper_power", 1.5)          # curve shape (1=linear, 2=quadratic)

    # ── Soft edge zone ──
    fade_width = config.get("fade_width", 0.30)          # large fade zone for soft edges

    center_x = W / 2.0
    # Ellipse center: horizontally centered, vertically at 40% from bottom
    # This means the ellipse covers mostly the body area and extends upward
    center_y_frac = config.get("center_y", 0.40)
    inv_Hm1 = 1.0 / (H - 1) if H > 1 else 1.0
    inv_half_W = 1.0 / (W / 2.0)

    for py_px in range(H):
        # y: 0.0 at bottom, 1.0 at top
        y = 1.0 - py_px * inv_Hm1

        for px_px in range(W):
            # x: -1.0 to 1.0
            x = (px_px - center_x) * inv_half_W

            # ── Ellipse distance ──
            # Normalized coords relative to ellipse center
            ex = x / rx
            ey = (y - center_y_frac) / ry

            # ── Taper: narrow horizontally above center for flame/teardrop shape ──
            # Based on frame position so the taper reaches max at the top of the frame
            y_above = max(0.0, (y - center_y_frac) / (1.0 - center_y_frac))  # 0 at center, 1 at frame top
            taper = 1.0 - taper_strength * y_above ** taper_power
            taper = max(0.05, taper)
            ex = ex / taper

            # Angle around ellipse center (for oscillation)
            angle = math.atan2(ey, ex)

            # Base ellipse distance (1.0 = on boundary)
            ellipse_dist = math.sqrt(ex * ex + ey * ey)

            # ── Oscillate the boundary ──
            # Sine oscillation (phase = t*2π, loops perfectly)
            osc = edge_amp * math.sin(angle * edge_freq + phase)
            osc += edge_amp * 0.5 * math.sin(angle * edge_freq * 1.7 - phase * 0.8 + 1.0)

            # FBM noise distortion (circular path in noise space for seamless loop)
            n = fbm(angle * 2 + cx,
                    ellipse_dist * 3 + cy,
                    seed=seed, octaves=4)
            osc += (n - 0.5) * noise_strength * 2

            # Effective boundary radius at this angle
            boundary = 1.0 + osc

            # Signed distance: negative = outside, positive = inside
            signed_dist = boundary - ellipse_dist

            # ── Outside with no glow ──
            if signed_dist < -fade_width:
                continue

            # ── Alpha based on distance to boundary ──
            if signed_dist < 0:
                # Outside boundary: fade out
                alpha_factor = 1.0 - (-signed_dist / fade_width)
                alpha_factor = alpha_factor ** 1.5  # smooth curve
            elif signed_dist < fade_width * 0.5:
                # Near boundary inside: slight fade
                alpha_factor = 0.75 + 0.25 * (signed_dist / (fade_width * 0.5))
            else:
                alpha_factor = 1.0

            # ── Interior noise for organic movement ──
            interior_noise = fbm(x * 3 + cx * 0.5,
                                 y * 4 + cy,
                                 seed=seed + 500, octaves=3)

            # ── Color: center = bright (palette[0]), edge = dark (palette[-1]) ──
            edge_ratio = min(1.0, ellipse_dist / boundary) if boundary > 0 else 1.0
            color_t = edge_ratio * 0.7 + interior_noise * 0.3
            color_t = max(0.0, min(1.0, color_t))

            palette_pos = color_t * (len(palette) - 1)
            ci = min(int(palette_pos), len(palette) - 2)
            blend = palette_pos - ci
            r = int(palette[ci][0] + (palette[ci + 1][0] - palette[ci][0]) * blend)
            g = int(palette[ci][1] + (palette[ci + 1][1] - palette[ci][1]) * blend)
            b = int(palette[ci][2] + (palette[ci + 1][2] - palette[ci][2]) * blend)

            # Alpha
            alpha = core_alpha * alpha_factor * (0.85 + 0.15 * interior_noise)

            pixels[px_px, py_px] = (clamp(r), clamp(g), clamp(b), clamp(alpha))

    img = img.filter(ImageFilter.GaussianBlur(radius=1.5))
    img = img.resize((FRAME_W, FRAME_H), Image.LANCZOS)

    # ── Edge mask: force alpha to 0 near frame borders (except bottom) ──
    margin = config.get("edge_mask_margin", 7)  # pixels on the 96x96 frame
    px = img.load()
    for py_m in range(FRAME_H):
        for px_m in range(FRAME_W):
            dist_edge = min(px_m, FRAME_W - 1 - px_m, py_m)  # no bottom
            if dist_edge >= margin:
                continue
            factor = dist_edge / margin
            factor = factor * factor * (3 - 2 * factor)  # smoothstep
            r, g, b, a = px[px_m, py_m]
            if a > 0:
                px[px_m, py_m] = (r, g, b, clamp(a * factor))

    return img


# ─── TYPE AURA CONFIGURATIONS ────────────────────────────────────────

# Base config shared by all types
BASE_CONFIG = dict(
    core_alpha=255,
    radius_x=0.90, radius_y=0.85, center_y=0.40,
    fade_width=0.30,
)


def cfg(seed, time_speed=3.0, edge_amplitude=0.15, edge_frequency=4.0,
        noise_strength=0.10, noise_scroll=2.0, fade_width=0.30, **kw):
    return {**BASE_CONFIG, "seed": seed, "time_speed": time_speed,
            "edge_amplitude": edge_amplitude, "edge_frequency": edge_frequency,
            "noise_strength": noise_strength, "noise_scroll": noise_scroll,
            "fade_width": fade_width, **kw}


HALOS = {
    # ── Normal ──
    "halo_normal": (
        [(200, 195, 170), (170, 165, 140), (140, 135, 110),
         (110, 105, 85), (80, 75, 60), (50, 48, 35)],
        cfg(seed=100, time_speed=2.0, edge_amplitude=0.10, edge_frequency=3.5,
            noise_strength=0.07, noise_scroll=1.2),
    ),
    # ── Fire ──
    "halo_fire": (
        [(255, 160, 60), (240, 110, 30), (210, 70, 15),
         (180, 40, 5), (140, 20, 0), (100, 5, 0)],
        cfg(seed=42, time_speed=3.5, edge_amplitude=0.17, edge_frequency=4.5,
            noise_strength=0.12, noise_scroll=2.5),
    ),
    # ── Water ──
    "halo_water": (
        [(80, 170, 255), (50, 135, 240), (25, 100, 215),
         (10, 70, 185), (0, 45, 150), (0, 20, 110)],
        cfg(seed=137, time_speed=2.5, edge_amplitude=0.12, edge_frequency=4.0,
            noise_strength=0.08, noise_scroll=1.8),
    ),
    # ── Grass ──
    "halo_grass": (
        [(100, 220, 80), (70, 190, 55), (45, 160, 35),
         (25, 130, 20), (10, 100, 10), (0, 65, 0)],
        cfg(seed=256, time_speed=2.5, edge_amplitude=0.14, edge_frequency=3.5,
            noise_strength=0.10, noise_scroll=2.0),
    ),
    # ── Electric ──
    "halo_electric": (
        [(255, 235, 70), (245, 205, 35), (225, 175, 15),
         (200, 145, 0), (170, 115, 0), (130, 80, 0)],
        cfg(seed=314, time_speed=4.5, edge_amplitude=0.18, edge_frequency=5.5,
            noise_strength=0.13, noise_scroll=3.0),
    ),
    # ── Ice ──
    "halo_ice": (
        [(150, 235, 245), (100, 210, 230), (60, 180, 215),
         (30, 150, 195), (10, 115, 170), (0, 80, 135)],
        cfg(seed=180, time_speed=1.8, edge_amplitude=0.10, edge_frequency=4.0,
            noise_strength=0.07, noise_scroll=1.2),
    ),
    # ── Fighting ──
    "halo_fighting": (
        [(220, 75, 55), (195, 55, 38), (165, 38, 25),
         (135, 22, 15), (105, 10, 5), (70, 0, 0)],
        cfg(seed=333, time_speed=3.5, edge_amplitude=0.16, edge_frequency=4.5,
            noise_strength=0.11, noise_scroll=2.5),
    ),
    # ── Poison ──
    "halo_poison": (
        [(185, 85, 210), (155, 60, 180), (125, 40, 150),
         (95, 22, 115), (68, 10, 85), (40, 0, 50)],
        cfg(seed=404, time_speed=2.8, edge_amplitude=0.14, edge_frequency=4.0,
            noise_strength=0.10, noise_scroll=2.0),
    ),
    # ── Ground ──
    "halo_ground": (
        [(240, 215, 125), (215, 185, 95), (185, 155, 68),
         (155, 125, 48), (125, 95, 30), (90, 65, 15)],
        cfg(seed=450, time_speed=2.0, edge_amplitude=0.12, edge_frequency=3.5,
            noise_strength=0.09, noise_scroll=1.5),
    ),
    # ── Flying ──
    "halo_flying": (
        [(185, 165, 255), (155, 135, 238), (125, 108, 215),
         (95, 80, 190), (68, 55, 160), (42, 32, 125)],
        cfg(seed=500, time_speed=3.0, edge_amplitude=0.15, edge_frequency=4.0,
            noise_strength=0.10, noise_scroll=2.2),
    ),
    # ── Psychic ──
    "halo_psychic": (
        [(255, 110, 160), (238, 78, 130), (215, 50, 100),
         (185, 30, 75), (155, 12, 55), (115, 0, 35)],
        cfg(seed=550, time_speed=3.0, edge_amplitude=0.13, edge_frequency=4.5,
            noise_strength=0.09, noise_scroll=2.0),
    ),
    # ── Bug ──
    "halo_bug": (
        [(195, 205, 55), (168, 178, 35), (140, 150, 18),
         (115, 125, 5), (88, 98, 0), (62, 68, 0)],
        cfg(seed=600, time_speed=2.8, edge_amplitude=0.14, edge_frequency=4.0,
            noise_strength=0.10, noise_scroll=2.0),
    ),
    # ── Rock ──
    "halo_rock": (
        [(215, 190, 80), (190, 165, 60), (160, 138, 42),
         (130, 110, 28), (105, 85, 15), (75, 58, 5)],
        cfg(seed=650, time_speed=1.8, edge_amplitude=0.11, edge_frequency=3.5,
            noise_strength=0.08, noise_scroll=1.3),
    ),
    # ── Ghost ──
    "halo_ghost": (
        [(135, 105, 185), (110, 80, 160), (85, 58, 135),
         (62, 38, 110), (42, 22, 82), (22, 10, 55)],
        cfg(seed=666, time_speed=2.5, edge_amplitude=0.14, edge_frequency=3.5,
            noise_strength=0.10, noise_scroll=1.6, fade_width=0.32),
    ),
    # ── Dragon ──
    "halo_dragon": (
        [(135, 75, 255), (108, 50, 232), (80, 30, 205),
         (55, 15, 175), (35, 5, 140), (18, 0, 100)],
        cfg(seed=700, time_speed=4.0, edge_amplitude=0.17, edge_frequency=5.0,
            noise_strength=0.13, noise_scroll=2.8),
    ),
    # ── Dark ──
    "halo_dark": (
        [(135, 110, 90), (110, 85, 68), (85, 62, 48),
         (62, 44, 32), (42, 28, 18), (25, 15, 8)],
        cfg(seed=750, time_speed=2.2, edge_amplitude=0.12, edge_frequency=3.5,
            noise_strength=0.09, noise_scroll=1.4, fade_width=0.32),
    ),
    # ── Steel ──
    "halo_steel": (
        [(205, 205, 230), (180, 180, 205), (155, 155, 180),
         (130, 130, 155), (105, 105, 130), (78, 78, 100)],
        cfg(seed=800, time_speed=2.0, edge_amplitude=0.10, edge_frequency=4.0,
            noise_strength=0.07, noise_scroll=1.2),
    ),
    # ── Fairy ──
    "halo_fairy": (
        [(252, 175, 195), (235, 140, 165), (210, 110, 138),
         (185, 80, 110), (155, 55, 85), (120, 32, 58)],
        cfg(seed=850, time_speed=2.8, edge_amplitude=0.13, edge_frequency=4.5,
            noise_strength=0.09, noise_scroll=1.8),
    ),
}


# ─── MAIN ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    for name, (palette, config) in HALOS.items():
        print(f"Generating {name}...")
        frames = []
        for f in range(TOTAL_FRAMES):
            frame = generate_aura(f, TOTAL_FRAMES, palette, config)
            frames.append(frame)
            print(f"  frame {f + 1}/{TOTAL_FRAMES}", end="\r")
        print()
        sheet = make_sheet(frames)
        path = f"{OUTPUT_DIR}/{name}.png"
        sheet.save(path)
        print(f"  -> Saved {path}")

    print("Done!")
