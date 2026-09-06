# 전체 검토 후 수정 기록

## 변경

- 정지 메뉴를 키보드·패드·마우스로 조작. A/Enter 기본 동작은 계속하기. 재시작 확인은 취소 우선이며 400ms 연속 입력 방지.
- 참가·캐릭터·성장·공명 메뉴 마우스 지원. Tab/X 상세 창과 스크롤로 전체 개인/공유 능력치, 선택 카드 원문, 추천 근거, 보유 무기 피해/실제 간격 확인.
- 무기 T7 + 보물 T4 안내를 처음부터 노출. 준비된 합성 카드는 재추첨 제외보다 우선해서 보장. 상한에 도달한 발동 간격/감속/각도/보물 카드 제외.
- 추천은 전체 빌드 대비 한계 화력 증가율을 계산. 발사 수, 낙뢰 감쇠, 적용 가능한 범위, 발동 간격 하한 반영. 생존 상태·합성 재료·공명 해금 가중치 유지. 실제 측정 DPS가 아닌 비교 추정치임을 명시.
- 저장만 되던 치명타를 실제 공격에 연결: 발동당 확률 판정, 피해 2배. 지뢰·후속 폭발도 같은 판정 결과 적용.
- 과충전 표시는 기본 25% + 공유 코어 강화량을 계산. 첫 코어 획득 후 35%.
- 카메라가 근처 보스와 두 플레이어를 함께 담고 상단 HUD 여백 확보. 위험 예고는 아군 공격 효과보다 위에 배치.
- 적 7종과 캣닢 화분의 새 투명 아틀라스 적용. 적은 이동 방향과 무관하게 그림이 똑바로 서며 판정/행동은 유지. 맵 타일 대비 완화.

## 검증 방법과 한계

`tests/review_regression_test.gd`는 입력 안전장치, 마우스 개별 확정, 전체 능력치, 강화 상한, 연속 40회 합성 보장, 상대 화력 계산, 실제 치명타 피해, 적 방향·레이어와 카메라 여백을 검사합니다.

`tests/normal_speed_balance_test.gd`는 1배속·60Hz·정상 체력·기본 자석으로 이동 액션을 입력합니다. 위치를 순간이동시키지 않습니다. 대시/구조 접근과 화면의 추천 카드 선택을 자동화한 90초 회귀 검사이며, 사람 두 명의 플레이테스트를 대체하지 않습니다.

| 시드 | 조합 | 생존 | 첫 다운 | 처치 | 레벨 |
| --- | --- | --- | --- | --- | --- |
| 20260905 | 라이라 + 볼타 | 90초 | 없음 | 138 | 7 |
| 20260905 | 이그니스 + 네베 | 90초 | 없음 | 134 | 7 |
| 20260906 | 이그니스 + 네베 | 90초 | 없음 | 140 | 8 |

각 테스트 최대 물리 delta는 0.0167초. 고배속 무적 기능 검사는 밸런스 결과에서 제외합니다. 난이도 수치를 이 결과만으로 추가 완화하지 않았습니다.

새 회귀 검사 외에 로비, 카드 선택, 합성, 보물, 능력치, 캐릭터 예산, 무기 10종, 공명 조합 55개/효과 25종, 보스 패턴, 대시, 적 풀/파 진행, 필드 아이템, 피드백, 텍스트 배치 검사를 실행했습니다. 렌더러 캡처와 적 유휴 redraw 검사 및 326초 기능 soak도 수행했습니다. 실행 환경의 인증서 경고와 일부 기존 테스트 종료 시 ObjectDB 경고는 별개로 남아 있습니다.

실행 예시 (PowerShell):

```powershell
.godot_runtime\Godot_v4.7.2-stable_win64_console.exe --headless --path . --log-file .godot_runtime/review-regression.log --script res://tests/review_regression_test.gd
$env:CHAINBOUND_TEST_PAIR = '1' # 0: 라이라/볼타, 1: 이그니스/네베
$env:CHAINBOUND_TEST_SEED = '20260905'
.godot_runtime\Godot_v4.7.2-stable_win64_console.exe --headless --path . --log-file .godot_runtime/normal-speed.log --script res://tests/normal_speed_balance_test.gd
```

## 아트 생성 기록

- 모드: 내장 imagegen (별도 CLI/API 키 사용 없음).
- 스타일 참조: `assets/atlases/survivors.png`.
- 최종 에셋: `assets/atlases/enemies.png`, 1774×887 RGBA. 알파 확인 완료.
- 최초 생성은 바탕에 체크무늬가 포함되어 배경 제거 편집을 한 차례 수행. 게임은 `scripts/ui/enemy_icons.gd`의 명시적 영역과 알파 경계를 사용해 개별 그림을 추출합니다.

생성 프롬프트:

> Use case: stylized-concept. Asset type: transparent game sprite atlas for Moonroof, cute cat co-op survivor game. Image 1 is STYLE REFERENCE ONLY: match its navy chunky outlines, soft cel shading, rounded sticker-like cute silhouettes, not realism. Generate a new atlas, 4 columns x 2 rows, square equal cells, total landscape aspect 2:1. Exactly eight separate centered full-body sprites with generous transparent padding in each cell, no overlap, no frames, NO TEXT, no grid lines. Row 1 left to right: (1) mischievous grey snack-thief mouse with pink ears and small cheese, (2) tiny dark plum flea with six legs and orange eyes, (3) grumpy tan bulldog with red collar, (4) purple-black crow with amber beak and spread wings. Row 2 left to right: (5) masked raccoon with rope loop, (6) chunky raccoon wearing a tin-pot helmet and carrying a lid shield, (7) menacing cute round cleaning robot, ivory shell, orange warning light, red eyes, two side brushes, (8) rooftop terracotta planter with green catnip leaves. Three-quarter overhead front-facing views; compact easily readable at 48px. These are cartoon enemies of cats, distinguish from friendly cat portraits. Transparent background genuinely alpha, no ground patches, no cast shadows outside sprite, no glows. Uniform scale occupying about 78% of each cell.

수정 프롬프트:

> Use case: background-extraction. Image 1 is the edit target. Preserve ALL eight sprites, shapes, colors, exact positions, 4 by 2 grid layout and framing. Remove the visible white and grey checkerboard background and replace with genuinely transparent alpha pixels, NOT painted checkerboard. Clean sprite cutouts only, no floor shadows, no background pixels. Do not redesign any sprite. If alpha cannot be produced use uniform solid pure magenta #FF00FF background instead, no gradient or checker pattern.
