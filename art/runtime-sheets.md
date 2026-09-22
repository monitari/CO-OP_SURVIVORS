# 현재 게임에 적용한 시트

2026-09-22 기준. 기존 게임 ID의 이미지 69개를 교체했다.
새 시트의 나머지 셀은 향후 업데이트용이며 카탈로그나 적 출현 목록에 추가하지 않았다.

| 원본 | 배치 | 적용 범위 |
| --- | --- | --- |
| cats/survivors_sheet_v3.png | 6열 × 4행 | 첫 12칸: 기존 고양이 12종 |
| weapons/weapons_sheet_final.png | 6열 × 8행 | 첫 24칸: 기본/강화형 교차 순서 |
| upgrades/treasures_sheet_final.png | 4열 × 11행 | 첫 20칸: 기존 보물 |
| enemies/enemies_sheet_v2.png | 4열 × 8행 | 첫 12칸: 기존 적, 모두 오른쪽 방향 |
| enemies/planter_v2.png | 단독 | 화분 |

경로는 art/originals/ 기준이며, 정확한 셀→ID 대응은
tools/cut_atlas_icons.py의 GRIDS에 있다.

게임은 assets/sprites/의 개별 PNG를 읽는다. UI 아이콘은 내용의 긴 변보다
10% 큰 정사각형으로, 적과 화분은 내용에 밀착해 잘라 기존 표시 배율을 유지한다.
흡혈 보물 lifesteal은 기존 별칭에 따라 curse.png를 사용한다.
이미지를 공유하는 추가 보물 6종도 기존 별칭으로 새 그림을 사용한다.

재추출: python tools/cut_atlas_icons.py

원본 셀과 적용된 이미지 일치 확인: python tools/cut_atlas_icons.py --check

Godot 재임포트 후 icon_coverage_test, unified_art_test,
hybrid_fusion_test로 아이콘 로딩과 적 방향, 강화 흐름을 검증한다.
