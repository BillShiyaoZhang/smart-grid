extends Control
const UI = preload("res://scripts/ui/ui_kit.gd")
signal preferences_changed
signal closed
var preferences: RefCounted
var pending_action := ""
var binding_buttons: Dictionary = {}
var status: Label
var scale_picker: OptionButton
var contrast_toggle: CheckButton
var motion_toggle: CheckButton
var preview: PanelContainer
var preview_gauge: Control

func setup(value: RefCounted) -> void:
	preferences = value
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.05,0.07,0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,28)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var column := UI.column(panel,12)
	var header := UI.row(column)
	UI.label(header,"操作与显示设置",24)
	UI.spacer(header)
	UI.button(header,"返回  Esc",close)
	UI.label(column,"设置立即生效，单独保存；不改变当前战役或沙盘进度。",14,UI.MUTED)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := UI.column(scroll,10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scale_row := UI.row(body)
	UI.label(scale_row,"界面与字号比例",18)
	UI.spacer(scale_row)
	scale_picker = OptionButton.new()
	for scale_value in [100,125,150]: scale_picker.add_item("%d%%" % scale_value)
	scale_picker.select([1.0,1.25,1.5].find(preferences.ui_scale))
	scale_picker.item_selected.connect(func(index: int): _set_option("ui_scale",[1.0,1.25,1.5][index]))
	scale_row.add_child(scale_picker)
	var contrast := CheckButton.new()
	contrast_toggle = contrast
	contrast.text = "高对比界面"
	contrast.button_pressed = preferences.high_contrast
	contrast.toggled.connect(func(enabled: bool): _set_option("high_contrast",enabled))
	body.add_child(contrast)
	var motion := CheckButton.new()
	motion_toggle = motion
	motion.text = "减少天气与电流装饰动效"
	motion.button_pressed = preferences.reduced_motion
	motion.toggled.connect(func(enabled: bool): _set_option("reduced_motion",enabled))
	body.add_child(motion)
	preview=PanelContainer.new()
	body.add_child(preview)
	var example:=UI.column(preview,6)
	UI.label(example,"显示效果预览",18)
	preview_gauge=UI.metric(example,"已供 / 需求",11.9,22.9,"MW",UI.TEAL,true,"缺口 11.0 MW · 条纹表示未满足需求")
	preview_gauge.hatch_remainder=true
	var markers:=UI.row(example,8)
	UI.badge(markers,"✓ 已核实",UI.TEAL)
	UI.badge(markers,"? 待核实",UI.MUTED)
	UI.badge(markers,"! 需处理",UI.AMBER)
	_update_preview()
	UI.label(body,"快捷键",20)
	UI.label(body,"点击按键后输入新键。重复按键会交换两个操作；Esc 保留用于取消和返回。",14,UI.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for action in preferences.DEFAULT_BINDINGS:
		var action_name: String = action
		var row := UI.row(body)
		UI.label(row,str(preferences.ACTION_NAMES[action]))
		UI.spacer(row)
		binding_buttons[action] = UI.button(row,preferences.binding_label(action),func(): _capture(action_name),Vector2(160,36))
	UI.button(body,"恢复默认快捷键",func(): _save_result(preferences.reset_bindings()); _refresh_bindings())
	status = UI.label(column,"",14,UI.TEAL)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hide()

func open() -> void:
	pending_action = ""
	scale_picker.select([1.0,1.25,1.5].find(preferences.ui_scale))
	contrast_toggle.set_pressed_no_signal(preferences.high_contrast)
	motion_toggle.set_pressed_no_signal(preferences.reduced_motion)
	_refresh_bindings()
	show()

func close() -> void:
	pending_action = ""
	hide()
	closed.emit()

func _capture(action: String) -> void:
	pending_action = action
	_refresh_bindings()
	status.text = "按下新按键；Esc 取消此次修改。"

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if not pending_action.is_empty():
		if event.keycode == KEY_ESCAPE:
			pending_action = ""
			status.text = "已取消按键修改。"
		else:
			var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			_save_result(preferences.bind_action(pending_action,key))
			pending_action = ""
		_refresh_bindings()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _refresh_bindings() -> void:
	for action in binding_buttons:
		binding_buttons[action].text = "请按新键…" if action == pending_action else preferences.binding_label(action)

func _set_option(key: String, value: Variant) -> void:
	_save_result(preferences.set_option(key,value))
	_update_preview()

func _save_result(result: Error) -> void:
	status.text = "设置已保存。" if result == OK else "设置已应用，但无法写入个人配置文件。"
	status.add_theme_color_override("font_color",UI.TEAL if result == OK else UI.AMBER)
	preferences_changed.emit()

func _update_preview() -> void:
	if preview==null: return
	preview.theme=UI.create_theme(bool(preferences.high_contrast))
	preview.add_theme_stylebox_override("panel",UI.style(Color("07151d") if preferences.high_contrast else UI.RAISED,8,Color.WHITE if preferences.high_contrast else UI.MUTED.darkened(.5),12))
	preview_gauge.detail="静态方向与状态标记保留" if preferences.reduced_motion else "缺口 11.0 MW · 条纹表示未满足需求"
	preview_gauge.queue_redraw()
