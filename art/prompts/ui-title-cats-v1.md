# Main title character and backdrop generation v1

Mode: built-in imagegen.

The first full-body attempts were rejected because they added realistic fur and
anime-style rendering. The selected pair deliberately stays close to the
existing portrait language: round features, thick navy linework, flat fills,
and only one modest cel-shading band.

## Lyra — selected prompt

Create ONE clean full-body gray cat asset on a uniform chroma-green background,
matching the supplied simple flat cartoon portrait and the partner's exact
rendering simplicity and line weight. Medium-gray fur, white round muzzle and
chest, pink inner ears, dark oval eyes with tiny highlights, cyan collar and
cyan star tag, thick smooth dark-navy outline. Vertically composed cute,
slightly chibi body with all four paws and tail visible. Place on the LEFT,
turning and looking screen-right. Alert guardian pose with one lifted paw,
mildly fierce brows, and a friendly mischievous smile. No anime, realistic fur,
painterly detail, 3D, props, text, UI, shadow, or second character. Uniform
chroma green #00FF00 only outside the silhouette.

## Volta — selected prompt

Create ONE matching full-body black-and-white partner in the same simple rounded
construction, head-to-body ratio, flat shapes, modest detail, and thick
dark-navy line weight. White muzzle, chest, and paws; purple collar and
lightning tag. Place on the RIGHT, facing and looking screen-left. Confident
guardian stance with one lifted paw, mildly fierce brows, and a playful smile.
Keep every body part visible. No anime, realistic fur, painterly detail, 3D,
props, text, UI, shadow, or second character. Uniform chroma green #00FF00 only
outside the silhouette.

The generator returned opaque key-color files. The reproducible normalizer at
scripts/tools/chroma_key_generated.gd removes only strongly green pixels,
decontaminates edge spill, crops the silhouette, and creates 768 px runtime
assets with genuine alpha.

## Simplified backdrop — selected prompt

Create a production-ready 16:9 2D game main-menu background, exact 1280x720
composition, matching the simple flat cartoon characters: restrained navy
outlines, flat shapes, gentle cel shading. Broad uncluttered deep-navy sky,
subtle indigo gradient, one small cream crescent moon at upper-right, five or
six tiny stars, and a low rooftop parapet with extremely simplified distant
city silhouettes in the bottom 18 percent. Keep the center and both side zones
quiet. No characters, logo, text, UI, plants, food, lamps, crates, pipes,
antennas, ornate detail, vignette, photorealism, or 3D.
