# Generated image UI

Generated with the built-in imagegen tool on 2026-09-14.
The v3 production source is preserved under `art/originals/ui`; its runtime copy
is normalized to the intended import size and rendered using nine-slice scaling.
Text and input remain native Godot controls so localization and
keyboard/gamepad/mouse navigation keep working.

## Storefront v3

The title screen and menu backdrops share the same flat, outlined rendering as
the runtime cat portraits.

- Background source: `art/originals/ui/moonroof_backdrop_v3.png` (1672 x 941)
- Background runtime: `assets/ui/moonroof_backdrop_v3.png` (1280 x 720)
- Logo source: `art/originals/ui/moonroof_title_v3.png` (1774 x 887)
- Logo runtime: `assets/ui/moonroof_title_v3.png` (1024 x 512, transparent)
- Final prompts and selection notes: `art/prompts/ui-main-visual-v3.md`

## Static title composition v4

- Simplified background source: `art/originals/ui/moonroof_backdrop_v4.png`
- Simplified background runtime: `assets/ui/moonroof_backdrop_v4.png` (1280 x 720)
- Lyra source: `art/originals/ui/title_lyra_fullbody_v1.png`
- Lyra runtime: `assets/ui/title_lyra_fullbody_v1.png` (transparent, 768 px high)
- Volta source: `art/originals/ui/title_volta_fullbody_v1.png`
- Volta runtime: `assets/ui/title_volta_fullbody_v1.png` (transparent, 768 px high)
- Final prompts and selection notes: `art/prompts/ui-title-cats-v1.md`
- Runtime layout: static logo, one full-body cat on each side, no floating head
  portraits, no procedural title stars or character bobbing.

## moonroof_backdrop_v2.png

Status: runtime copy removed — nothing loaded it. Regenerate from this prompt if needed.

Prompt:
Use case: stylized-concept. Asset type: production game menu background, landscape 16:9.
Create a polished hand-painted cartoon midnight Seoul rooftop for a cooperative cute
cat survivors game. Deep navy sky, small stars, warm full moon upper right, distant
city windows, rooftop parapet along bottom, cat-shaped lantern and seated cat silhouette
lower left, snack tin and box lower right, ladder at far right. Cyan moonlit edges
and warm golden accents. Large central 75 percent of canvas is calm dark navy negative
space for real UI overlays. No text, no letters, no logo, no buttons, no interface frames.
Rich illustration matching a cozy magical cat rooftop game, crisp high resolution.
Save as a project-ready background image.

## moonroof_panel_v2.png

Status: runtime copy removed — nothing loaded it. Regenerate from this prompt if needed.

Prompt:
Use case: ui-mockup. Asset type: single reusable nine-slice game UI panel texture.
Generate ONE rectangular panel filling the image with a thin cyan luminous bevel
border and subtly rounded corners. Entire inside opaque deep midnight navy, almost
flat and quiet, very subtle hand painted satin glass texture. Tiny warm gold rivets
confined to four corners. Cozy magical moonlit rooftop cat game aesthetic. Aspect
ratio 3:2. Panel precisely front facing and symmetric, border inset only 8 pixels
from edge. No text no icons no symbols no characters no multiple panels no scenery.
All central 85 percent clear uniformly dark to hold dynamic labels. Actual production
texture not mockup screenshot.

## character_panel_v3.png

Status: runtime copy removed — menu panels are now drawn as translucent overlays
(`CatTheme.image_surface`). The source stays under `art/originals/ui/`.

- Source: `art/originals/ui/character_panel_v3.png` (1536 x 1024)
- Runtime: `assets/ui/character_panel_v3.png` (384 x 256)
- Godot use: shared `StyleBoxTexture` with 16 px texture margins

Prompt:

```text
Use case: ui-mockup
Asset type: reusable opaque full-bleed Godot StyleBoxTexture nine-slice panel
Input images: Image 1 is a style reference for the navy fill, thin blue-gray border,
and tiny gold corner accents only.

Primary request: generate exactly ONE flat rectangular game UI panel texture. THE
ENTIRE IMAGE CANVAS IS THE PANEL. There is no outside area, no margin, no backdrop,
and no transparency preview. The panel fill reaches every canvas edge. Use square
outer canvas corners so every corner pixel belongs to the panel texture. Draw one
thin neutral pale blue-gray border exactly 16 pixels inside all four canvas edges,
a restrained dark inner keyline, and tiny moon-gold L-shaped highlights confined to
the four fixed corner caps. The center and all long edge spans are uniform and safe
for nine-slice stretching.

Composition/framing: full-bleed 3:2 landscape texture, exact front-facing orthographic
view. No object floating on a background. No empty area around the panel. No drop
shadow beyond the border because there is no beyond-canvas area.
Style/medium: shipped commercial 2D game UI asset, crisp engine-rendered edges, clean
and system-driven, only two depth levels.
Color palette: full-canvas deep navy #101B30 with slightly darker #0D182A edge zone;
thin neutral border #A6B9CF; tiny restrained moon-gold #EDC77E corner accents.
Materials/textures: nearly flat matte navy, very subtle even grain only; no
directional gradient, lighting hotspot, scenery, or vignette.

Nine-slice constraints:
- canvas edge to 12 percent inward is the fixed corner/edge cap
- middle 76 percent of top and bottom edges is one perfectly straight,
  decoration-free span
- middle 76 percent of left and right edges is one perfectly straight,
  decoration-free span
- central 76 percent by 76 percent is completely uniform, mark-free navy
- identical border thickness on all four sides
- perfectly symmetric left/right and top/bottom
- legible when downscaled to 384 x 256 and resized to wide or tall UI panels

Text: none.
Constraints: opaque full-bleed panel texture; every pixel must be navy panel artwork,
border, or corner accent. Exactly one panel. No text, letters, numbers, icons, cats,
controls, logos, watermark, transparency, checkerboard, white margin, gray margin,
scene, mockup screenshot, or multiple variants.
Avoid: rounded object silhouette floating inside canvas, any exposed background,
checkerboard pattern, perspective, asymmetry, glossy sci-fi neon, bloom, ornate
fantasy decoration, noisy texture, central highlight, uneven borders.
```
