# 영어 전면 적용과 동료 요약 판 정돈

- 동료 요약 판: 네 줄을 17px 간격의 고정 좌표에 찍고 있었는데 이 글자 크기에서 Label의 최소 높이는 22px이라 매 줄이 위 줄을 덮었다. 네 줄을 `VBoxContainer`로 쌓고 판의 높이를 내용에서 계산하되 **아래 모서리를 고정**해 위로만 자라게 했다. 손패의 가장 큰 카드가 시작하는 선이 그 아래 모서리이므로, 캡션이 길어져도 카드 위로 내려올 수 없다. 폭은 270 → 290px, 글줄은 `EditorialUI.fit_text`로 상자에 맞을 때까지 한 단계씩 줄인다.
- 부채꼴 위 호 캡션: 가운데 카드의 분류 테이프가 카드 위로 10px 튀어나와 호의 가장 낮은 지점과 맞닿았다. apex 38 → 26.
- 번역 적용: 실행 중에 조합되는 문장은 Godot의 자동 캡션 번역이 닿지 않는다. 카드의 본문·추천 이유·태그, 전투 알림, HUD 수치, 결과·빌드 시트, LAN 상태, 보물 효과문, 공명 이름과 설명을 모두 번역 시점에서 조립하도록 고쳤다. `localization/ui.csv`는 311 → 913줄.
- `scripts/systems/loc.gd`: `Node`가 아닌 곳(정적 헬퍼, 카탈로그의 `const` 표)에서 쓰는 번역 진입점. 키는 언제나 한국어 원문이라 번역이 없으면 원문이 그대로 남는다.
- 생성 공명: 이름과 설명이 원소·행동 두 낱말로 조립되므로 조립 재료를 항목에 함께 담고 `ResonanceSystem.display_name` / `display_description`이 표시 시점에 다시 조립한다. 캐시를 그대로 쓰면 카탈로그가 처음 읽힌 언어로 굳는다.
- 보물 효과문: 문장을 `{v}` 기준으로 잘라 스탯 행의 라벨과 꼬리를 만든다. 자르는 대상이 번역된 문장이어야 영어 행의 라벨도 영어가 된다. 단위 후보에 `s`를 더했다.
- `EditorialUI.place`: `clip_text`를 크기 지정 **앞**으로 옮겼다. 자르기가 꺼진 Label은 자기 글줄을 최소 폭으로 보고하고 Control은 `size`를 그 최소까지 끌어올리므로, 298px로 지정한 상자가 한국어 문장 폭인 313px로 조용히 벌어져 옆 버튼 아래로 파고들고 있었다.
- 분류 테이프(`_paint_chip`)는 건네받은 원문이 아니라 실제로 그릴 번역문을 재어 폭을 잡는다. `Weapon Upgrade`가 `eapon Upgra`로 잘리던 원인.
- 영어가 길어 줄이거나 넓힌 곳: 생존자 스탯 칸(`이속`→`Spd`, `공속`→`AS`), 기여 표시(`Contrib %d`), 공명 표시(`Res %d/%d`), 결과 화면의 기록/보상 줄 간격, LAN 안내문 줄바꿈, 카드 본문 최소 글자 크기 13 → 11.

검증: `layout_test`가 **두 언어 모두** 훑도록 바뀌었다. 재던 값도 `text` 속성이 아니라 `atr()`이 돌려주는 실제 표시 문자열이며, 버튼 글자와 형제 캡션끼리의 글자 겹침을 새로 검사한다. `card_wrap_test`도 두 언어로 372장을 그린다. `test_harness.require_loaded`는 기본 로케일을 `ko`로 고정한다 — 검사 문구가 한국어인 테스트가 기기에 저장된 언어 설정에 따라 실패하던 문제.

```
godot --headless --path . --script tests/layout_test.gd
godot --headless --path . --script tests/card_wrap_test.gd
godot --path . --script tests/localization_capture.gd -- --locale en
```

실제 렌더러 캡처: `.godot_runtime/loc-{ko,en}-{title,settings,lobby,character,hud,growth,details,resonance,pause,result}.png`.
