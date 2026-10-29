extends RefCounted
const UI = preload("res://scripts/ui/ui_kit.gd")

static func build(host: Control, title: String, advance_text: String, on_advance: Callable, on_close: Callable) -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(.025,.065,.08,.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,28)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,22)
	host.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",UI.style(UI.SURFACE,10,Color("46616a"),18,true))
	margin.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var body := UI.column(scroll,12)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var relayout := func():
		body.custom_minimum_size.y=maxf(610,host.size.y-90)
	host.resized.connect(relayout)
	relayout.call_deferred()
	var header := UI.row(body,14)
	UI.label(header,title,24)
	UI.spacer(header)
	UI.label(header,"规划中 · 已暂停",14,UI.MUTED)
	UI.button(header,advance_text,on_advance)
	UI.button(header,"返回电网  Esc",on_close)
	return body
