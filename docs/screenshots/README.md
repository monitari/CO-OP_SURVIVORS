# 스크린샷

README에 쓰이는 화면들입니다. 손으로 찍지 않고 `tests/visual_capture.gd`가
헤드리스로 렌더링합니다 — 각 화면을 실제 게임 상태로 만든 뒤 뷰포트를 저장하므로,
UI가 바뀌면 다시 뽑기만 하면 되고 낡은 스크린샷이 남지 않습니다.

```powershell
godot --path . --script res://tests/visual_capture.gd
Copy-Item .godot_runtime/*.png docs/screenshots/
```

`.godot_runtime/`은 gitignore 대상이라, README가 참조하는 것만 이 폴더로 복사합니다.
