"""User-approved background removal and padding only; preserves source PNGs."""
from pathlib import Path
import shutil
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/art/unified"
SOURCES = ROOT / "assets/art/sources"


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
    cut.thumbnail((448, 448), Image.Resampling.LANCZOS)
    result = Image.new("RGBA", (512, 512))
    result.alpha_composite(cut, ((512 - cut.width) // 2, (512 - cut.height) // 2))
    result.save(path, optimize=True)
    assert result.getpixel((0, 0))[3] == 0
    print(f"ART_NORMALIZED {path.relative_to(ROOT)} removed={removed} content={cut.size}")


if __name__ == "__main__":
    for path in sorted(ART.glob("*/*.png")):
        normalize(path)
