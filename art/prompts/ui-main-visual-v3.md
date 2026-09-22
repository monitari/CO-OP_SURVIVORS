# Main visual v3

Generated with the built-in `image_gen` workflow on 2026-09-14.

Outputs:

- `art/originals/ui/backdrops/moonroof_backdrop_v3.png`
- `art/originals/ui/title/moonroof_title_v3.png`
- `assets/ui/backdrops/moonroof_backdrop_v3.png`
- `assets/ui/title/moonroof_title_v3.png`

## Background prompt

```text
Use case: stylized-concept
Asset type: production 16:9 main-menu background for the Godot game
"달빛 옥상 · 간식 수호대"
Primary request: create a brand-new cute midnight Seoul rooftop illustration
whose rendering style matches simple commercial 2D cat character portraits:
very thick deep-navy outlines, round friendly shapes, crisp vector-like
silhouettes, restrained soft cel shading, flat readable color areas, slightly
handmade edges.
Scene/backdrop: a cozy rooftop overlooking a simplified Seoul night skyline,
large warm moon in the upper-right sky, subtle stars, rooftop parapet and a few
cat-feeding props along the bottom corners, small warm lanterns and plants
confined to the outer edges.
Composition/framing: exact wide 16:9 title-screen composition. Keep the
upper-center and middle-center calm, dark, and uncluttered for a large title
logo, two live cat sprites, and menu buttons. Put visual detail mainly along
the far left, far right, and bottom edge. No characters in the artwork.
Lighting/mood: magical but calm moonlit night, welcoming cooperative adventure,
strong readable separation between background and foreground UI.
Color palette: midnight navy #081321, raised blue #14273B, muted blue-gray
#A6B9CF, moon gold #EDC77E, tiny cyan #63DCE6 and amber #FF9F43 accents.
Materials/textures: matte illustrated surfaces, minimal even grain, no
photographic texture.
Constraints: no text, no letters, no numbers, no logo, no interface, no
buttons, no panels, no cats or people, no watermark. Shipped commercial indie
game background. Preserve wide negative space for UI.
Avoid: painterly realism, photorealism, glossy 3D, detailed cinematic concept
art, neon bloom, red horror palette, ornate fantasy architecture, clutter in
the center, fuzzy edges.
```

## Initial logo prompt

```text
Use case: logo-brand
Asset type: transparent game title wordmark for a commercial 2D cute-cat
survivors game
Primary request: create one original Korean title logo that matches round cute
cat portraits with thick deep-navy outlines and simple cel-shaded color areas.
Style/medium: clean vector-like 2D wordmark, bold rounded Korean display
lettering, playful but readable, thick uniform navy outer stroke, cream and
moon-gold main fill, restrained cyan and amber accent shadows. Small cat-ear
silhouette integrated only above the first line and a tiny paw-print separator;
one short chain motif may underline the title.
Composition/framing: centered compact two-line logo, wide landscape silhouette,
generous transparent padding. First line smaller, second line larger.
Text (verbatim): "달빛 옥상" on the first line and "간식 수호대" on the
second line. Render these exact Korean characters once, with no extra letters
or words.
Constraints: genuinely transparent background with clean alpha edges; exact
Korean spelling; extremely readable at 720p; flat 2D production asset; one logo
only; no mockup, no scene, no characters, no rectangular badge, no watermark.
Avoid: glossy 3D extrusion, painterly brushwork, photorealism, dense sparkles,
rainbow colors, thin lettering, fuzzy edges, English text, misspelled Korean,
extra text.
```

The initial logo used a crescent inside the first line and made `옥` ambiguous,
so the selected runtime logo was regenerated with the stricter prompt below.

## Final selected logo prompt

```text
Use case: logo-brand
Asset type: final transparent Korean title wordmark for a commercial cute 2D cat game
Primary request: create one simple, highly legible two-line Korean title logo
matching round cat portraits with thick deep-navy outlines and flat cel-shaded colors.
Text (verbatim): first line "달빛 옥상"; second line "간식 수호대".
Text construction constraint: render every Hangul syllable as a normal complete
readable Korean glyph. The first line must visibly contain exactly four syllable
blocks in this order: 달 / 빛 / 옥 / 상. The second line must visibly contain
exactly five syllable blocks in this order: 간 / 식 / 수 / 호 / 대. Keep a
clear word space after "달빛" and after "간식". No icon, moon, paw, ear, star,
chain, or decorative shape may replace, overlap, split, or become part of any
Korean letter.
Style/medium: clean flat vector-like 2D lettering; bold rounded Korean display
font; thick uniform deep-navy outer stroke; cream first line and moon-gold second
line; one restrained orange shadow band; no gloss or plastic highlights.
Composition/framing: centered compact two-line wordmark, wide landscape silhouette,
generous transparent margin. Decorative cat ears may sit above the outer outline
only, and a simple cyan chain may sit below the entire wordmark only.
Constraints: genuinely transparent background with clean alpha; exact Korean
spelling; one logo; readable at 720p; no mockup, scene, character, badge, English,
extra text, or watermark.
Avoid: stylized substitution of Hangul strokes, crescent inside text, paw between
syllables, misspelled Korean, 3D extrusion, glossy gradients, checkerboard
background, fuzzy edges.
```
