extends Control
const UI = preload("res://scripts/ui/ui_kit.gd")
signal preferences_changed
signal sound_preview_requested(cue: String)
signal closed
const SECTION_TITLES := {"display":"画面","audio":"声音","input":"操作","accessibility":"界面与辅助","game":"游戏"}
var preferences: RefCounted
var pending_action := ""
var binding_buttons: Dictionary={}
var status: Label
var scale_picker: OptionButton
var contrast_toggle: CheckButton
var motion_toggle: CheckButton
var preview: PanelContainer
var preview_gauge: Control
var tabs: TabContainer
var page_buttons: Dictionary={}
var option_controls: Dictionary={}
var value_labels: Dictionary={}
var display_confirmation: Control
var display_countdown: Label
var display_preview_active := false
var display_preview_seconds_left := 0.0
var current_section := "display"
var _confirm_display_button: Button
var _revert_display_button: Button
var _focus_modes: Dictionary={}
var _pending_slider_save := false
var _slider_save_delay := 0.0
var _return_button: Button
var background: TextureRect
var _decorative_previews: Dictionary={}

func setup(value: RefCounted) -> void:
	preferences=value
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	background=TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/art/title_bay.png"): background.texture=load("res://assets/art/title_bay.png")
	add_child(background)
	var shade:=ColorRect.new()
	shade.color=Color(.018,.055,.073,.38)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var shell:=PanelContainer.new()
	shell.add_theme_stylebox_override("panel",UI.style(Color(.063,.165,.204,.88),14,Color("52717b"),18))
	margin.add_child(shell)
	var column:=UI.column(shell,12)
	var header:=UI.row(column)
	UI.label(header,"设置",30)
	UI.spacer(header)
	_return_button=UI.button(header,"返回  Esc",close,Vector2(114,38))
	_note(column,"设置自动保存。窗口与分辨率调整需要确认，个人设置独立于游戏进度。")
	var workspace:=UI.row(column,16)
	workspace.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var navigation:=UI.column(workspace,8)
	navigation.custom_minimum_size.x=142
	tabs=TabContainer.new()
	tabs.tabs_visible=false
	tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	workspace.add_child(tabs)
	for section in SECTION_TITLES:
		var section_id: String=section
		var button:=UI.button(navigation,SECTION_TITLES[section],func(): select_section(section_id),Vector2(142,44),true)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_stylebox_override("pressed",UI.style(UI.TEAL,8,UI.TEAL,10))
		button.add_theme_color_override("font_pressed_color",UI.SURFACE)
		page_buttons[section]=button
		var scroll:=ScrollContainer.new()
		scroll.name=section
		scroll.follow_focus=true
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var body:=UI.column(scroll,14)
		body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		UI.label(body,SECTION_TITLES[section],24)
		var fields: Node=body
		if section in ["display","audio"]: fields=_decorated_fields(body,section)
		match section:
			"display": _build_display(fields)
			"audio": _build_audio(fields)
			"input": _build_input(body)
			"accessibility": _build_accessibility(body)
			"game": _build_game(body)
	var footer:=UI.row(column,10)
	status=UI.label(footer,"设置已就绪。",14,UI.TEAL)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	UI.button(footer,"恢复本页默认",_reset_current,Vector2(148,38))
	UI.action(UI.button(footer,"完成",close,Vector2(96,38)))
	_build_display_confirmation()
	_refresh_controls()
	select_section("display")
	resized.connect(_layout_settings)
	_layout_settings()
	hide()

func _decorated_fields(parent: Node, section: String) -> VBoxContainer:
	var layout:=UI.row(parent,22)
	var fields:=UI.column(layout,14)
	fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	fields.size_flags_stretch_ratio=1.4
	var card:=PanelContainer.new()
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	card.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	card.add_theme_stylebox_override("panel",UI.style(Color("143740"),10,Color("54777a"),12))
	layout.add_child(card)
	_decorative_previews[section]=card
	var column:=UI.column(card,12)
	UI.label(column,"海湾视野" if section=="display" else "声音空间",19,UI.TEXT)
	var image:=TextureRect.new()
	var path: String="res://assets/art/chapters/15.png" if section=="audio" else "res://assets/art/operator_cover.png"
	if ResourceLoader.exists(path): image.texture=load(path)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.custom_minimum_size=Vector2(0,170)
	column.add_child(image)
	var gauge: Control=UI.metric(column,"供电示例",22,24,"MW",UI.TEAL,true,"薄荷绿表示供电，珊瑚红表示缺口")
	gauge.compact=true
	gauge.remainder_color=UI.RED
	gauge.custom_minimum_size.y=64
	if section=="audio":
		_note(column,"海湾主题、海风与天气、清晰的操作回声。使用左侧音量分别调整。")
	else:
		_note(column,"精致微缩设施与清楚的信息层级。调整窗口后，在确认框中保留画面设置。")
	_note(column,"界面效果示例 · 非当前运营读数")
	return fields

