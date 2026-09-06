"""User-approved background removal and padding only; preserves source PNGs."""
from pathlib import Path
import shutil
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/sprites"
SOURCES = ROOT / "art/originals"
## Visible content on the 512px canvas, leaving the 28px safe margin the icon
## test checks for. Every icon is scaled until this much of it survives the
## resample, so they sit at one size beside each other.
CONTENT = 444
## Scratch canvas the scaled crop is measured on before it is centred. Wider than
## 512 so an over-large intermediate can still be measured instead of clipped.
OVERSIZE = 768


def normalize(path):
    source = SOURCES / path.relative_to(ART)
    source.parent.mkdir(parents=True, exist_ok=True)
    if not source.exists():
        shutil.copy2(path, source)
    image = Image.open(source).convert("RGBA")
    alpha = image.getchannel("A")
    removed = 0
    if alpha.getextrema()[0] > 0:
        # Only neutral, bright pixels connected to the image boundary qualify.
        # Dark outlines enclose cream fur, claws and white eye highlights.
        candidates = Image.new("L", image.size)
        candidates.putdata([
            255 if min(r, g, b) >= 210 and max(r, g, b) - min(r, g, b) <= 24 else 0
            for r, g, b, a in image.getdata()
        ])
        for point in [(0, 0), (image.width - 1, 0), (0, image.height - 1),
                      (image.width - 1, image.height - 1)]:
            if candidates.getpixel(point) == 255:
                ImageDraw.floodfill(candidates, point, 128, thresh=0)
        values = list(candidates.getdata())
        removed = values.count(128)
        if removed < image.width * image.height * 0.05:
            raise RuntimeError(f"Unrecognized opaque background: {source}")
        alpha.putdata([0 if mask == 128 else a for mask, a in zip(values, alpha.getdata())])
        # Remove the two source-pixel white matte fringe outside thick ink lines.
        alpha = alpha.filter(ImageFilter.MinFilter(5))
        image.putalpha(alpha)
    box = image.getchannel("A").getbbox()
    if box is None:
        raise RuntimeError(f"Empty art: {source}")
    cut = image.crop(box)
    # Fitting the crop to a fixed box is not the same as giving every icon the
    # same size on screen. Art with a soft edge loses its faintest pixels to the
    # resample, so a crop fitted to 448 could land anywhere from 412 to 448 of
    # actually visible content — an eight percent spread between icons that are
    # meant to read as one set. Measure what survives the resample and correct
    # the scale until it is the same for every icon, then centre on what is
    # visible rather than on the crop that produced it.
    scale = CONTENT
    for _ in range(8):
        work = cut.copy()
        work.thumbnail((scale, scale), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (OVERSIZE, OVERSIZE))
        canvas.alpha_composite(work, ((OVERSIZE - work.width) // 2,
                                      (OVERSIZE - work.height) // 2))
        visible_box = canvas.getchannel("A").getbbox()
        visible = canvas.crop(visible_box)
        longest = max(visible.width, visible.height)
        if longest == CONTENT:
            break
        scale = max(1, round(scale * CONTENT / longest))
    result = Image.new("RGBA", (512, 512))
    result.alpha_composite(visible, ((512 - visible.width) // 2,
                                     (512 - visible.height) // 2))
    result.save(path, optimize=True)
    assert result.getpixel((0, 0))[3] == 0
    print(f"ART_NORMALIZED {path.relative_to(ROOT)} removed={removed} content={visible.size}")


if __name__ == "__main__":
    import sys
    requested = [Path(argument).resolve() for argument in sys.argv[1:]]
    for path in requested or sorted(ART.glob("*/*.png")):
        normalize(path)
