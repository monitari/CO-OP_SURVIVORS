# 고양이 테마 UI 아이콘

큰 귀·둥근 얼굴·두꺼운 외곽선의 고양이 초상과 발바닥·방울·털실·깃털 장난감
모티프를 사용하는 카툰 아이콘입니다. 기존 속성 색상과 기본/합성 무기의 형태 관계를 유지합니다.
모두 내장 imagegen으로 생성한 투명 PNG이며, 정확한 프롬프트는 [prompts/](prompts/)에 있습니다.
이 폴더(`art/`)는 `.gdignore`가 있어 Godot이 임포트하지 않습니다 — 제작 원본과 기록만 두는 곳이고,
게임이 실제로 읽는 파일은 `assets/atlases/`와 `assets/sprites/`에 있습니다.

UI 이미지 시안과 생성 프롬프트는 [UI 제작 및 이미지 생성 지침](../docs/ui-generation-guidelines.md)의 레이아웃 하드 제약과 production-ready 규칙을 먼저 적용합니다. 정확한 텍스트와 입력 상태는 imagegen 결과가 아니라 Godot UI로 구현합니다.

| 시트 | 원본 크기 | 격자 | 항목 수 |
| --- | --- | --- | --- |
| atlases/survivors.png | 1983×793 | 5×2 | 고양이 10종 |
| atlases/weapons.png | 1402×1122 | 5×4 | 기본 10종 + 합성 10종 |
| atlases/upgrades.png | 1774×887 | 6×3 | 보물 18종 |
| atlases/enemies.png | — | 8칸(불규칙) | 적 7종 + 화분 |

셀은 왼쪽에서 오른쪽, 위에서 아래 순서입니다.

- 초상: lyra, volta, ignis, neve, moro / serin, kael, rian, tera, nova
- 기본 무기: homing, lightning, flame, frost, scythe / chain, orbit, lance, mine, gravity
- 합성 무기: starpiercer, thunder_god, supernova, absolute_zero, black_moon / stigmata, celestial, judgement, ruin_garden, event_horizon
- 보물: might, area, amount, haste, projectile_speed, armor / recovery, magnet, growth, luck, move, vitality / crit, pierce, thorns, resolve, overcharge, greed

**이 시트들은 더 이상 게임이 읽지 않습니다.** 56칸을 전부 잘라내 `assets/sprites/`에 id별 PNG로 커밋했고, 게임은 그 파일만 읽습니다. 다시 자르려면 `python tools/cut_atlas_icons.py`.

### 왜 다시 잘랐는가

처음에는 당시 실행 코드(`icon_catalog._by_id` + `icon_crop.region`)를 그대로 호출해 저장했습니다. 화면 결과는 픽셀 단위로 같았지만, **그 코드 자체에 결함이 있었습니다.** 칸을 96×96으로 줄여서 가장 점수가 높은 덩어리 하나를 찾고 그 덩어리의 **사각형**으로 잘랐기 때문에,

- 사각형 안에 들어온 것은 **옆 칸 그림이라도 딸려왔고** (`black_moon` 오른쪽 위의 흰 블록, `kael` 머리 위의 초록 얼룩)
- 사각형 밖에 있던 것은 **떨어져 나갔습니다** — 흩어진 반짝임, 별 장식, 덩어리 너머로 뻗은 발톱이 잘린 채 남았습니다

42px로 그려질 때는 잘 보이지 않았지만 파일로 꺼내 놓으니 그대로 드러났습니다. `tools/cut_atlas_icons.py`는 96px 대리 이미지 없이 원본 해상도에서 연결 성분을 전부 구한 뒤, **중심이 자기 칸 밖에 있는 성분만 버리고 나머지는 전부 남깁니다.** 오버스캔은 귀나 뾰족한 끝이 칸 경계를 넘어간 경우를 살리려고 있는 것이지 옆 아이콘이 걸어 들어오라고 있는 것이 아니기 때문입니다. 48칸 전부에 대해 잘라낸 픽셀 수가 원래 칸의 내용과 7% 이내로 일치하는 것을 확인했습니다.

### 규격

칸 크기가 제각각인 것은 잘린 내용에 맞춘 native 해상도이기 때문이고, 정규화된 512px 스프라이트(에코·라떼·신규 적·신규 무기)와는 규격이 다릅니다. UI 아이콘은 정사각 캔버스(한 변 = 내용 긴 변 × 1.1)로, 적 아이콘은 여백 없는 tight crop으로 저장합니다. `TextureRect`는 `KEEP_ASPECT_CENTERED`로 그리고 `Enemy.setup`은 텍스처의 긴 변으로 스케일을 정하기 때문에, 이 두 규칙이 예전 `AtlasTexture`의 margin/region과 같은 크기를 만듭니다.

`scripts/ui/icon_catalog.gd`에서 원본 크기를 격자로 나눈 `AtlasTexture`를 캐시해 사용합니다.
현재 카탈로그의 모든 항목에 전용 아트가 있으며, 향후 추가되는 미등록 ID만 임시 도형을 사용합니다.
격자를 변경할 때는 순서 배열과 열/행 인자를 함께 변경하세요. `tests/icon_coverage_test.gd`로 누락을 확인할 수 있습니다.