func _layout_settings() -> void:
	for card in _decorative_previews.values(): card.visible=size.x>=1050

func _note(parent: Node, text: String) -> Label:
	var label:=UI.label(parent,text,14,UI.MUTED)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func _setting_row(parent: Node, text: String) -> HBoxContainer:
	var row:=UI.row(parent,12)
	var label:=UI.label(row,text,16)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return row

func _choice(parent: Node, caption: String, key: String, values: Array, labels: Array, display_preview: bool=false) -> OptionButton:
	var row:=_setting_row(parent,caption)
	var picker:=OptionButton.new()
	picker.custom_minimum_size=Vector2(180,38)
	for label in labels: picker.add_item(str(label))
	picker.set_meta("values",values)
	picker.item_selected.connect(func(index: int):
		if display_preview: _preview_display({key:values[index]})
		else: _set_option(key,values[index])
	)
	row.add_child(picker)
	option_controls[key]=picker
	return picker

func _toggle(parent: Node, caption: String, key: String) -> CheckButton:
	var button:=CheckButton.new()
	button.text=caption
	button.custom_minimum_size.y=38
	button.toggled.connect(func(enabled: bool): _set_option(key,enabled))
	parent.add_child(button)
	option_controls[key]=button
	return button

func _slider(parent: Node, caption: String, key: String, minimum: float=0.0, maximum: float=1.0) -> void:
	var group:=UI.column(parent,4)
	var row:=_setting_row(group,caption)
	var label:=UI.label(row,"",16,UI.TEAL)
	label.custom_minimum_size.x=56
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	value_labels[key]=label
	var slider:=HSlider.new()
	slider.min_value=minimum
	slider.max_value=maximum
	slider.step=.01
	slider.custom_minimum_size=Vector2(0,28)
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var track:=UI.style(Color("173f49"),5,Color("52717b"),0)
	track.content_margin_top=5
	track.content_margin_bottom=5
	slider.add_theme_stylebox_override("slider",track)
	slider.add_theme_stylebox_override("grabber_area",UI.style(UI.TEAL,5,UI.TEAL,0))
	slider.add_theme_stylebox_override("grabber_area_highlight",UI.style(UI.TEXT,5,UI.TEXT,0))
	var knob:=Image.create(20,20,false,Image.FORMAT_RGBA8)
	for y in range(20):
		for x in range(20):
			var alpha: float=clampf(9.5-Vector2(x-9.5,y-9.5).length(),0,1)
			knob.set_pixel(x,y,Color(UI.TEXT,alpha))
	var knob_texture:=ImageTexture.create_from_image(knob)
	slider.add_theme_icon_override("grabber",knob_texture)
	slider.add_theme_icon_override("grabber_highlight",knob_texture)
	slider.value_changed.connect(func(amount: float):
		preferences.set_options({key:amount},false)
		label.text="%d%%" % roundi(amount*100)
		_pending_slider_save=true
		_slider_save_delay=.3
		preferences_changed.emit()
	)
	slider.drag_ended.connect(func(_changed: bool): _flush_slider_changes())
	group.add_child(slider)
	option_controls[key]=slider

func _build_display(body: Node) -> void:
	_choice(body,"窗口模式","window_mode",["windowed","borderless"],["窗口","无边框全屏"],true)
	var resolutions: Array=preferences.available_resolutions()
	var captions: Array=[]
	for resolution in resolutions: captions.append("%d × %d" % [resolution.x,resolution.y])
	_choice(body,"窗口分辨率","window_resolution",resolutions,captions,true)
	_note(body,"全屏使用当前显示器分辨率；窗口尺寸可在窗口模式下调整。")
	_toggle(body,"垂直同步","vsync")
	_choice(body,"帧率上限","max_fps",[30,60,120,0],["30 FPS","60 FPS","120 FPS","不限"])
	_choice(body,"模型边缘抗锯齿","msaa_3d",[0,2,4],["关闭","2× MSAA","4× MSAA"])
	_note(body,"画面调整立即预览。15 秒内未确认会恢复之前的窗口设置。")

func _build_audio(body: Node) -> void:
	for entry in [["总音量","master_volume"],["音乐","music_volume"],["音效","sfx_volume"],["环境","ambience_volume"],["警报","alerts_volume"]]:
		_slider(body,entry[0],entry[1])
	_toggle(body,"切换到其他应用时静音","mute_unfocused")
	var actions:=UI.row(body,10)
	UI.button(actions,"试听音效",func(): sound_preview_requested.emit("confirm"),Vector2(144,38))
	UI.button(actions,"试听警报",func(): sound_preview_requested.emit("alert"),Vector2(144,38))
	_note(body,"警报只提示已知的运行事项；音量为零时完全静音。")

