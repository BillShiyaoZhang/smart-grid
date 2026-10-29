extends VBoxContainer
## Contextual editor. Drafts live in the planning session, commands use the real queue.
const UI = preload("res://scripts/ui/ui_kit.gd")
var panel: Control
var game: Node
var facility_id := -1
var inputs: Dictionary = {}
var status_label: Label
var draft_label: Label
var method: OptionButton
var reason_label: Label
var syncing := false
var _fields: Dictionary = {}

func setup(owner_panel: Control, id: int) -> void:
	panel=owner_panel
	game=panel.game
	facility_id=id
	set_meta("facility_editor",true)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	var building: Dictionary=game.sim.get_building(id)
	if building.is_empty(): return
	UI.label(self,"运行方案",20)
	var storage: bool=game.sim.evolution.is_storage(str(building.kind))
	var generator: bool=game.sim.evolution.is_generator(str(building.kind)) or building.kind=="gas"
	if storage:
		var choices := OptionButton.new()
		for title in ["保供优先","高峰支援","低买高卖","继承全网默认","旧版自定义"]: choices.add_item(title)
		choices.fit_to_longest_item=false
		choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		add_child(choices)
		inputs.intent=choices
		choices.item_selected.connect(func(_index: int): _save())
		_number("reserve","有效备用电量 %",0,90,5)
		_number("peak","削峰起点",0,23,1)
	elif generator:
		var enabled := CheckButton.new()
		enabled.text="允许运行"
		add_child(enabled)
		inputs.enabled=enabled
		enabled.toggled.connect(func(_value: bool): _save())
		_number("dispatch","出力上限 %",0,100,5)
	else:
		var advanced:=UI.button(self,"打开此设施高级设置",func(): panel.select_facility(facility_id); panel.open())
		advanced.tooltip_text="冷却、生态下泄、保护等专业设置"
		return
	method=OptionButton.new()
	method.add_item("现场队 · ¥350 · 约21分钟")
	method.add_item("远程 · 需可信观测与控制")
	method.fit_to_longest_item=false
	method.clip_text=true
	method.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_child(method)
	method.item_selected.connect(func(_index: int): _save())
	status_label=UI.label(self,"",14,UI.MUTED)
	status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	reason_label=UI.label(self,"",14,UI.MUTED)
	reason_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	draft_label=UI.label(self,"",14,UI.AMBER)
	draft_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	UI.action(UI.button(self,"提交运行方案",_submit))
	UI.button(self,"重置此设施草案",_reset)
	refresh()

func _number(key: String, caption: String, low: float, high: float, step_value: float) -> void:
	var row:=UI.row(self,6)
	UI.label(row,caption,14,UI.MUTED).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var input:=SpinBox.new()
	input.min_value=low
	input.max_value=high
	input.step=step_value
	input.custom_minimum_size=Vector2(92,34)
	row.add_child(input)
	inputs[key]=input
	input.value_changed.connect(func(_value: float): _save())

func _save() -> void:
	if syncing or facility_id<0: return
	var building: Dictionary=game.sim.get_building(facility_id)
	if building.is_empty(): return
	var effective: Dictionary=panel._effective_facility(building)
	var values: Dictionary=panel.drafts.retain(str(facility_id),effective)
	for key in inputs:
		if key=="enabled": values[key]=inputs[key].button_pressed
		elif key=="intent": values[key]=["supply","peak","arbitrage","inherit","legacy_custom"][inputs[key].selected]
		else: values[key]=inputs[key].value
	values.method=1 if method.selected==0 else 0
	panel.drafts.retain(str(facility_id),effective,values)
	_fields=values
	_update_state()

