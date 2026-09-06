# 고양이 테마 UI 아이콘

큰 귀·둥근 얼굴·두꺼운 외곽선의 고양이 초상과 발바닥·방울·털실·깃털 장난감
모티프를 사용하는 카툰 아이콘입니다. 기존 속성 색상과 기본/합성 무기의 형태 관계를 유지합니다.
모두 내장 imagegen으로 생성한 투명 PNG이며, 정확한 프롬프트는 [제작 기록](generation-prompts.md)에 있습니다.

| 파일 | 원본 크기 | 격자 | 항목 수 |
| --- | --- | --- | --- |
| survivor_atlas.png | 1983×793 | 5×2 | 고양이 10종 |
| weapon_atlas.png | 1402×1122 | 5×4 | 기본 10종 + 합성 10종 |
| upgrade_atlas.png | 1774×887 | 6×3 | 보물 18종 |

셀은 왼쪽에서 오른쪽, 위에서 아래 순서입니다.

- 초상: lyra, volta, ignis, neve, moro / serin, kael, rian, tera, nova
- 기본 무기: homing, lightning, flame, frost, scythe / chain, orbit, lance, mine, gravity
- 합성 무기: starpiercer, thunder_god, supernova, absolute_zero, black_moon / stigmata, celestial, judgement, ruin_garden, event_horizon
- 보물: might, area, amount, haste, projectile_speed, armor / recovery, magnet, growth, luck, move, vitality / crit, pierce, thorns, resolve, overcharge, greed

`scripts/ui/icon_catalog.gd`에서 원본 크기를 격자로 나눈 `AtlasTexture`를 캐시해 사용합니다.
현재 카탈로그의 모든 항목에 전용 아트가 있으며, 향후 추가되는 미등록 ID만 임시 도형을 사용합니다.
격자를 변경할 때는 순서 배열과 열/행 인자를 함께 변경하세요. `tests/icon_coverage_test.gd`로 누락을 확인할 수 있습니다.
