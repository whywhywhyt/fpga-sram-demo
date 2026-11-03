"""Independent pixel-grid model for the 32x16 light-wall painter."""
from pathlib import Path
import json
import random

ROOT = Path(__file__).resolve().parent
W, H = 32, 16
N = W * H
RNG = random.Random(20261029)
BACKGROUND = [((52 + x // 2) << 16) | ((64 + y) << 8) | (76 + x // 3)
              for y in range(H) for x in range(W)]
frames = []


def frame(name, rect=None, command=0, fill=None, noise=False):
    image = list(BACKGROUND if fill is None else [fill] * N)
    if rect:
        x0, y0, width, height = rect
        for y in range(y0, y0 + height):
            for x in range(x0, x0 + width):
                image[y * W + x] = 0xD8B894
    if noise:
        image = [sum(max(0, min(255, ((value >> shift) & 255) + RNG.randint(-2, 2))) << shift
                     for shift in (16, 8, 0)) for value in image]
    frames.append((name, image, command))


for index in range(6):
    frame(f"warmup/calibration {index}", noise=True)
frame("empty scene")
for x in range(4, 9):
    frame(f"slow move {x}", (x, 5, 3, 4))
for x in (12, 17, 21):
    frame(f"fast move {x}", (x, 5, 3, 4))
for index in range(70):
    frame(f"stationary must not learn away {index}", (21, 5, 3, 4))
for index in range(66):
    frame(f"leave and fade {index}")
frame("isolated tile noise")
frames[-1][1][7 * W + 7] = 0xFFFFFF
for index in range(3):
    frame(f"empty with sensor noise {index}", noise=True)
frame("global lighting change must be blocked", fill=0xFFFFFF)
frame("back to original background")

# PAINT: one centered mark per meaningful movement, then accumulated strokes.
frame("enter paint mode", (3, 4, 3, 4), command=2)
for x in (7, 11, 16, 23):
    frame(f"paint movement {x}", (x, 5, 3, 4))
for index in range(5):
    frame(f"paint holds accumulated strokes {index}", (23, 5, 3, 4))
frame("freeze artwork", command=2)
frame("frozen ignores foreground", (1, 1, 12, 9))
frame("frozen ignores bright scene", fill=0xFFFFFF)

# RIPPLE starts after HOLD, expands one octagonal grid step per processed frame.
frame("enter ripple mode", (15, 6, 3, 4), command=2)
for index in range(14):
    frame(f"ripple expands {index}", (15, 6, 3, 4))
frame("ripple follows moving object", (21, 7, 3, 4))
for index in range(66):
    frame(f"rainbow ripple leaves and fades {index}")
frame("rainbow red center reentry", (10, 6, 3, 4))
frame("return to live", command=2)
frame("live clears old effects", (21, 7, 3, 4))

frame("manual recapture", command=1, fill=0x304050)
for index in range(4):
    frame(f"new background calibration {index}", fill=0x304050)
frame("new background empty", fill=0x304050)
for index in range(6):
    frame(f"new background foreground {index}", (14, 6, 4, 3), fill=0x304050)


def neighbors(index):
    x, y = index % W, index // W
    return [other for other, valid in ((index - 1, x > 0), (index + 1, x < W - 1),
                                       (index - W, y > 0), (index + W, y < H - 1)) if valid]


def channels(value):
    return tuple((value >> shift) & 63 for shift in (12, 6, 0))


def pack(rgb):
    return (rgb[0] << 12) | (rgb[1] << 6) | rgb[2]


def dim(value):
    return max(1, (value + 1) // 2) if value else 0


def palette(energy, fast):
    if energy == 0:
        red = green = blue = 0
    elif energy >= 48:
        red, green, blue = ((energy, energy >> 3, energy - (energy >> 2)) if fast
                            else (energy >> 3, energy, energy - (energy >> 2)))
    elif energy >= 24:
        red, green, blue = energy >> 2, energy >> 2, energy
    else:
        red, green, blue = energy, 0, energy
    return (dim(red) << 16) | (dim(green) << 8) | dim(blue)


def contour_palette(energy):
    return (dim(energy >> 1) << 16) | (dim(energy) << 8) | dim(energy)


def rainbow_palette(energy, distance):
    band = (distance // 2) % 8
    q = energy - energy // 4
    colors = [(energy, 0, 0), (energy, energy // 2, 0), (q, q, 0),
              (0, energy, 0), (0, q, q), (0, 0, energy),
              (energy // 2, 0, energy), (energy // 2, 0, energy)]
    red, green, blue = colors[band]
    return (dim(red) << 16) | (dim(green) << 8) | dim(blue)


def octagonal_distance(dx, dy):
    high, low = max(dx, dy), min(dx, dy)
    return high + (low >> 1)


background = [0] * N
energy = [0] * N
hue = [False] * N
prior_foreground = [False] * N
display = [0] * N
warmup = 2
calibration_count = 0
background_valid = False
effect = 0  # LIVE=0, PAINT=1, HOLD=2, RIPPLE=3
old_center = None
ripple_phase = 0
rainbow_center = (0, 0)
foreground_count = 0
clear_trails = False
output = []
metadata = []

for name, image, command in frames:
    if command == 1:
        background_valid = False
        calibration_count = 0
        warmup = 0
        effect = 0
        old_center = None
        clear_trails = False
    elif command == 2:
        old_effect = effect
        effect = (effect + 1) % 4
        clear_trails = old_effect in (0, 2, 3)
        if old_effect == 2:
            ripple_phase = 0

    current = [pack(tuple(((value >> shift) & 255) >> 2 for shift in (16, 8, 0)))
               for value in image]
    frame_foreground = foreground_count
    if warmup:
        warmup -= 1
        status = 0
    elif effect == 2 and background_valid:
        # HOLD does not touch the output image, trails, or foreground count.
        status = 4
    else:
        calibrating = not background_valid
        if calibrating:
            for index in range(N):
                if calibration_count == 0:
                    background[index] = current[index]
                else:
                    background[index] = pack(tuple((old * 3 + new + 2) // 4
                                                   for old, new in zip(channels(background[index]),
                                                                       channels(current[index]))))
            raw = [False] * N
        else:
            raw = [sum(abs(a - b) for a, b in zip(channels(current[index]),
                                                  channels(background[index]))) >=
                    (8 if prior_foreground[index] else 12) for index in range(N)]

        clean = [raw[index] and any(raw[other] for other in neighbors(index)) for index in range(N)]
        frame_foreground = sum(clean)
        blocked = frame_foreground > (N * 3 // 4)
        if frame_foreground:
            xs = [index % W for index, active in enumerate(clean) if active]
            ys = [index // W for index, active in enumerate(clean) if active]
            center = ((min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2)
        else:
            center = None

        if center is None or old_center is None:
            speed = 0
        else:
            speed = abs(center[0] - old_center[0]) + abs(center[1] - old_center[1])
        fast = old_center is not None and center is not None and speed >= 2
        if effect == 3 and frame_foreground >= 4 and not blocked and not calibrating:
            rainbow_center = center
            if old_center is None:
                ripple_phase = 0

        for index in range(N):
            x, y = index % W, index // W
            core = clean[index] and not calibrating and not blocked
            halo = any(clean[other] for other in neighbors(index)) and not calibrating and not blocked
            contour = core and not all(clean[other] for other in neighbors(index))

            paint_event = False  # baseline regression has no marker and pen stays up
            paint_core = paint_event and center == (x, y)
            paint_halo = paint_event and abs(x - center[0]) <= 1 and abs(y - center[1]) <= 1

            ripple_valid = effect == 3 and frame_foreground >= 4 and not blocked and center is not None
            distance = octagonal_distance(abs(x - center[0]), abs(y - center[1])) if ripple_valid else -1
            ripple_core = ripple_valid and distance == ripple_phase
            ripple_halo = ripple_valid and abs(distance - ripple_phase) == 1

            if effect == 1:
                target = 63 if paint_core else (12 if paint_halo else 0)
            elif effect == 3:
                target = 63 if ripple_core else (28 if ripple_halo else 0)
            else:
                target = 63 if core else (14 if halo else 0)

            old_energy = energy[index]
            decayed = 0 if calibrating or clear_trails else (
                old_energy if effect == 1 else max(0, old_energy - 1))
            next_energy = max(target, decayed)
            if target and target >= decayed:
                hue[index] = (bool(((ripple_phase >> 2) & 1) ^ int(fast)) if effect == 3 else fast)
            energy[index] = next_energy
            prior_foreground[index] = core
            if effect == 3:
                color_distance = octagonal_distance(abs(x - rainbow_center[0]), abs(y - rainbow_center[1]))
                display[index] = rainbow_palette(next_energy, color_distance)
            else:
                display[index] = contour_palette(next_energy) if effect == 0 and contour else palette(next_energy, hue[index])

        foreground_count = frame_foreground
        if calibrating:
            calibration_count += 1
            if calibration_count == 4:
                background_valid = True
            status = 2 if background_valid else 1
        else:
            old_center = None if blocked else center
            status = 5 if blocked else (3 if effect == 1 else (6 if effect == 3 else 2))
            if effect == 3 and frame_foreground >= 4 and not blocked:
                ripple_phase = 0 if ripple_phase >= 38 else ripple_phase + 1
        clear_trails = False

    output.extend(display)
    metadata.append({"name": name, "command": command, "status": status,
                     "foreground_count": frame_foreground,
                     "lit_pixels": sum(value != 0 for value in display),
                     "ripple_phase": ripple_phase, "effect": effect})


def find_frame(label):
    return metadata[next(i for i, item in enumerate(metadata) if item["name"] == label)]


assert find_frame("empty scene")["lit_pixels"] == 0
assert find_frame("freeze artwork")["effect"] == 2
assert find_frame("frozen ignores foreground")["lit_pixels"] == find_frame("freeze artwork")["lit_pixels"]
assert find_frame("frozen ignores bright scene")["lit_pixels"] == find_frame("freeze artwork")["lit_pixels"]
assert find_frame("enter ripple mode")["effect"] == 3
assert find_frame("ripple expands 10")["ripple_phase"] > find_frame("enter ripple mode")["ripple_phase"]
assert find_frame("live clears old effects")["lit_pixels"] > 0
assert find_frame("leave and fade 65")["lit_pixels"] == 0
assert find_frame("rainbow ripple leaves and fades 65")["lit_pixels"] == 0
origin_frame = next(i for i, item in enumerate(metadata) if item["name"] == "enter ripple mode")
assert output[origin_frame*N + 7*W + 16] == 0x200000
reentry_frame = next(i for i, item in enumerate(metadata) if item["name"] == "rainbow red center reentry")
assert output[reentry_frame*N + 7*W + 11] == 0x200000
for index, item in enumerate(metadata):
    if item["effect"] == 3:
        assert all(((value >> shift) & 255) <= 32 for value in output[index*N:(index+1)*N] for shift in (16,8,0))

(ROOT / "input_rgb.hex").write_text("\n".join(f"{value:06x}" for _, image, _ in frames for value in image) + "\n")
(ROOT / "expected_rgb.hex").write_text("\n".join(f"{value:06x}" for value in output) + "\n")
(ROOT / "commands.hex").write_text("\n".join(f"{command:x}" for _, _, command in frames) + "\n")
(ROOT / "status.hex").write_text("\n".join(f"{item['status']:x}" for item in metadata) + "\n")
(ROOT / "counts.hex").write_text("\n".join(f"{item['foreground_count']:03x}" for item in metadata) + "\n")
(ROOT / "vector_metadata.json").write_text(json.dumps({"frames": len(frames), "pixels_per_frame": N,
                                                       "cases": metadata}, indent=2) + "\n")
(ROOT / "vector_count.vh").write_text(f"`define TEST_FRAMES {len(frames)}\n")
print(f"Generated {len(frames)} independent reference frames, {len(output)} pixel comparisons")