func refresh() -> void:
	if status_label==null: return
	var building: Dictionary=game.sim.get_building(facility_id)
	if building.is_empty(): return
	var focus: Control=get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var editing: bool=focus!=null and is_ancestor_of(focus)
	var values: Dictionary=panel.drafts.retain(str(facility_id),panel._effective_facility(building))
	_fields=values
	if not editing:
		syncing=true
		for key in inputs:
			if key=="enabled": inputs[key].set_pressed_no_signal(bool(values.get(key,true)))
			elif key=="intent": inputs[key].select(maxi(0,["supply","peak","arbitrage","inherit","legacy_custom"].find(str(values.get(key,"legacy_custom")))))
			else: inputs[key].set_value_no_signal(float(values.get(key,0)))
		method.select(0 if int(values.get("method",1))==1 else 1)
		syncing=false
	method.set_item_disabled(1,not game.sim.feature_enabled("remote") or not game.sim.digital.can_configure(game.sim,facility_id))
	_update_state()

func _update_state() -> void:
	if status_label==null: return
	var pending := false
	for pair in [[game.sim.digital.field_jobs,"现场队"],[game.sim.digital.pending_commands,"远程"]]:
		for job in pair[0]:
			if job.get("kind","")=="facility" and int(job.get("building_id",-1))==facility_id:
				status_label.text="已提交 → %s执行中 · 剩余 %.0f分钟" % [pair[1],float(job.remaining)*60]
				pending=true
	if not pending:
		status_label.text="当前设置正在生效"
		for receipt in game.sim.operation_receipts():
			if receipt.get("action","")=="facility" and int(receipt.get("target_id",-1))==facility_id:
				status_label.text="✓ 已生效" if receipt.get("phase","")=="executed" else "! 已拒绝 · "+str(receipt.get("message","请核实执行条件"))
	var changed: bool=panel.drafts.dirty(str(facility_id))
	draft_label.text="草案尚未提交" if changed else "字段与当前生效设置一致"
	if game.sim.has_method("storage_status") and inputs.has("intent"):
		var storage: Dictionary=game.sim.storage_status(facility_id)
		draft_label.text+=("\n继承全网方案" if storage.get("inherited",false) else "\n此设施独立方案")
		reason_label.text=str(storage.get("reason",""))
		inputs.reserve.editable=str(_fields.get("intent","legacy_custom"))!="inherit"
		inputs.peak.get_parent().visible=str(_fields.get("intent","legacy_custom")) in ["peak","legacy_custom"]
		inputs.peak.editable=game.sim.evolution.has_technology("smart_storage")

func _reset() -> void:
	var building: Dictionary=game.sim.get_building(facility_id)
	if building.is_empty(): return
	panel.drafts.reset(str(facility_id),panel._effective_facility(building))
	refresh()

func _submit() -> void:
	_save()
	var building: Dictionary=game.sim.get_building(facility_id)
	if building.is_empty(): return
	var execution: String="field" if method.selected==0 else "remote"
	var result: Dictionary
	if inputs.has("intent") and str(_fields.get("intent","legacy_custom"))!="legacy_custom" and game.sim.has_method("set_storage_intent"):
		if str(_fields.intent)=="peak":
			result=game.sim.configure_facility(facility_id,{"storage_intent":"peak","storage_reserve":float(_fields.reserve)/100.0,"peak_hour":float(_fields.peak)},execution)
		else: result=game.sim.set_storage_intent(str(_fields.intent),float(_fields.reserve)/100.0,facility_id,execution)
	else:
		var settings: Dictionary={}
		if inputs.has("enabled"): settings.enabled=bool(_fields.enabled)
		if inputs.has("dispatch"): settings.dispatch=float(_fields.dispatch)/100.0
		if inputs.has("reserve"):
			settings.storage_mode=["auto","hold","peak"][int(_fields.get("storage",0))]
			settings.reserve_soc=float(_fields.reserve)/100.0
			settings.peak_hour=float(_fields.peak)
		result=game.sim.configure_facility(facility_id,settings,execution)
	game._apply(result)
	game._sync_world(true)
	game._update_hud()
	status_label.text=("已提交 · " if result.get("ok",false) else "! ")+str(result.get("message",""))
	refresh()