func _build_input(body: Node) -> void:
	_slider(body,"镜头平移速度","pan_sensitivity",.5,2.0)
	_slider(body,"镜头缩放速度","zoom_sensitivity",.5,2.0)
	_note(body,"点击按键后输入新键。重复按键会交换操作；Esc 保留用于取消和返回。")
	for action in preferences.DEFAULT_BINDINGS:
		var action_name: String=action
		var row:=_setting_row(body,str(preferences.ACTION_NAMES[action]))
		binding_buttons[action]=UI.button(row,preferences.binding_label(action),func(): _capture(action_name),Vector2(132,36))
	UI.button(body,"恢复默认快捷键",func(): _save_result(preferences.reset_bindings()); _refresh_bindings())

func _build_accessibility(body: Node) -> void:
	_choice(body,"信息深度","information_depth",["beginner","operator","engineer"],["入门 · 结果与下一步","运营 · 功率、证据与指标","工程 · 观测年龄与模型边界"])
	_note(body,"信息深度只改变解释与专业参数的展开，不改变仿真规则或难度。")
	scale_picker=_choice(body,"界面与字号比例","ui_scale",[1.0,1.25,1.5],["100%","125%","150%"])
	contrast_toggle=_toggle(body,"高对比界面","high_contrast")
	motion_toggle=_toggle(body,"减少天气、电流与菜单装饰动效","reduced_motion")
	preview=PanelContainer.new()
	body.add_child(preview)
	var example:=UI.column(preview,8)
	UI.label(example,"显示效果预览",18)
	preview_gauge=UI.metric(example,"已供 / 需求",11.9,22.9,"MW",UI.TEAL,true,"缺口 11.0 MW · 条纹表示未满足需求")
	preview_gauge.hatch_remainder=true
	var markers:=UI.row(example,8)
	UI.badge(markers,"✓ 已核实",UI.TEAL)
	UI.badge(markers,"? 待核实",UI.MUTED)
	UI.badge(markers,"! 需处理",UI.AMBER)
	_note(body,"状态同时使用文字、形状和颜色。减少装饰动效后仍保留必要的状态提示。")

func _build_game(body: Node) -> void:
	_toggle(body,"切换到其他应用时暂停游戏","pause_unfocused")
	_choice(body,"自动保存间隔","autosave_seconds",[90,180,300,0],["90 秒","3 分钟","5 分钟","关闭"])
	_note(body,"自动保存仅在已开始的游戏会话中计时。主菜单不会覆盖游戏进度；手动与自动存档分别保留。")
	var card:=UI.card(body,UI.TEAL,16)
	UI.label(card,"进度各自保存",18,UI.TEAL)
	_note(card,"历史战役与经营 / 自由沙盘使用各自的进度。个人显示、声音和按键设置在切换游戏进度后继续保留。")

func _build_display_confirmation() -> void:
	display_confirmation=Control.new()
	display_confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display_confirmation.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(display_confirmation)
	var shade:=ColorRect.new()
	shade.color=Color(.01,.035,.05,.91)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display_confirmation.add_child(shade)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display_confirmation.add_child(center)
	var panel:=PanelContainer.new()
	panel.custom_minimum_size.x=440
	panel.add_theme_stylebox_override("panel",UI.style(UI.SURFACE,12,UI.TEAL,24))
	center.add_child(panel)
	var body:=UI.column(panel,16)
	UI.label(body,"保留新的画面设置？",24)
	display_countdown=UI.label(body,"",16,UI.AMBER)
	var actions:=UI.row(body,12)
	_revert_display_button=UI.button(actions,"恢复之前设置  Esc",revert_display,Vector2(196,42))
	_confirm_display_button=UI.action(UI.button(actions,"保留设置",confirm_display,Vector2(148,42)))
	display_confirmation.hide()

func select_section(section: String) -> void:
	if not SECTION_TITLES.has(section) or display_preview_active: return
	pending_action=""
	current_section=section
	tabs.current_tab=SECTION_TITLES.keys().find(section)
	for key in page_buttons: page_buttons[key].button_pressed=key==section
	_refresh_bindings()

func open() -> void:
	pending_action=""
	_refresh_controls()
	show()
	_return_button.grab_focus()

func close() -> void:
	pending_action=""
	if display_preview_active: revert_display()
	_flush_slider_changes()
	hide()
	closed.emit()

