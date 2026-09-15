extends RefCounted
## Declarative default controls. Keeping the data here makes adding an action a
## one-line change and lets menus/tests install the exact same bindings.

const KEYBOARD := {
	"build_details": [KEY_TAB],
	"menu_previous": [KEY_UP, KEY_W],
	"menu_next": [KEY_DOWN, KEY_S],
	"menu_left": [KEY_LEFT, KEY_A],
	"menu_right": [KEY_RIGHT, KEY_D],
	"menu_confirm": [KEY_ENTER],
	"menu_cancel": [KEY_BACKSPACE],
	"p1_left": [KEY_A],
	"p1_right": [KEY_D],
	"p1_up": [KEY_W],
	"p1_down": [KEY_S],
	"p2_left": [KEY_LEFT],
	"p2_right": [KEY_RIGHT],
	"p2_up": [KEY_UP],
	"p2_down": [KEY_DOWN],
	"restart": [KEY_ENTER],
	"pause": [KEY_ESCAPE],
	"toggle_shake": [KEY_F1],
	"toggle_numbers": [KEY_F2],
	"toggle_sound": [KEY_F3],
	"toggle_music": [KEY_F4],
	"toggle_fullscreen": [KEY_F11],
	"toggle_moonlight": [KEY_F12],
	"p1_choice_1": [KEY_A],
	"p1_choice_2": [KEY_S],
	"p1_choice_3": [KEY_D],
	"p2_choice_1": [KEY_LEFT],
	"p2_choice_2": [KEY_DOWN],
	"p2_choice_3": [KEY_RIGHT],
	"p1_select_previous": [KEY_A],
	"p1_select_next": [KEY_D],
	"p1_select_confirm": [KEY_W],
	"p1_select_cancel": [KEY_S],
	"p2_select_previous": [KEY_LEFT],
	"p2_select_next": [KEY_RIGHT],
	"p2_select_confirm": [KEY_UP],
	"p2_select_cancel": [KEY_DOWN],
	"p1_reroll": [KEY_Q],
	"p2_reroll": [KEY_SLASH],
	"p1_dash": [KEY_SPACE],
	"p2_dash": [KEY_PERIOD],
	"meta_buy": [KEY_SPACE],
}

const SHARED_JOYPAD_BUTTONS := {
	"build_details": JOY_BUTTON_X,
	"menu_previous": JOY_BUTTON_DPAD_UP,
	"menu_next": JOY_BUTTON_DPAD_DOWN,
	"menu_left": JOY_BUTTON_DPAD_LEFT,
	"menu_right": JOY_BUTTON_DPAD_RIGHT,
	"menu_confirm": JOY_BUTTON_A,
	"menu_cancel": JOY_BUTTON_B,
	"pause": JOY_BUTTON_START,
	"restart": JOY_BUTTON_A,
	"meta_buy": JOY_BUTTON_Y,
}

const PLAYER_JOYPAD_BUTTONS := [
	{
		"p1_choice_1": JOY_BUTTON_X,
		"p1_choice_2": JOY_BUTTON_A,
		"p1_choice_3": JOY_BUTTON_B,
		"p1_select_previous": JOY_BUTTON_LEFT_SHOULDER,
		"p1_select_next": JOY_BUTTON_RIGHT_SHOULDER,
		"p1_select_confirm": JOY_BUTTON_A,
		"p1_select_cancel": JOY_BUTTON_B,
		"p1_reroll": JOY_BUTTON_Y,
	},
	{
		"p2_choice_1": JOY_BUTTON_X,
		"p2_choice_2": JOY_BUTTON_A,
		"p2_choice_3": JOY_BUTTON_B,
		"p2_select_previous": JOY_BUTTON_LEFT_SHOULDER,
		"p2_select_next": JOY_BUTTON_RIGHT_SHOULDER,
		"p2_select_confirm": JOY_BUTTON_A,
		"p2_select_cancel": JOY_BUTTON_B,
		"p2_reroll": JOY_BUTTON_Y,
	},
]

const PLAYER_JOYPAD_AXES := [
	{
		"p1_left": [JOY_AXIS_LEFT_X, -1.0],
		"p1_right": [JOY_AXIS_LEFT_X, 1.0],
		"p1_up": [JOY_AXIS_LEFT_Y, -1.0],
		"p1_down": [JOY_AXIS_LEFT_Y, 1.0],
		"p1_dash": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	},
	{
		"p2_left": [JOY_AXIS_LEFT_X, -1.0],
		"p2_right": [JOY_AXIS_LEFT_X, 1.0],
		"p2_up": [JOY_AXIS_LEFT_Y, -1.0],
		"p2_down": [JOY_AXIS_LEFT_Y, 1.0],
		"p2_dash": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	},
]


static func install() -> void:
	for action in KEYBOARD:
		_ensure_action(action)
		for keycode in KEYBOARD[action]:
			_add_key(action, keycode)
	for device in PLAYER_JOYPAD_BUTTONS.size():
		for action in SHARED_JOYPAD_BUTTONS:
			_add_button(action, device, SHARED_JOYPAD_BUTTONS[action])
		for action in PLAYER_JOYPAD_BUTTONS[device]:
			_add_button(action, device, PLAYER_JOYPAD_BUTTONS[device][action])
		for action in PLAYER_JOYPAD_AXES[device]:
			var binding: Array = PLAYER_JOYPAD_AXES[device][action]
			_add_axis(action, device, binding[0], binding[1])


static func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


static func _add_key(action: StringName, physical_keycode: int) -> void:
	_ensure_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode as Key
	_add_event(action, event)


static func _add_button(action: StringName, device: int, button: int) -> void:
	_ensure_action(action)
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button as JoyButton
	_add_event(action, event)


static func _add_axis(action: StringName, device: int, axis: int, value: float) -> void:
	_ensure_action(action)
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis as JoyAxis
	event.axis_value = value
	_add_event(action, event)


static func _add_event(action: StringName, event: InputEvent) -> void:
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)
