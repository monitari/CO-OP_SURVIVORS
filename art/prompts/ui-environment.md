# Moonroof UI and environment asset pass

Generated with the built-in `image_gen` workflow on 2026-09-07. The generated
HUD raster kept a baked checkerboard after the transparency pass, so it remains
an art reference only. The runtime HUD frame is the clean 9-slice SVG derived
from that reference.

## Integrated gameplay mockup

```text
Use case: ui-mockup
Asset type: polished 16:9 in-game combat screen concept mockup for the existing Godot game
Primary request: Redesign the current gameplay screen into a shippable-looking illustrated asset-based UI and detailed environment while preserving the existing game, characters, combat layout, camera angle, and information architecture. The identity is "two cute cats chained together defending an endless moonlit rooftop."
Scene/backdrop: top-down moonlit city rooftop at night. Replace the plain repeating brick floor with hand-painted slate rooftop tiles, restrained cracks, rain stains, paw prints, patched seams, drains, vents, pipes, antenna bases, small warning markings, and warm window or maintenance-light accents. Keep the central combat area low-detail and low-contrast; concentrate props and storytelling detail near the outer edges. The arena still needs to feel infinitely tileable rather than like one bounded room.
UI: illustrated 2D game HUD frames using deep midnight navy metal, soft cream highlights, moon-gold trim, subtle chain and cat-paw ornaments. Keep P1 cyan/teal on the left and P2 lavender/violet on the right. Create cohesive asset-like frames for both player health panels, central timer/objective panel, and bottom XP bar. Use rounded chunky silhouettes, crisp dark outlines, gentle bevel highlights, and restrained decorative corners. Preserve the current HUD positions and approximate footprints so gameplay view is not reduced.
Style/medium: polished hand-painted 2D indie game UI and environment, cute Korean arcade aesthetic, cohesive with the existing cat sprites and weapon title art; clean production mockup, not generic concept art and not photorealistic.
Composition/framing: exact wide 1280x720-style gameplay framing, fixed top-down camera. Preserve both cats near center with the cyan chain between them, enemies, gems and combat effects. Maintain generous visual clarity around both players.
Lighting/mood: cool blue moonlight, slightly mysterious but playful, warm amber practical lights at the edges, clear character silhouettes.
Color palette: midnight navy and desaturated blue-green rooftop, cream, moon gold, cyan P1, violet P2, small amber accents.
Constraints: change the presentation layer only. Keep the two existing cat designs recognizable and unchanged, keep their scale and positions, keep the chain, enemies, and combat readability. HUD may not overlap the players or enemy field more than the current HUD. No logos, no watermark.
Avoid: excessive clutter in the center, full-screen ornamental border, glossy sci-fi HUD, photorealism, overly bright floor, heavy fog, illegible tiny decorations, extra characters, fake game logo, random English text.
```

## Seamless rooftop floor

```text
Use case: stylized-concept
Asset type: seamless tileable game environment texture for a top-down 2D game
Primary request: Create a perfectly seamless square rooftop-floor texture matching the quiet central play area in the approved mockup.
Scene/backdrop: old urban rooftop paving made from large rectangular slate and concrete slabs, subtle staggered joints, a few restrained hairline cracks, faint rain stains, tiny worn patches, and very sparse faded cat paw prints.
Style/medium: polished hand-painted 2D indie game environment art with crisp dark outlines only where natural; cute Korean arcade game aesthetic; orthographic top-down view.
Composition/framing: flat square texture viewed exactly from above, uniform density, no horizon, no perspective, no border. All four edges must join seamlessly when repeated.
Lighting/mood: soft even cool moonlight with extremely subtle ambient shading; no directional cast shadows.
Color palette: deep desaturated navy, blue-green slate, charcoal grout; low contrast so bright characters, enemies and projectiles remain readable.
Constraints: background floor only; no large focal feature; no UI; no frame; no props; no vents; no pipes; no drains; no crates; no characters; no text; no logos; no watermark.
Avoid: obvious repeating centerpiece, strong highlights, bright cracks, high-frequency noise, perspective distortion, vignette, edge darkening, baked shadows, room walls.
```

## Reusable HUD frame reference

```text
Use case: stylized-concept
Asset type: reusable transparent 9-slice game HUD panel frame texture
Primary request: Create one clean horizontal HUD panel frame that can be resized and reused behind player health, timer, objectives, and boss information.
Subject: a very wide rounded rectangular frame, approximately 6:1 width-to-height, with a deep midnight navy translucent interior, narrow moon-gold outer trim, a subtle cool blue inner highlight, and tiny restrained cat-paw and chain-link corner engravings.
Style/medium: polished hand-painted 2D indie game UI asset, crisp clean silhouette, cohesive with cute cat sprites, production-ready rather than concept art.
Composition/framing: single centered isolated frame on a genuinely transparent canvas; front-facing orthographic UI asset; symmetrical left/right; generous empty stretchable center; consistent border thickness. Keep decorative details only in the four corner caps so the middle and edge spans are safe for 9-slice scaling.
Lighting/mood: subtle bevel highlight from above and soft small shadow, no dramatic lighting.
Color palette: midnight navy, charcoal, muted moon gold, tiny desaturated blue highlight.
Constraints: exactly one frame; no text; no numbers; no icons inside; no health bar; no characters; no logo; no watermark. Strong legibility when reduced to 365 by 86 pixels.
Avoid: ornate fantasy filigree, bright yellow gold, glossy sci-fi neon, large cat ears, protrusions that waste space, busy decoration, perspective, mockup scene, multiple variants, opaque canvas background.
```
