# 밸런스 확장 아이콘 제작 기록

2026-09-06 · 내장 imagegen 사용 · 투명 PNG. 생성 결과의 배경 알파를 검사한 뒤
개별 파일로 잘랐습니다. 제작 원본은 `art/atlases/hybrid_fusions.png`와
`art/atlases/new_treasures.png`, 런타임 파일은 `assets/sprites/`에 있습니다.

## 무기+무기 합성 6종

기존 `weapons.png`를 화풍 기준 이미지로 사용했습니다. 3×2 셀 순서는
`comet_storm`, `cream_volcano`, `glacial_satellite`, `eclipse_lance`,
`singularity_mine`, `return_bell`입니다.

> Create exactly 6 distinct fused weapon icons in a strict 3 columns x 2 rows
> transparent atlas. Match the reference's chunky cute cat-magic sticker icon
> language, dark navy outline and saturated pastel fills. Combine, in order:
> cat-star comet + thundercloud; paw-flame volcano + milk wave; snowflake + yarn
> planet; crescent claw + feather lance; cat-eye vortex + paw-rune mines; winged
> collar bell + returning fish boomerangs. No text, frames or backgrounds.

첫 결과는 투명 RGB에 색이 남아 있었으나 알파는 0이었습니다. 배경 추출 편집으로
아이콘 모양을 고정하고 모든 여백이 실제 alpha 0임을 다시 확인했습니다.

## 보물 2종

기존 `upgrades.png`를 화풍 기준 이미지로 사용했습니다. 2×1 셀 순서는
`duration`, `curse`입니다.

> Create exactly two treasure icons: a moonlit cat-ear hourglass with cyan glass
> and deep-blue sand; an upside-down cracked collar bell with a violet curse wisp
> and red warning glint. Match the reference's rounded hand-drawn treasure style,
> thick navy outline and matte pastel fills. Genuine transparent background; no
> text, labels, frames or characters.

초안의 체크무늬가 실제 픽셀이어서 사용하지 않았고, 배경 추출 편집본에서 코너와
셀 경계의 alpha가 0임을 검사한 뒤 잘랐습니다.
