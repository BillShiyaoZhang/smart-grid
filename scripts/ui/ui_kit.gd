extends RefCounted
## Shared visual language for the map and all planning windows.
const SURFACE := Color("112b35")
const RAISED := Color("1b3943")
const TEAL := Color("77dbc0")
const TEXT := Color("f2eddb")
const MUTED := Color("a4bbc0")
const AMBER := Color("efbb7d")
const RED := Color("f38a79")

static func style(color: Color=SURFACE, radius: int=8, border: Color=Color("36515b"), padding: int=12, shadow: bool=false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(1)
	box.set_content_margin_all(padding)
	if shadow:
		box.shadow_color = Color(.01,.03,.04,.18)
		box.shadow_size = 4
		box.shadow_offset = Vector2(0,2)
	return box

static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	theme.default_font_size = 14
	for type in ["Label","Button","OptionButton","CheckButton","CheckBox","LineEdit","TabContainer","PopupMenu"]:
		theme.set_color("font_color",type,TEXT)
		theme.set_font_size("font_size",type,14)
	for type in ["Button","OptionButton"]:
		for state in ["normal","hover","pressed","disabled","focus"]:
			var color := RAISED
			var border := Color("36515b")
			if state == "hover": color = Color("2c505a"); border = TEAL.darkened(.3)
			if state == "pressed": color = Color("28584f"); border = TEAL
			if state == "disabled": color = Color("172f38"); border = Color("28414a")
			if state == "focus": color = Color.TRANSPARENT; border = TEAL
			theme.set_stylebox(state,type,style(color,6,border,8))
		theme.set_color("font_disabled_color",type,Color("7e959d"))
		theme.set_color("font_hover_color",type,TEXT)
		theme.set_color("font_pressed_color",type,TEAL)
	for type in ["LineEdit","TextEdit"]:
		theme.set_stylebox("normal",type,style(Color("0e252f"),5,Color("36515b"),8))
		theme.set_stylebox("focus",type,style(Color("0e252f"),5,TEAL,8))
		theme.set_color("font_color",type,TEXT)
	theme.set_stylebox("panel","PanelContainer",style())
	theme.set_stylebox("panel","PopupMenu",style())
	theme.set_stylebox("panel","TabContainer",style(SURFACE,6,Color("36515b"),12))
	theme.set_stylebox("tab_selected","TabContainer",style(Color("28514e"),5,TEAL,10))
	theme.set_stylebox("tab_unselected","TabContainer",style(Color("142f39"),5,Color("29444e"),10))
	theme.set_color("font_selected_color","TabContainer",TEAL)
	theme.set_color("font_unselected_color","TabContainer",MUTED)
	theme.set_font_size("font_size","TabContainer",14)
	theme.set_stylebox("panel","TooltipPanel",style(Color("102833"),6,Color("527078"),10))
	theme.set_color("font_color","TooltipLabel",TEXT)
	theme.set_font_size("font_size","TooltipLabel",14)
	return theme

static func label(parent: Node, text: String, font_size: int=14, color: Color=TEXT) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size",maxi(14,font_size))
	result.add_theme_color_override("font_color",color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func button(parent: Node, text: String, callback: Callable, minimum: Vector2=Vector2(0,36), toggle: bool=false) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(minimum.x,maxf(34,minimum.y))
	result.toggle_mode = toggle
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.focus_mode = Control.FOCUS_ALL
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

static func column(parent: Node, gap: int=10) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation",gap)
	parent.add_child(result)
	return result

static func row(parent: Node, gap: int=10) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation",gap)
	parent.add_child(result)
	return result

static func spacer(parent: Node) -> Control:
	var result := Control.new()
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result