func _capture(action: String) -> void:
	select_section("input")
	pending_action=action
	_refresh_bindings()
	status.text="按下新按键；Esc 取消此次修改。"

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if display_preview_active:
		if event.keycode==KEY_ESCAPE:
			revert_display()
			get_viewport().set_input_as_handled()
		return
	if not pending_action.is_empty():
		if event.keycode==KEY_ESCAPE:
			pending_action=""
			status.text="已取消按键修改。"
		else:
			var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
			_save_result(preferences.bind_action(pending_action,key))
			pending_action=""
		_refresh_bindings()
		get_viewport().set_input_as_handled()
	elif event.keycode==KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if display_preview_active:
		display_preview_seconds_left=maxf(0,display_preview_seconds_left-delta)
		display_countdown.text="%d 秒后自动恢复之前的窗口设置。" % ceili(display_preview_seconds_left)
		if display_preview_seconds_left<=0: revert_display()
	if _pending_slider_save:
		_slider_save_delay-=delta
		if _slider_save_delay<=0: _flush_slider_changes()

func _flush_slider_changes() -> void:
	if not _pending_slider_save: return
	_pending_slider_save=false
	_save_result(preferences.save_preferences())

func _preview_display(values: Dictionary) -> void:
	var result: Error=preferences.begin_display_preview(values)
	if result!=OK: _save_result(result); return
	display_preview_active=true
	display_preview_seconds_left=15.0
	display_countdown.text="15 秒后自动恢复之前的窗口设置。"
	_focus_modes.clear()
	for control in find_children("*","Control",true,false):
		if control==display_confirmation or display_confirmation.is_ancestor_of(control): continue
		if control.focus_mode!=Control.FOCUS_NONE:
			_focus_modes[control]=control.focus_mode
			control.focus_mode=Control.FOCUS_NONE
	display_confirmation.show()
	_revert_display_button.grab_focus()
	preferences_changed.emit()

func _finish_display_preview() -> void:
	display_preview_active=false
	display_preview_seconds_left=0
	display_confirmation.hide()
	for control in _focus_modes:
		if is_instance_valid(control): control.focus_mode=_focus_modes[control]
	_focus_modes.clear()
	_refresh_controls()
	_return_button.grab_focus()

func confirm_display() -> void:
	if not display_preview_active: return
	var result: Error=preferences.confirm_display_preview()
	_finish_display_preview()
	_save_result(result)

func revert_display() -> void:
	if not display_preview_active: return
	var result: Error=preferences.revert_display_preview()
	_finish_display_preview()
	_save_result(result)
	if result==OK: status.text="已恢复之前的窗口设置。"

func _reset_current() -> void:
	_flush_slider_changes()
	if current_section=="display":
		_save_result(preferences.set_options({"vsync":true,"max_fps":60,"msaa_3d":2}))
		var defaults: Dictionary={"window_mode":"windowed","window_resolution":Vector2i(1440,900)}
		_preview_display(defaults)
	else: _save_result(preferences.reset_section(current_section))
	_refresh_controls()

func _refresh_controls() -> void:
	for key in option_controls:
		var control: Control=option_controls[key]
		var value: Variant=preferences.get(key)
		if control is OptionButton:
			var values: Array=control.get_meta("values")
			control.select(maxi(0,values.find(value)))
		elif control is CheckButton: control.set_pressed_no_signal(bool(value))
		elif control is HSlider:
			control.set_value_no_signal(float(value))
			value_labels[key].text="%d%%" % roundi(float(value)*100)
	if option_controls.has("window_resolution"): option_controls.window_resolution.disabled=preferences.window_mode=="borderless"
	_refresh_bindings()
	_update_preview()

func _refresh_bindings() -> void:
	for action in binding_buttons:
		binding_buttons[action].text="请按新键…" if action==pending_action else preferences.binding_label(action)

func _set_option(key: String, value: Variant) -> void:
	_save_result(preferences.set_option(key,value))
	_refresh_controls()

func _save_result(result: Error) -> void:
	status.text="设置已保存。" if result==OK else "设置已应用，但无法写入个人配置文件。"
	status.add_theme_color_override("font_color",UI.TEAL if result==OK else UI.AMBER)
	preferences_changed.emit()

func _update_preview() -> void:
	if preview==null: return
	preview.theme=UI.create_theme(bool(preferences.high_contrast))
	preview.add_theme_stylebox_override("panel",UI.style(Color("07151d") if preferences.high_contrast else UI.RAISED,8,Color.WHITE if preferences.high_contrast else UI.MUTED.darkened(.5),12))
	preview_gauge.detail="静态方向与状态标记保留" if preferences.reduced_motion else "缺口 11.0 MW · 条纹表示未满足需求"
	preview_gauge.queue_redraw()
