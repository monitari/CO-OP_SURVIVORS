# Character select grid v2

Generated with the built-in `image_gen` workflow on 2026-09-14.

Output: `art/concepts/character-select-grid-v2.png`

This is an art-direction reference, not a runtime UI texture. Korean text,
input state, focus behavior, and responsive sizing remain native Godot controls.

## Prompt

```text
Use case: ui-mockup
Asset type: production-ready character selection screen concept for the existing Godot game "달빛 옥상 · 간식 수호대"

Primary request: draw a complete shipped-commercial-game character selection interface for a cooperative cute-cat survivors game on a moonlit Seoul rooftop. This is a clean, systematic, engine-rendered interface direction sheet that must be directly implementable with Godot controls, not concept art.

Canvas and bounding boxes:
- Exact 16:9 landscape screen composition, designed for 1280 x 720.
- Outer margin 48 px left/right and 40 px top/bottom.
- One fixed rectangular UI frame within those margins.
- Top title row: fixed 64 px height.
- Character selector row: 12 exact-copy portrait cards in one row, same y coordinate, same width and height, uniform 8 px gaps.
- Main content row: two equal-width player panels with a fixed 16 px center gutter; both panels share identical top and bottom edges.
- Bottom action/help row aligned to the same main content grid.
- All panel content uses 16 px internal padding.

Subject and content:
- Header title text exactly: "오늘 밤의 수호대"
- Twelve cute, distinct, readable cat portrait icons in identical boxes.
- Roster labels exactly once, left to right: "라이라", "볼타", "이그니스", "네베", "모로", "세린", "카일", "리안", "테라", "노바", "에코", "라떼"
- Left panel: P1, selected cat "라이라", cyan ownership accent. Gray-blue short-haired cat portrait.
- Right panel: P2, selected cat "볼타", warm amber-orange ownership accent. Black cat portrait with a small violet lightning motif.
- Each player panel uses exactly the same component template: portrait block, role/title line, fixed four-cell stat row, starting weapon row, two equal secondary controls, and one fixed-height primary ready button.
- Stat row is one fixed-height flex row. Every stat cell is identical and follows [24 px icon box] [8 px gap] [label/value]. Match baselines exactly.
- Primary button label exactly: "준비하기". Secondary button labels exactly: "이전", "다음".
- Do not add random text. Keep all typography large enough to read at 1280 x 720.

Style/medium: engine-rendered 2D game UI, crisp vector-like edges with restrained illustrated cat portraits. Practical reusable components, not painterly art. One highly legible Korean sans-serif family with clear weight hierarchy.
Scene/backdrop: subdued, low-contrast top-down midnight rooftop texture behind the main interface only, with faint slate seams and no props under text.
Color palette: deep midnight navy #080F20; panel navy #101B30; raised navy #20334E; cream #FFF9EA; muted blue gray #A6B9CF; moon gold #EDC77E; P1 cyan #63DCE6; P2 amber orange #FF9F43.
Depth and materials: only 2-3 depth levels; 1 px neutral borders, 2 px active borders, small consistent shadow; mostly flat surfaces. Background and foreground UI clearly separated.

LAYOUT AND ALIGNMENT ARE HARD CONSTRAINTS.

Use a strict 8px grid system throughout the entire interface.
Do not place UI elements freely or approximately.

All repeated components must be exact copies of the same component template:
- identical width and height
- identical internal padding
- identical icon area size
- identical text baseline
- identical border radius
- identical spacing

Every row must share exact horizontal alignment.
Every column must share exact vertical alignment.
Elements in the same row must have matching top and bottom edges.

Use only this spacing scale: 8px, 16px, 24px, 32px, 48px.
Do not invent arbitrary spacing values.

Inside each panel, establish one fixed content left edge.
Titles, labels, statistics, descriptions, and controls must align to this grid.
Decorative elements must not alter content alignment.

Icons and text must be placed inside fixed-size layout boxes.
Align numerical values and labels by baseline, not by visual approximation.

Buttons of the same hierarchy must use identical height, padding, radius, and label positioning.

The left and right main panels must share the same top alignment unless explicitly specified otherwise.

Preserve component dimensions regardless of text length.
Use controlled wrapping, truncation, or smaller text instead of moving adjacent components.

Prioritize geometric consistency over organic or artistic placement.
Before final rendering, perform an alignment pass for shared edges, baselines,
margins, repeated component sizes, and spacing. No accidental 2-10px offsets.

Constraints: usability, hierarchy, readability, and component consistency outrank visual spectacle. State differences are shown only with color, border, and luminance, never by resizing. No overlap, no tilted cards, no free-floating controls, no clipped panels, no watermark, no fake logo.
Avoid: concept art, painterly UI, cinematic composition, ornamental fantasy frames, glossy sci-fi panels, bloom, excessive glow, bevel-heavy metal, noisy textures, random decorations, fuzzy edges, illegible tiny text, mismatched component sizes, approximate alignment, excessive cat-ear protrusions.
```
