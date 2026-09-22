"""Export current runtime IDs from the remade sheets; leave future cells unused.

UI icons retain 10% square padding. Enemy images are tight crops, because the
game scales their longest edge to determine body size. --check validates the
exports without writing. Preserve all alpha components inside each 320px cell.
"""
import argparse
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "art/originals"
OUT = ROOT / "assets/sprites"
CELL = 320
PAD_RATIO = 1.1
GRIDS = {
    "cats": ("cats/survivors_sheet_v3.png", 6, 4, [
        "lyra", "volta", "ignis", "neve", "moro", "serin",
        "kael", "rian", "tera", "nova", "echo", "latte"]),
    "weapons": ("weapons/weapons_sheet_final.png", 6, 8, [
        "homing", "starpiercer", "lightning", "thunder_god", "flame", "supernova",
        "frost", "absolute_zero", "scythe", "black_moon", "chain", "stigmata",
        "orbit", "celestial", "lance", "judgement", "mine", "ruin_garden",
        "gravity", "event_horizon", "boomerang", "skipping_stone", "milk", "cream_tide"]),
    "upgrades": ("upgrades/treasures_sheet_final.png", 4, 11, [
        "might", "area", "amount", "haste", "projectile_speed", "duration", "armor", "recovery",
        "move", "vitality", "crit", "pierce", "thorns", "resolve", "overcharge", "greed",
        "magnet", "growth", "luck", "curse"]),  # Existing lifesteal alias uses curse.png.
    "enemies": ("enemies/enemies_sheet_v2.png", 4, 8, [
        "chaser", "swarm", "charger", "shooter", "chain_hunter", "bulwark", "brute", "rat_runner",
        "wasp", "owl", "mole", "hedgehog"]),
}


def cut(atlas, cell, pad_square):
    window = atlas.crop(cell)
    bounds = window.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError(f"Empty source cell: {cell}")
    icon = window.crop(bounds)
    if not pad_square:
        return icon
    side = round(max(icon.size) * PAD_RATIO)
    canvas = Image.new("RGBA", (side, side))
    canvas.paste(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
    return canvas


def exports():
    for kind, (sheet, cols, rows, order) in GRIDS.items():
        with Image.open(SOURCES / sheet) as source:
            atlas = source.convert("RGBA")
        if atlas.size != (cols * CELL, rows * CELL):
            raise ValueError(f"Wrong sheet dimensions: {sheet}: {atlas.size}")
        for index, name in enumerate(order):
            target = OUT / kind / f"{name}.png"
            if not target.is_file():
                raise ValueError(f"Refusing to activate a new runtime ID: {target}")
            x, y = index % cols * CELL, index // cols * CELL
            yield target, cut(atlas, (x, y, x + CELL, y + CELL), kind != "enemies")
    with Image.open(SOURCES / "enemies/planter_v2.png") as source:
        pot = source.convert("RGBA")
    if pot.size != (CELL, CELL):
        raise ValueError(f"Wrong planter dimensions: {pot.size}")
    yield OUT / "enemies/planter.png", cut(pot, (0, 0, CELL, CELL), False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    pending = list(exports())
    for target, icon in pending:
        if args.check:
            with Image.open(target) as saved:
                saved = saved.convert("RGBA")
            if saved.size != icon.size or saved.tobytes() != icon.tobytes():
                raise ValueError(f"Runtime sprite differs from source: {target}")
        else:
            icon.save(target, optimize=True)
        print(f"{'CHECK' if args.check else 'CUT'} {target.relative_to(OUT)} {icon.width}x{icon.height}")
    print(f"SPRITES_{'CHECK' if args.check else 'APPLIED'}: {len(pending)} current assets")


if __name__ == "__main__":
    main()
