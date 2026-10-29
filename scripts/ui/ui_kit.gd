extends RefCounted
## Shared visual language for the map and all planning windows.
const Gauge = preload("res://scripts/ui/visual_gauge.gd")
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

static func create_theme(high_contrast: bool=false) -> Theme:
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
	for state in ["scroll","scroll_focus"]:
		theme.set_stylebox(state,"VScrollBar",style(Color("0a202a"),4,Color("0a202a"),2))
		theme.set_stylebox(state,"HScrollBar",style(Color("0a202a"),4,Color("0a202a"),2))
	for state in ["grabber","grabber_highlight","grabber_pressed"]:
		for type in ["VScrollBar","HScrollBar"]: theme.set_stylebox(state,type,style(Color("45646c") if state=="grabber" else TEAL,4,Color.TRANSPARENT,4))
	for type in ["HSlider","VSlider"]:
		theme.set_stylebox("slider",type,style(Color("0b222c"),4,Color("36515b"),3))
		theme.set_stylebox("grabber_area",type,style(TEAL,4,TEAL,3))
		theme.set_stylebox("grabber_area_highlight",type,style(TEAL.lightened(.15),4,TEAL,3))
	theme.set_stylebox("background","ProgressBar",style(Color("0b222c"),5,Color("36515b"),3))
	theme.set_stylebox("fill","ProgressBar",style(TEAL,5,TEAL,3))
	var separator := StyleBoxLine.new()
	separator.color = Color("40616b")
	separator.thickness = 1
	theme.set_stylebox("separator","HSeparator",separator)
	theme.set_stylebox("panel","PopupMenu",style())
	theme.set_stylebox("panel","TabContainer",style(SURFACE,6,Color("36515b"),12))
	theme.set_stylebox("tab_selected","TabContainer",style(Color("28514e"),5,TEAL,10))
	theme.set_stylebox("tab_unselected","TabContainer",style(Color("142f39"),5,Color("29444e"),10))
	theme.set_color("font_selected_color","TabContainer",TEAL)
	theme.set_color("font_unselected_color","TabContainer",MUTED)
	theme.set_font_size("font_size","TabContainer",14)
	for state in ["tab_selected","tab_unselected","tab_hovered"]:
		theme.set_stylebox(state,"TabBar",style(Color("28514e") if state=="tab_selected" else SURFACE,4,TEAL if state=="tab_selected" else Color("36515b"),6))
	theme.set_color("font_selected_color","TabBar",TEAL)
	theme.set_color("font_unselected_color","TabBar",MUTED)
	theme.set_font_size("font_size","TabBar",14)
	theme.set_stylebox("panel","TooltipPanel",style(Color("102833"),6,Color("527078"),10))
	theme.set_color("font_color","TooltipLabel",TEXT)
	theme.set_font_size("font_size","TooltipLabel",14)
	if high_contrast:
		for type in ["Label","Button","OptionButton","CheckButton","CheckBox","LineEdit","TabContainer","PopupMenu","TooltipLabel"]:
			theme.set_color("font_color",type,Color.WHITE)
		for type in ["Button","OptionButton"]:
			for state in ["normal","hover","pressed","disabled","focus"]:
				var background := Color("07151d") if state in ["normal","disabled"] else Color("234d52")
				theme.set_stylebox(state,type,style(background,6,Color("c4e8ec"),8))
			theme.set_color("font_disabled_color",type,Color("b3c1c7"))
		theme.set_stylebox("panel","PanelContainer",style(Color("07151d"),8,Color("9dc4ce")))
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

static func action(button_: Button, intent: String="primary") -> Button:
	var accent: Color=RED if intent=="destructive" else TEAL
	var background:=Color("452e32") if intent=="destructive" else TEAL
	button_.add_theme_stylebox_override("normal",style(background,6,accent,8))
	button_.add_theme_stylebox_override("hover",style(background.lightened(.13),6,accent,8))
	button_.add_theme_stylebox_override("pressed",style(background.darkened(.12),6,accent,8))
	button_.add_theme_color_override("font_color",TEXT if intent=="destructive" else Color("092c35"))
	button_.add_theme_color_override("font_hover_color",TEXT if intent=="destructive" else Color("092c35"))
	button_.add_theme_color_override("font_pressed_color",TEXT if intent=="destructive" else Color("092c35"))
	button_.add_theme_color_override("font_focus_color",TEXT if intent=="destructive" else Color("092c35"))
	return button_

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

static func metric(parent: Node, caption: String, value: float, maximum: float, unit: String="", accent: Color=TEAL, known: bool=true, detail: String="") -> Control:
	var gauge := Gauge.new()
	gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(gauge)
	gauge.configure(caption,value,maximum,unit,accent,known,detail)
	return gauge

static func badge(parent: Node, text: String, accent: Color=TEAL) -> Label:
	var result := label(parent,text,14,accent)
	result.add_theme_stylebox_override("normal",style(Color(accent,.09),5,Color(accent,.5),6))
	return result

static func card(parent: Node, accent: Color=Color("36515b"), padding: int=12) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",style(SURFACE,8,accent,padding))
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var body := column(panel,8)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return body
