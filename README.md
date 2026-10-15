<div align="center">

# 🐾 달빛 옥상 간식 수호대

**사슬로 묶인 두 고양이가 밤의 옥상을 지키는 2인 협동 서바이버라이크**

<img src="docs/screenshots/gameplay.png" width="860" alt="사슬로 묶인 두 고양이가 옥상에서 첫 번째 보스와 적들을 마주한 플레이 화면">

<br>

![Godot](https://img.shields.io/badge/Godot-4.7.2-478cbf?logo=godotengine&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows-0078d4)
![Players](https://img.shields.io/badge/players-1~2-f59e0b)
![Status](https://img.shields.io/badge/status-alpha%20v0.2.0-8b5cf6)
![Contest](https://img.shields.io/badge/2026%20인디유-출품작-ec4899)

**[⬇ 체험 빌드 받기 (Windows)](https://github.com/monitari/CO-OP_SURVIVORS/releases/latest)**

</div>

---

## 어떤 게임인가요

두 사람이 고양이를 한 마리씩 골라, 25분 동안 옥상으로 몰려오는 적을 버티고 마지막 보스를 쓰러뜨리는 게임입니다. 두 고양이는 사슬로 묶여 있어서 멀리 떨어질 수 없습니다.

서바이버라이크 게임은 둘이 같이 해도 각자 알아서 살아남으면 되는 경우가 많아서, 같이 해야 하는 이유를 만들고 싶었습니다. 그래서 두 고양이를 사슬로 묶었고, 사슬이 팽팽할수록 공격력이 오르는 대신 사슬 내구도가 닳게 했습니다. 너무 오래 벌어져 있으면 오히려 약해지기 때문에, 언제 벌어지고 언제 모일지를 두 사람이 계속 맞춰야 합니다.

공격은 자동으로 나갑니다. 사슬에 묶인 채 조준까지 하기는 너무 정신이 없어서, 플레이어는 이동과 대시로 피하는 것과 레벨업 때 무엇을 고를지에 집중하도록 했습니다.

## 다운로드와 실행

1. [Releases](https://github.com/monitari/CO-OP_SURVIVORS/releases/latest)에서 `moonroof-snack-guardians-win64.exe`를 받습니다.
2. 설치 없이 바로 실행하면 됩니다. Windows의 "PC 보호" 창이 뜨면 **추가 정보 → 실행**을 눌러 주세요.
3. 기본 1280×720 창 모드로 열리고, `F11` 또는 `Alt+Enter`로 전체 화면을 켤 수 있습니다.

| 권장 사양 | |
|---|---|
| OS | Windows 10 / 11 (64비트) |
| 그래픽 | OpenGL 3.3 이상 지원 |
| 메모리 | 8GB 이상 |
| 입력 | 키보드, 2인 플레이 시 Xbox 호환 패드 권장 |

개발 PC(Ryzen 7 7800X3D, RTX 5060 Ti, 32GB)에서 동작을 확인했고, 저사양 환경 테스트는 아직 진행 중입니다.

## 플레이 방식

| 모드 | 설명 | 상태 |
|---|---|---|
| **AI 동료** | 혼자 플레이하고 동료 고양이는 AI가 조작합니다. 적과 보스 공격을 피하고, 쓰러진 플레이어를 살리러 오고, 성장 카드도 알아서 고릅니다. | 구현 |
| **로컬 2인** | 한 PC에서 키보드 + 키보드, 또는 키보드 + 게임패드로 둘이 플레이합니다. | 구현 |
| **LAN 2인** | 호스트와 참가자가 같은 네트워크에서 접속합니다. 기본 연결과 전투 동기화까지 만들었고 안정화 작업 중입니다. | 개발 중 |

## 조작

|  | P1 | P2 | 게임패드 |
|---|---|---|---|
| 이동 | `W` `A` `S` `D` | 방향키 | 왼쪽 스틱 |
| 대시 | `Space` | `.` | 오른쪽 트리거 |
| 카드 이동 | `A` / `D` | `←` / `→` | `LB` / `RB` |
| 확정 / 취소 | `W` / `S` | `↑` / `↓` | `A` / `B` |
| 다시 뽑기 | `Q` | `/` | `Y` |
| 상세 보기 | `Tab` | `Tab` | `X` |

`Esc` 일시정지, 결과 화면에서 `Enter`를 누르면 같은 조합으로 다시 도전합니다. 메뉴와 카드는 마우스로도 고를 수 있습니다.

## 사슬 규칙

사슬 길이는 고른 두 고양이에 따라 달라집니다. 가까이서 싸우는 고양이는 사슬을 짧게, 자리를 지키는 고양이는 길게 만들어서 조합마다 움직이는 방식이 꽤 다릅니다.

| 상태 | 장력 | 효과 |
|---|---|---|
| 안정 | 70% 미만 | 효과 없음, 내구도 회복 |
| 저항 | 70% 이상 | 내구도 회복 멈춤 |
| 과충전 | 82% 이상 | 공격력 +25%, 내구도 감소 |
| 한계 | 95% 이상 | 내구도 빠르게 감소 |

내구도가 다 떨어지면 과부하가 걸려 공격력이 20% 줄고, 두 사람이 다시 가까이 붙어야 풀립니다. 보스도 사슬을 노리고 공격하기 때문에 보스전에서는 위치 잡기가 더 중요해집니다.

## 한 판의 흐름

| 시간 | 0:00 | 2:30 | 5:00 | 10:00 | 15:00 | 20:00 | 25:00 |
|---|---|---|---|---|---|---|---|
| 흐름 | 시작 | 특수 웨이브 (78초마다) | 보스 1 | 보스 2 | 보스 3 | 보스 4 | 최종 보스 |
| | | | 폭주 청소 로봇 | 경비 드론 모함 | 옥상 관리자 | 구역 통제기 | 최종 관제 코어 |

- 적은 30초 간격으로 몰려오고, 세 번째 웨이브마다 규모가 큰 공세가 들어옵니다.
- 레벨이 오르면 두 사람이 각자 성장 카드에서 무기나 보물을 골라 캐릭터를 키웁니다. 무기는 레벨 3에서 테크를 고르고, 조건을 채우면 진화합니다.
- 한 명이 쓰러지면 제한 시간 안에 다른 한 명이 옆으로 가서 잠깐 버텨야 살릴 수 있습니다.
- 보스를 잡으면 두 사람 모두 체력이 절반 회복되고 사슬 내구도가 다시 찹니다. 앞의 두 보스는 공명핵을 떨어뜨립니다.
- **공명**은 두 사람이 진화시킨 무기를 공명핵으로 합쳐 하나의 기술로 만드는 시스템입니다. 그래서 레벨업 때 내 무기뿐 아니라 동료가 뭘 키우는지도 같이 보게 됩니다.

## 스크린샷

<table>
  <tr>
    <td><img src="docs/screenshots/character-select.png" alt="두 사람이 각자 고양이를 고르는 캐릭터 선택 화면"></td>
    <td><img src="docs/screenshots/level-up.png" alt="레벨업 때 부채꼴로 펼쳐지는 성장 카드 세 장"></td>
  </tr>
  <tr>
    <td align="center"><sub>캐릭터 선택</sub></td>
    <td align="center"><sub>레벨업 성장 카드</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/resonance-showcase.png" alt="두 진화 무기가 마주 보고 돌며 공명이 완성되는 연출"></td>
    <td><img src="docs/screenshots/victory-result.png" alt="최종 보스를 쓰러뜨린 뒤의 결과 화면"></td>
  </tr>
  <tr>
    <td align="center"><sub>공명 발동 연출</sub></td>
    <td align="center"><sub>결과 화면</sub></td>
  </tr>
</table>

## 개발 현황

v0.2.0 알파 빌드입니다. 타이틀부터 캐릭터 선택, 전투, 레벨업, 보스전, 결과 화면, 영구 성장까지 한 판은 처음부터 끝까지 이어집니다.

| 항목 | 내용 | 상태 |
|---|---|---|
| 로컬 2인 | 키보드와 게임패드로 한 PC에서 2인 플레이 | 구현 |
| AI 동료 | 이동, 회피, 부활, 성장 선택 | 구현 |
| LAN 2인 | 기본 연결과 전투 동기화, 안정화 작업 중 | 개발 중 |
| 캐릭터, 무기 | 일부 구현, 나머지 제작 중 | 개발 중 |
| 성장 | 무기별 테크와 진화, 보물, 공명 | 조정 중 |
| 적, 보스 | 일반 적 6종, 보스 5종, 특수 웨이브, 필드 아이템 | 구현 |
| 언어 | 한국어, 영어 UI | 번역 확인 중 |

아직 다른 사람을 대상으로 한 플레이 테스트는 해 보지 못했습니다. 사슬 규칙을 금방 이해하는지, 25분이 길지 않은지, 과충전을 일부러 노리게 되는지가 가장 궁금한 부분입니다.

### 앞으로의 계획

| 시기 | 내용 |
|---|---|
| 2026년 10~11월 | 남은 고양이와 무기 구현, 2인 플레이 테스트, 초반 난이도와 튜토리얼 수정 |
| 2026년 12월 | LAN 2인 마무리(연결 안정성, 지연 처리), 버그 수정과 성능 점검 |
| 2027년 1~2월 | 체험판 빌드 정리, Steam 페이지와 소개 영상 준비, 영어 번역 확인 |
| 이후 | 체험판 반응을 보고 콘텐츠 추가, 얼리 액세스 여부 결정 |

## 직접 실행하기 (개발용)

외부 애드온 없이 [Godot 4.7.2 Standard](https://godotengine.org/download/windows/)만 있으면 됩니다.

1. Godot에서 이 폴더의 `project.godot`을 엽니다.
2. `F5`로 실행합니다.

Windows 빌드는 내보내기 템플릿을 설치한 뒤 아래 명령으로 `builds/`에 만듭니다.

```powershell
godot --headless --path . --export-release "Windows Desktop"
```

헤드리스 테스트는 `tests/` 폴더에 있습니다. 예를 들어 협동 규칙 테스트는 이렇게 돌립니다.

```powershell
godot --headless --path . --script res://tests/coop_rework_test.gd
```

## 저장소 구조

```
scripts/     게임 코드 (GDScript)
  catalogs/  고양이, 무기, 보물 데이터
  entities/  플레이어, 적, 투사체
  systems/   웨이브, 무기, 경험치, 공명, 네트워크
  ui/        화면 구성과 테마
assets/      게임에 실제로 들어가는 이미지, 폰트, 음원
art/         이미지 생성 원본과 프롬프트 기록 (빌드에 포함되지 않음)
tests/       헤드리스 테스트와 스크린샷 캡처
tools/       아틀라스 자르기, 음악 생성 등 보조 스크립트
docs/        설계 기록, UI 가이드, 스크린샷
```

시스템별로 왜 이렇게 만들었는지, 밸런스와 성능을 어떻게 맞췄는지는 [개발 노트](docs/dev-notes.md)와 [docs/](docs/) 폴더의 기록에 정리해 두었습니다.

## AI 활용과 라이선스

이 게임은 AI 도구의 도움을 많이 받아 만들었습니다. 숨기지 않고 적어 둡니다.

- **그림**: 고양이, 적, 무기, 보물 아이콘, 옥상 소품, 타이틀과 UI 배경 이미지는 OpenAI Codex의 이미지 생성 기능(imagegen)으로 만들었습니다. 사용한 프롬프트는 [art/prompts/](art/prompts/)에 남겨 두었고, 생성한 원본을 잘라 정리하는 작업은 [tools/](tools/)의 스크립트로 했습니다.
- **코드**: OpenAI Codex, Claude Code 같은 AI 코딩 도구와 함께 작성했습니다. 기획, 규칙과 밸런스 결정, 플레이 확인과 테스트 검토는 직접 했습니다.
- **소리**: 효과음과 음악은 외부 샘플 없이 코드로 합성했습니다(`tools/generate_music.py`).
- **폰트**: Griun 한글 고운체, [Jua](https://fonts.google.com/specimen/Jua)(SIL OFL, `assets/fonts/Jua-OFL.txt`), Memoment 꾹꾹을 사용하며 각 폰트의 배포 조건을 따릅니다.

AI 생성물은 저작권 관계가 아직 분명하지 않은 부분이 있어서, 이 저장소에는 따로 오픈소스 라이선스를 붙이지 않았습니다. 공모전 심사와 포트폴리오 열람을 위해 공개한 저장소이니, 코드나 리소스를 가져다 쓰시려면 먼저 이슈로 연락 부탁드립니다.

## English

**Moonroof Snack Guardians** is a 2-player co-op survivor-like made in Godot 4.7.2. Two cats are chained together and have to hold a moonlit rooftop for 25 minutes against waves of enemies and five bosses. A taut chain boosts damage but wears down its durability, so both players have to keep deciding when to spread out and when to regroup. You can play local co-op on one PC or solo with an AI partner; LAN play is still in development. The UI supports Korean and English. This is an alpha build (v0.2.0) submitted to the 2026 Indie-U contest. Art was generated with AI image tools and the code was written with the help of AI coding assistants (see above).

---

<div align="center">
<sub>만든 사람: <b>YULMU</b> (김준후, 1인 개발) · 2026년 7월부터 개발 중</sub>
</div>
