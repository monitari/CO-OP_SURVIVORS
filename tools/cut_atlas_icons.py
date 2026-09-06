"""Cuts one PNG per icon out of the archived grid sheets in art/atlases/.

The runtime used to do this on every load, and it did it badly. It shrank the
cell to 96x96, flood-filled for the single best-scoring blob, and cropped to
that blob's bounding rectangle. Two things went wrong with that:

  * anything inside the rectangle came along, including a slice of whatever the
    neighbouring cell had drawn near the shared edge, and
  * anything outside it was lost, so detached sparkles and star charms were
    dropped and shapes that reached past the blob were cut flat.

This keeps every component the icon is actually made of and drops the ones that
belong to a neighbour, at full resolution rather than through a 96px proxy.
A component is a neighbour when its centre sits outside the nominal cell: the
overscan exists so ears and tips that cross the boundary survive, not so the
next icon can walk in.
"""
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
ATLASES = ROOT / "art/atlases"
OUT = ROOT / "assets/sprites"

ALPHA = 25          # keep antialiased outline pixels, not just the solid core
OVERSCAN = 0.08     # room for ears and tips that cross the printed cell edge
JOIN = 0.14         # how far from the body a detached sparkle may still belong
PAD_RATIO = 1.1     # square canvas side, relative to the content's longer edge

GRIDS = {
    "cats": ("survivors.png", 5, 2, [
        "lyra", "volta", "ignis", "neve", "moro", "serin", "kael", "rian", "tera", "nova"]),
    "weapons": ("weapons.png", 5, 4, [
        "homing", "lightning", "flame", "frost", "scythe",
        "chain", "orbit", "lance", "mine", "gravity",
        "starpiercer", "thunder_god", "supernova", "absolute_zero", "black_moon",
        "stigmata", "celestial", "judgement", "ruin_garden", "event_horizon"]),
    "upgrades": ("upgrades.png", 6, 3, [
        "might", "area", "amount", "haste", "projectile_speed", "armor",
        "recovery", "magnet", "growth", "luck", "move", "vitality",
        "crit", "pierce", "thorns", "resolve", "overcharge", "greed"]),
}

# The enemy sheet never had a regular grid — a crow's wings cross into the next
# cell — so it keeps the hand-measured rectangles the runtime used.
ENEMY_REGIONS = [
    ("chaser", 0.035, 0.10, 0.20, 0.38), ("swarm", 0.28, 0.19, 0.18, 0.27),
    ("charger", 0.51, 0.10, 0.19, 0.39), ("shooter", 0.72, 0.10, 0.26, 0.40),
    ("chain_hunter", 0.035, 0.55, 0.205, 0.38), ("bulwark", 0.275, 0.53, 0.185, 0.40),
    ("brute", 0.49, 0.53, 0.205, 0.40), ("planter", 0.75, 0.53, 0.19, 0.40),
]


def cut(atlas, cell, overscan, pad_square):
    """Crop the icon that belongs to `cell`, discarding neighbouring art."""
    x0, y0, x1, y1 = cell
    gx = int(round(min(x1 - x0, y1 - y0) * overscan))
    wx0, wy0 = max(0, x0 - gx), max(0, y0 - gy_clamp(y0, gx))
    wx1, wy1 = min(atlas.width, x1 + gx), min(atlas.height, y1 + gx)
    window = atlas.crop((wx0, wy0, wx1, wy1))
    alpha = np.array(window)[:, :, 3]
    solid = alpha > ALPHA
    labels, count = ndimage.label(solid)
    if count == 0:
        raise RuntimeError("empty cell")
    sizes = ndimage.sum(solid, labels, range(1, count + 1))
    main = int(np.argmax(sizes)) + 1
    objects = ndimage.find_objects(labels)
    ys, xs = objects[main - 1]
    body = (xs.start, ys.start, xs.stop, ys.stop)
    reach = max(x1 - x0, y1 - y0) * JOIN
    # nominal cell expressed in window coordinates
    nx0, ny0, nx1, ny1 = x0 - wx0, y0 - wy0, x1 - wx0, y1 - wy0

    keep = np.zeros_like(solid)
    kept = [body]
    for i in range(1, count + 1):
        yy, xx = objects[i - 1]
        box = (xx.start, yy.start, xx.stop, yy.stop)
        if i != main:
            cx, cy = (box[0] + box[2]) / 2.0, (box[1] + box[3]) / 2.0
            # a neighbour's art is centred outside this cell
            if not (nx0 <= cx < nx1 and ny0 <= cy < ny1):
                continue
            gap = max(body[0] - box[2], box[0] - body[2], body[1] - box[3], box[1] - body[3], 0)
            if gap > reach:
                continue
            kept.append(box)
        keep |= labels == i

    kx0 = min(b[0] for b in kept); ky0 = min(b[1] for b in kept)
    kx1 = max(b[2] for b in kept); ky1 = max(b[3] for b in kept)
    cleaned = np.array(window)
    cleaned[~keep] = 0
    icon = Image.fromarray(cleaned).crop((kx0, ky0, kx1, ky1))
    if not pad_square:
        return icon
    side = int(round(max(icon.size) * PAD_RATIO))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
    return canvas


def gy_clamp(y0, gx):
    return gx if y0 - gx >= 0 else y0


def main():
    written = 0
    for kind, (sheet, cols, rows, order) in GRIDS.items():
        atlas = Image.open(ATLASES / sheet).convert("RGBA")
        cw, ch = atlas.width / cols, atlas.height / rows
        (OUT / kind).mkdir(parents=True, exist_ok=True)
        for index, name in enumerate(order):
            col, row = index % cols, index // cols
            cell = (int(col * cw), int(row * ch), int(col * cw + cw), int(row * ch + ch))
            icon = cut(atlas, cell, OVERSCAN, pad_square=True)
            icon.save(OUT / kind / ("%s.png" % name), optimize=True)
            print("CUT %-9s %-16s %dx%d" % (kind, name, icon.width, icon.height))
            written += 1
    atlas = Image.open(ATLASES / "enemies.png").convert("RGBA")
    (OUT / "enemies").mkdir(parents=True, exist_ok=True)
    for name, rx, ry, rw, rh in ENEMY_REGIONS:
        cell = (int(rx * atlas.width), int(ry * atlas.height),
                int((rx + rw) * atlas.width), int((ry + rh) * atlas.height))
        # Enemies stay tight: Enemy.setup scales the sprite by its longer edge,
        # so padding one would shrink it on the field.
        icon = cut(atlas, cell, 0.0, pad_square=False)
        icon.save(OUT / "enemies" / ("%s.png" % name), optimize=True)
        print("CUT %-9s %-16s %dx%d" % ("enemies", name, icon.width, icon.height))
        written += 1
    print("CUT_DONE %d icons" % written)


if __name__ == "__main__":
    main()
