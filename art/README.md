# 고양이 테마 UI 아이콘

큰 귀·둥근 얼굴·두꺼운 외곽선의 고양이 초상과 발바닥·방울·털실·깃털 장난감
모티프를 사용하는 카툰 아이콘입니다. 기존 속성 색상과 기본/합성 무기의 형태 관계를 유지합니다.
모두 내장 imagegen으로 생성한 투명 PNG이며, 정확한 프롬프트는 [prompts/](prompts/)에 있습니다.
이 폴더(`art/`)는 `.gdignore`가 있어 Godot이 임포트하지 않습니다 — 제작 원본과 기록만 두는 곳이고,
게임이 실제로 읽는 파일은 `assets/sprites/`와 `assets/ui/`에 있습니다.

UI 이미지 시안과 생성 프롬프트는 [UI 제작 및 이미지 생성 지침](../docs/ui-generation-guidelines.md)의 레이아웃 하드 제약과 production-ready 규칙을 먼저 적용합니다. 정확한 텍스트와 입력 상태는 imagegen 결과가 아니라 Godot UI로 구현합니다.

현재 시트와 ID 대응은 [적용 시트](runtime-sheets.md)에 있습니다. 게임은 시트를 직접 읽지 않고
`assets/sprites/`의 개별 PNG 69개를 사용합니다. 원본에서 다시 추출하려면
`python tools/cut_atlas_icons.py`, 일치 여부만 확인하려면 `python tools/cut_atlas_icons.py --check`를 실행하세요.

### 왜 다시 잘랐는가

처음에는 당시 실행 코드(`icon_catalog._by_id` + `icon_crop.region`)를 그대로 호출해 저장했습니다. 화면 결과는 픽셀 단위로 같았지만, **그 코드 자체에 결함이 있었습니다.** 칸을 96×96으로 줄여서 가장 점수가 높은 덩어리 하나를 찾고 그 덩어리의 **사각형**으로 잘랐기 때문에,

- 사각형 안에 들어온 것은 **옆 칸 그림이라도 딸려왔고** (`black_moon` 오른쪽 위의 흰 블록, `kael` 머리 위의 초록 얼룩)
- 사각형 밖에 있던 것은 **떨어져 나갔습니다** — 흩어진 반짝임, 별 장식, 덩어리 너머로 뻗은 발톱이 잘린 채 남았습니다

현재 시트는 각 그림을 320px 셀 안에 배치하므로, 추출기는 셀 경계 안의 알파 영역 전체를 자릅니다. 이전 불규칙 시트를 대상으로 한 오버스캔·연결 성분 판정은 더 이상 사용하지 않습니다.

### 규격

UI 아이콘은 정사각 캔버스(한 변 = 내용 긴 변 × 1.1)로, 적 아이콘은 여백 없는 tight crop으로 저장합니다. `TextureRect`는 `KEEP_ASPECT_CENTERED`로 그리고 `Enemy.setup`은 텍스처의 긴 변으로 스케일을 정합니다.

`scripts/ui/icon_catalog.gd`는 `assets/sprites/`의 개별 PNG를 id로 찾아 캐시합니다. 현재 고양이 12마리의 추출 원본은 `originals/cats/survivors_sheet_v3.png`입니다.
현재 카탈로그의 모든 항목에 전용 아트가 있으며, 향후 추가되는 미등록 ID만 임시 도형을 사용합니다.
원본 시트의 격자를 변경할 때는 `tools/cut_atlas_icons.py`의 순서 배열과 열/행 인자를 함께 변경하세요. `tests/icon_coverage_test.gd`로 누락을 확인할 수 있습니다.
