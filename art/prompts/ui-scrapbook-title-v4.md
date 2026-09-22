# 스크랩북 타이틀·스냅 이미지 생성 기록

모든 래스터 이미지는 Codex 내장 ImageGen으로 생성했습니다.

## 1920×1080 스크랩북 옥상 배경

- 런타임 파일: `assets/ui/backdrops/moonroof_scrapbook_backdrop_v2.png`
- 원본 보관: `art/originals/ui/backdrops/moonroof_scrapbook_backdrop_v2.png`
- 참조 이미지: `assets/ui/backdrops/moonroof_scrapbook_backdrop_v1.png`
- 생성 결과의 16:9 구도를 유지한 채 고품질 보간으로 정확히 1920×1080에 맞췄습니다.
- 최종 프롬프트:

  > Recreate the supplied moonroof scrapbook backdrop at high resolution for a 1920x1080 game window. Preserve the torn cream paper negative-space shape across the left and center, navy night sky, large warm full moon in the upper-right, distant blue city and mountains, rooftop ledge, cat bowls, warm lanterns, foliage, tape scraps, film-frame edges, paper grain, and vintage screen-print texture. Redraw edges and small details cleanly while retaining the handmade printed-paper look. Use an exact 16:9 landscape composition, keep the left 58% calm for menu cards and title, and keep scenery toward the right and bottom. Background only: no cats, characters, title, logo, words, letters, numbers, UI, buttons, captions, watermark, signature, or long straight decorative divider line.

## 최종 타이틀 로고

- 런타임 파일: `assets/ui/title/moonroof_title_scrapbook_v4.png`
- 원본 보관: `art/originals/ui/title/moonroof_title_scrapbook_v4.png`
- 참조 이미지: `assets/ui/title/moonroof_title_v3.png`, `assets/ui/backdrops/moonroof_scrapbook_backdrop_v1.png`
- 최종 프롬프트:

  > Create a polished transparent-background title logo asset for a Korean cozy co-op indie game. Use the exact two-line Korean text “달빛 옥상” on the first line and “간식 수호대” on the second line. Match the supplied scrapbook rooftop reference: chunky hand-lettered cream and warm yellow letters, coral drop shadow, deep navy ink outline, subtle worn paper texture, playful Steam indie-game key art. Add only tiny integrated motifs such as a crescent moon and cat ears. Keep the silhouette compact and centered. Do not add a chain, underline, horizontal rule, ribbon, plaque, extra caption, watermark, or any other text. Transparent outside the logo. Preserve Korean spelling exactly.

## 정사각 스냅 사진 세트

- 런타임 파일:
  - `assets/ui/title/title_snapshot_ignis_neve_v1.png`
  - `assets/ui/title/title_snapshot_tera_nova_v1.png`
  - `assets/ui/title/title_snapshot_squad_v1.png`
  - `assets/ui/title/title_snapshot_prank_v1.png`
- 원본 시트: `art/originals/ui/title/title_snapshot_sheet_v1.png`
- 생성 방식: 캐릭터 참조를 사용해 2×2 정사각 시트를 만든 뒤 각 칸을 개별 정사각 이미지로 분리했습니다.
- 프롬프트 요약: 이그니스·네베·테라·노바의 고유 색과 특징을 유지한 데포르메 SD 고양이, 간식 쟁탈전·영웅 포즈·단체 포즈·장난 장면, 깔끔한 선화와 평면 채색, 텍스트·로고·UI·워터마크 제외.
