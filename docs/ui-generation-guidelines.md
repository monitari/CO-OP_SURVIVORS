# UI 제작 및 이미지 생성 지침

이 문서는 게임 UI를 직접 구현하거나 imagegen으로 UI 시안을 만들 때 적용하는 최우선 규칙입니다.
런타임 UI는 가능한 한 실제 컴포넌트와 공통 레이아웃 토큰으로 구현하고, 이미지는 분위기·배경·아트 방향을 잡는 참고 자료로 사용합니다.

## 우선순위

다음 순서를 절대적인 우선순위로 둡니다.

1. 레이아웃 정확도
2. 정렬과 공통 기준선
3. 가독성과 정보 위계
4. 시각적 스타일
5. 장식적 세부 묘사

예쁜 장식이나 캐릭터 연출 때문에 정렬, 텍스트 가독성, 조작 가능성을 희생하지 않습니다.

## 공통 레이아웃 규칙

- 모든 UI는 공통 그리드에 맞춥니다. 기본 간격은 8px 그리드를 사용하며, 저장소의 런타임 UI는 `scripts/ui/layout_grid.gd`의 좌표 규칙을 우선합니다.
- 허용하는 spacing scale은 8 / 16 / 24 / 32 / 48px입니다. 임의의 13px, 19px 같은 간격과 수동 오프셋을 만들지 않습니다.
- 같은 계층의 반복 요소는 동일한 템플릿의 복제본이어야 합니다. width, height, 내부 padding, icon box, border radius, border thickness, 텍스트 baseline, 간격을 모두 맞춥니다.
- 같은 행의 요소는 정확히 같은 top/bottom edge를 공유하고, 같은 열의 요소는 정확히 같은 시작선과 끝선을 공유합니다.
- 각 패널은 하나의 고정된 내부 좌측 기준선을 사용합니다. 제목, 설명, 라벨, 수치, 버튼을 서로 다른 x좌표에서 시작하지 않습니다.
- 아이콘과 텍스트는 고정 크기 layout box 안에 넣고, 아이콘·라벨·수치를 visual approximation이 아니라 공통 baseline과 수직 중앙선으로 정렬합니다.
- 같은 용도의 버튼은 동일한 높이, padding, radius, 텍스트 위치를 사용합니다. 상태 차이는 크기 변화가 아니라 색상·테두리·명도 변화로 표현합니다.
- 좌우 메인 패널은 의도적인 비대칭이 아닌 이상 동일한 y좌표에서 시작합니다.
- 텍스트 길이가 달라도 컴포넌트 크기는 바꾸지 않습니다. 제한된 영역에서 줄바꿈, clip, truncation을 사용하고 주변 요소를 밀어내지 않습니다.
- 장식, 고양이 귀, 선, 테두리 포인트, 그림자는 콘텐츠 박스의 기준선과 크기를 변경하지 않습니다.
- `optically balanced`보다 `geometrically aligned`를 우선합니다.

## 고정 그룹 규칙

반복 그룹은 개별 요소를 따로 배치하지 말고 먼저 하나의 bounding box를 정한 뒤 그 안에서 배치합니다.

예를 들어 스탯 행은 다음 구조를 따릅니다.

- 고정 높이의 단일 flex row
- 각 스탯은 동일한 폭의 cell
- 각 cell은 `[24px icon box] [8px gap] [label/value]` 구조
- 세로 중앙과 텍스트 baseline을 모든 cell에서 동일하게 유지
- 개별 스탯에 임의의 y 오프셋을 적용하지 않음

캐릭터 선택 카드, 성장 카드, 버튼, 장비 슬롯, 결과 타일도 같은 원칙으로 구성합니다.

## 화면 구조 명문화

화면을 제작할 때는 먼저 캔버스와 주요 bounding box를 선언합니다. 예시는 다음과 같습니다.

```text
Canvas: 1648 x 926
Outer margin: 64px
Main UI frame: fixed rectangular container

Top title row: 72px height
Character selector row: 12 equal cards, same y, same height, uniform gap
Main content row: two columns with a fixed gap
Bottom information row: aligned to the main content grid
```

화면별로 다음을 명시해야 합니다.

- 캔버스 크기와 바깥 여백
- 행과 열의 개수 및 고정 높이
- 반복 컴포넌트의 width / height
- 패널 내부 padding
- 공유하는 수평선·수직선·baseline
- 텍스트가 넘칠 때의 처리 방식

## 이미지 생성용 하드 제약

imagegen으로 UI 시안을 만들 때는 다음 블록을 프롬프트에 포함합니다.

```text
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
```

## AI 느낌 억제 규칙

UI 시안은 `shipped commercial game UI`, `production-ready`, `engine-rendered`, `clean and system-driven` 방향으로 요청합니다.
`concept art`, `painterly`, `cinematic`, `gorgeous`, `ultra polished`, `vibrant decorative interface`처럼 장식 우선으로 해석될 표현은 줄입니다.

반드시 다음을 지킵니다.

- usability, hierarchy, readability, component consistency를 visual spectacle보다 우선
- crisp edges, 제한된 2~3단계 depth, 일관된 border thickness와 shadow logic
- 배경 일러스트와 전경 UI를 분리
- glow, bloom, bevel, metallic edge, glossy surface, noisy texture를 절제
- 모든 요소가 같은 강도로 빛나지 않게 함
- UI에는 읽기 쉬운 하나의 sans-serif 계열 폰트와 명확한 weight hierarchy 사용
- 버튼은 ornamental object가 아니라 실제로 눌리는 control처럼 보이게 함

다음은 피합니다.

- 랜덤 장식과 불필요한 UI 복잡도
- 요소마다 다른 렌더링 방식
- fuzzy edge, illegible tiny text, decorative clutter
- 모든 요소가 동일하게 빛나는 구성
- UI 컴포넌트까지 회화적·일러스트적으로 처리하는 방식
- 실제 게임에서 구현하기 어려운 장식 구조

## 제작 절차

1. 레이아웃과 컴포넌트 bounding box를 고정합니다.
2. 공통 템플릿을 복제해 반복 요소를 배치합니다.
3. 텍스트, 아이콘, baseline, 상태 스타일을 정리합니다.
4. 장식을 추가하되 콘텐츠 기준선과 hit area를 건드리지 않습니다.
5. 최종 렌더링 전에 alignment pass를 수행합니다.
6. 구현 단계에서는 `docs/ui-guide.md`, `scripts/ui/layout_grid.gd`, 공통 테마 토큰을 함께 확인합니다.

imagegen 결과물은 최종 UI 자체가 아니라 구조·분위기·아트 방향을 검토하는 참고 자료로 취급합니다.
정확한 텍스트, 입력 상태, 반응형 크기, 접근 가능한 조작은 Godot 컨트롤로 구현하고 테스트로 검증합니다.
