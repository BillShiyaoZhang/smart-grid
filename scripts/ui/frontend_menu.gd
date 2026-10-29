extends Control
## Native, keyboard-accessible menus over original title key art / the paused world.
const UI = preload("res://scripts/ui/ui_kit.gd")
signal action_requested(action: String)
var mode := "title"
var buttons: Dictionary = {}
var title_label: Label
var summary: Label
var warning: Label
var background: TextureRect
var shade: TextureRect
var scroll: ScrollContainer
var body: VBoxContainer
var feature: PanelContainer
var version: Label

func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	background = TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/art/title_bay.png"): background.texture = load("res://assets/art/title_bay.png")
	add_child(background)
	shade = TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,0.38,0.72,1.0])
	gradient.colors = PackedColorArray([Color("061c27fa"),Color("08232bf0"),Color("08232b15"),Color("08232b08")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	shade.texture = texture
	add_child(shade)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	body = UI.column(scroll,10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label = UI.label(body,"潮汐电网",56)
	UI.label(body,"T I D A L   G R I D",15,UI.AMBER)
	var rule := HSeparator.new()
	body.add_child(rule)
	buttons.resume = UI.action(UI.button(body,"继续游戏  →",func(): action_requested.emit("continue"),Vector2(0,48)))
	buttons.resume.add_theme_font_size_override("font_size",21)
	summary = UI.label(body,"",14,UI.MUTED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning = UI.label(body,"",14,UI.AMBER)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for spec in [["campaign","开启教学战役"],["management","开始运营 · 经营路线"],["sandbox","自由沙盘"],["save","保存游戏"],["load","读取游戏"],["settings","设置"],["title","返回主菜单"],["credits","制作名单"],["quit","退出游戏"]]:
		var key: String = spec[0]
		var button := UI.button(body,spec[1],func(): action_requested.emit(key),Vector2(0,36))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = _icon(key)
		button.add_theme_constant_override("h_separation",12)
		button.add_theme_font_size_override("font_size",17)
		button.add_theme_stylebox_override("normal",UI.style(Color("102b3520"),5,Color("48647055"),9))
		button.add_theme_stylebox_override("hover",UI.style(Color("24464ee8"),5,UI.TEAL.darkened(.35),9))
		button.add_theme_constant_override("outline_size",0)
		buttons[key] = button
	feature = PanelContainer.new()
	feature.add_theme_stylebox_override("panel",UI.style(Color("d6c6a8"),7,UI.AMBER,14))
	body.add_child(feature)
	var note := UI.column(feature,3)
	UI.label(note,"电流的足迹",23,UI.SURFACE)
	UI.label(note,"15 个历史现场 · 从第一盏灯到智能电网",14,Color("30494d")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	version = UI.label(body,"原创海湾电网经营游戏 · Godot",14,UI.MUTED)
	resized.connect(_layout)
	_layout.call_deferred()

func open_title(catalog: Dictionary) -> void:
	mode = "title"
	title_label.text = "潮汐电网"
	background.show()
	shade.modulate = Color.WHITE
	for key in buttons: buttons[key].visible = key not in ["save","load","title"]
	var latest: Dictionary = catalog.get("latest",{})
	buttons.resume.visible = not latest.is_empty()
	buttons.resume.disabled = latest.is_empty()
	buttons.campaign.text = "开启教学战役"
	summary.text = "%s\n%s\n保存于 %s" % [latest.title,latest.detail,latest.saved_at] if not latest.is_empty() else "建设、调度与守护每一盏灯。"
	warning.text = "发现无法读取的存档，已保留原文件；可继续最近的有效进度。" if not catalog.get("invalid",[]).is_empty() else ""
	warning.visible = not warning.text.is_empty()
	UI.action(buttons.campaign) if latest.is_empty() else _secondary(buttons.campaign)
	feature.show()
	show()
	_layout()
	(buttons.resume if not latest.is_empty() else buttons.campaign).grab_focus()

func open_pause() -> void:
	mode = "paused"
	title_label.text = "暂歇片刻"
	background.hide()
	shade.modulate = Color(1,1,1,.95)
	for key in buttons: buttons[key].visible = key in ["resume","save","load","campaign","settings","title","quit"]
	buttons.resume.disabled = false
	buttons.resume.text = "继续游戏  →"
	buttons.campaign.text = "战役章节目录"
	_secondary(buttons.campaign)
	summary.text = "电网已暂停，返回后继续原有运行状态。"
	warning.hide()
	feature.hide()
	show()
	_layout()
	buttons.resume.grab_focus()

func _secondary(button: Button) -> void:
	for state in ["normal","hover","pressed"]:
		button.remove_theme_stylebox_override(state)
	button.add_theme_stylebox_override("normal",UI.style(Color("102b3520"),5,Color("48647055"),9))
	button.add_theme_stylebox_override("hover",UI.style(Color("24464ee8"),5,UI.TEAL.darkened(.35),9))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.remove_theme_color_override(key)

func _layout() -> void:
	if scroll == null: return
	var inset: float = 22.0 if size.y<620 else 40.0
	var width: float = clampf(size.x*.36,310,480)
	if mode=="paused": width = minf(430,size.x-2*inset)
	scroll.position = Vector2(inset,inset)
	scroll.size = Vector2(minf(width,size.x-2*inset),size.y-2*inset)
	title_label.add_theme_font_size_override("font_size",38 if size.y<620 else 56)
	body.add_theme_constant_override("separation",6 if size.y<620 else 10)

func _icon(key: String) -> Texture2D:
	var paths := {
		"campaign":"M5 18 L11 6 L20 16 M3 18 A2 2 0 1 0 7 18 A2 2 0 1 0 3 18 M9 6 A2 2 0 1 0 13 6 A2 2 0 1 0 9 6 M18 16 A2 2 0 1 0 22 16 A2 2 0 1 0 18 16",
		"management":"M4 20 V13 H7 V20 M10 20 V8 H13 V20 M16 20 V3 H19 V20",
		"sandbox":"M3 7 L12 2 L21 7 V17 L12 22 L3 17 Z M3 7 L12 12 L21 7 M12 12 V22",
		"settings":"M4 5 H20 M4 12 H20 M4 19 H20 M8 2 V8 M16 9 V15 M10 16 V22",
		"credits":"M12 8 V17 M12 4 V5 M3 2 H21 V22 H3 Z",
		"quit":"M9 4 H3 V20 H9 M10 12 H23 M18 7 L23 12 L18 17",
		"save":"M3 3 H18 L22 7 V21 H3 Z M7 3 V10 H17 V3 M7 21 V14 H17 V21",
		"load":"M2 20 V5 H9 L12 8 H22 V20 Z",
		"title":"M2 11 L12 2 L22 11 M5 9 V22 H19 V9 M10 22 V15 H14 V22"
	}
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#e8dec4" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>' % paths.get(key,paths.settings)
	var image := Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)
