# UI 아이콘 아틀라스

세 파일은 모두 1254×1254 PNG이며 투명 배경을 사용합니다. 런타임에서는
`scripts/ui/icon_catalog.gd`가 원본 크기를 열/행 수로 나눠 `AtlasTexture`로
제공하므로, 원본을 리사이즈하지 않는 한 별도의 잘라낸 파일은 필요하지 않습니다.

- `survivor_atlas.png` (3×2): `lyra`, `volta`, `ignis`, `neve`, `moro`, `serin`
- `weapon_atlas.png` (3×2): `homing`, `lightning`, `flame`, `frost`, `scythe`, `chain`
- `upgrade_atlas.png` (4×3): `might`, `area`, `amount`, `haste`, `projectile_speed`,
  `armor`, `recovery`, `magnet`, `growth`, `luck`, `move`, `vitality`

순서는 왼쪽에서 오른쪽, 위에서 아래입니다. 새 캐릭터나 능력치를 추가할 때는
아틀라스의 마지막 셀과 `GameIconCatalog`의 순서 배열을 함께 갱신하세요.

## 아직 아트가 없는 항목

아틀라스는 손으로 그린 고정 크기 파일이라 이후 추가된 항목(새 생존자
`kael`/`rian`/`tera`/`nova`, 그 무기들, 합성 무기 10종, 보물 6종)은 셀이
없습니다. 이 항목들은 `GameIconCatalog.generated()`가 id에서 결정론적으로
만들어 내는 임시 글리프로 그려집니다 — 색상환 위치와 도형이 id 해시에서
나오므로 같은 id는 항상 같은 아이콘이 되고, 아이콘 없는 빈 카드가 뜨는 일은
없습니다.

진짜 아트를 그려 넣을 때는 아틀라스 격자를 넓히고 `GameIconCatalog`의 순서
배열에 id를 추가하면 됩니다. 그 순간부터 해당 id는 임시 글리프 대신 아틀라스
셀을 씁니다. `tests/icon_coverage_test.gd`가 어떤 id가 아직 임시인지 출력합니다.
