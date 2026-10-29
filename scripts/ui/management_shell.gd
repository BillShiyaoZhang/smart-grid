extends RefCounted
const UI = preload("res://scripts/ui/ui_kit.gd")

static func build(host: Control, title: String, advance_text: String, on_advance: Callable, on_close: Callable) -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(.025,.065,.08,.76)
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
	var header := HFlowContainer.new()
	header.add_theme_constant_override("h_separation",10)
	header.add_theme_constant_override("v_separation",6)
	body.add_child(header)
	var title_label: Label=UI.label(header,title,28)
	var compact_title:=func(): title_label.text=title.get_slice(" · ",0) if host.size.x<1100 else title
	host.resized.connect(compact_title)
	compact_title.call_deferred()
	UI.spacer(header)
	UI.badge(header,"规划中 · 已暂停",UI.AMBER)
	var controller: Node=host.get("game")
	if advance_text.begins_with("推进") and controller!=null:
		UI.button(header,"推进 15 分钟",func():
			if controller.has_method("advance_management"): controller.advance_management(.25)
			else: on_advance.call()
		)
		UI.button(header,"推进 1 小时",func():
			if controller.has_method("advance_management"): controller.advance_management(1.0)
			else: on_advance.call()
		)
		UI.button(header,"等待下一事件",func():
			if controller.has_method("wait_for_next_event"): controller.wait_for_next_event()
			else: on_advance.call()
		)
	else: UI.button(header,advance_text,on_advance)
	UI.button(header,"返回电网  Esc",on_close)
	return body
