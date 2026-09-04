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
