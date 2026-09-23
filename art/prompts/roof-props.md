# 옥상 배경 소품 스프라이트

2026-09-23 · OpenAI 내장 `imagegen` 사용 · 캐릭터 시트 화풍 재제작 · 소품별 독립 PNG

기존 `RoofLayout.KINDS`의 서 있는 소품 19종을 코드 도형 대신 사용할 수 있는
손그림 스프라이트로 제작했다. 2차 생성은 사용자가 제공한 적 시트를 화풍 참조로 삼아
굵은 잉크선·과장된 실루엣·셀 셰이딩을 통일했다. 현재 출력은 실제 투명 배경이며,
`scripts/tools/normalize_roof_prop_sprites.gd`는 alpha를 그대로 보존한다. 과거의 불투명
체크무늬/종이 출력도 다시 빌드할 수 있도록 중립 배경 제거 경로는 남겨 두었다.

- 생성 원본: `art/originals/environment/props/*_raw.png`
- 투명 고해상도 원본: `art/originals/environment/props/*.png`
- 런타임 크기: `assets/environment/props/*.png` — 게임 단위당 2텍셀(아래 가시 영역은 게임 단위)
- 모든 런타임 텍스처는 `mipmaps/generate=true`, `fix_alpha_border=true`
- 바닥 그림자와 접촉광은 기존 `ArenaFloor`가 그리므로 스프라이트에는 굽지 않았다.

## 공통 프롬프트

```text
Use case: stylized-concept
Asset type: one isolated production-ready 2D rooftop environment prop sprite
for a cute Korean indie arcade survival game

Image 1 is a strict visual-style reference only. Match its polished cute
action-game sprite language: thick dark-navy tapered ink outline, confident
linework, chunky rounded silhouette, crisp two-to-three-step cel shading,
selective painted wear and controlled highlights. Do not copy its characters
or sheet layout. The prop should remain secondary to actors through its muted
night palette, not through weak edges or muddy values.

Camera: orthographic elevated 2.5D three-quarter rooftop view, upright billboard
sprite, front/near edge at bottom, entire object visible, centered with safe
padding.

Lighting: cool moonlight from upper left and a subtle warm rim from lower right;
night-friendly midtones and the same contrast hierarchy as the reference.

Output: genuine alpha transparency outside the object; no checkerboard painted
into the image, scenery, floor, cast shadow, contact shadow, glow field, frame,
text, logo, watermark, characters, faces, or unrelated objects. Exactly one
complete prop grouping, centered with generous margin and every contact point
on one ground line. No fragile one-pixel details. Clean antialiased silhouette
without halo. Not photorealistic, vector-flat clip art, pixel art, or 3D.
```

사용자가 대화에 첨부한 적 시트를 첫 물탱크의 직접 화풍 참조로 사용했다. 이후 18종은
그 물탱크와 직전 결과를 연속 앵커로 사용해 외곽선 굵기, 금속의 청회색, 오른쪽의 작은
난색 림이 흔들리지 않게 했다. 각 표의 요청 요약을 공통 프롬프트 뒤에 한 줄씩 붙여
소품별로 별도 생성했다.

## 소품별 요청과 런타임 가시 영역

| 파일 | 가시 영역 | 요청 요약 |
|---|---:|---|
| `water_tower.png` | 108×214 | 네 가새 다리의 청회색 원통 탱크, 원뿔 뚜껑·사다리·녹 흔적 |
| `laundry.png` | 216×120 | 굵은 기둥 둘, 처진 밧줄, 큰 천 세 장과 바닥 빨래 바구니 |
| `lights.png` | 260×110 | 기둥 둘과 굵게 처진 케이블, 따뜻한 전구 여섯 개, 외부 후광 없음 |
| `antenna.png` | 72×196 | 튼튼한 중앙 마스트, 굵은 가로 수신봉, 빨간 경고등과 중량 받침 |
| `tree_pot.png` | 104×204 | 낡은 테라코타 화분, 짧은 줄기, 큰 잎 덩어리의 둥근 수관 |
| `parasol.png` | 120×178 | 적색·크림 줄무늬 갓, 굵은 중앙 봉과 원형 중량 받침 |
| `chimney.png` | 54×162 | 좁은 적갈색 벽돌 굴뚝, 회색 금속 캡과 어두운 배기구 |
| `ac_unit.png` | 92×92 | 낮은 청회색 실외기, 큰 앞면 팬·측면 통풍구·짧은 발 |
| `boxes.png` | 80×118 | 크기가 다른 테이프 상자 세 개, 찌그러진 모서리, 무표기 |
| `milk_crate.png` | 58×76 | 굵고 둥근 격자의 빈 청록색 플라스틱 상자 |
| `garden.png` | 150×96 | 낮은 나무 텃밭, 상추·허브·무의 큰 잎 덩어리 |
| `bench.png` | 120×96 | 굵은 나무 판자 세 장과 짙은 금속 다리의 짧은 벤치 |
| `turbine.png` | 48×80 | 낮은 원통 받침과 둥근 리브형 터빈 환풍기 머리 |
| `cat_house.png` | 72×112 | 박공지붕 고양이 집, 둥근 빈 출입구와 작은 줄무늬 천막 |
| `fish_rack.png` | 140×94 | A형 나무 건조대와 세로로 매단 은빛 생선 네 마리 |
| `pots.png` | 88×90 | 로즈메리·민트·넓은 잎 허브를 심은 테라코타 화분 세 개 |
| `solar.png` | 104×88 | 낮은 지지대의 기울어진 남색 태양광 패널과 달빛 반사 |
| `skylight.png` | 110×74 | 낮은 낡은 금속 프레임과 두 줄 달빛이 비친 푸른 유리 |
| `dish.png` | 68×96 | 낮은 타원 받침, 가는 마스트, 왼쪽 위를 보는 작은 위성 접시 |

안테나와 화분 나무는 첫 생성본의 비율이 `RoofLayout`의 세로형 `cover`와 달라,
각각 72:196 및 104:204 실루엣으로 한 번 더 생성한 교정본을 최종 선택했다.
굴뚝과 전구줄도 같은 치수 검수를 거쳐 각각 54:162의 좁은 기둥과 260:110의
높은 양쪽 기둥 비율로 교정했다.
