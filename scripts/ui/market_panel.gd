extends Control
## The trading desk submits simulation commands; forecasts and refreshes never settle money.
const PriceChart = preload("res://scripts/ui/market_chart.gd")
const TEAL := Color("77dbc0")
const CREAM := Color("f2eddb")
const MUTED := Color("95b0b6")
const ORANGE := Color("efbb7d")
const RED := Color("f38a79")
var game: Node
var headline: Dictionary = {}
var forecast_chart: Control
var tabs: TabContainer
var policy_mode: OptionButton
var buy_limit: SpinBox
var sell_floor: SpinBox
var tariff_mode: OptionButton
var valley_rate: SpinBox
var flat_rate: SpinBox
var peak_rate: SpinBox
var storage_mode: OptionButton
var charge_price: SpinBox
var discharge_price: SpinBox
var reserve_soc: SpinBox
var contract_mw: SpinBox
var contract_button: Button
var contract_label: Label
var commitment_label: Label
var connection_label: Label
var trade_status: Label
var tariff_status: Label
var storage_status: Label
var ledger_grid: GridContainer
var ledger_summary: Label
var advice: Label
var message_label: Label
var syncing := false

func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()

func open() -> void:
	refresh(true)
	show()

func close() -> void:
	hide()
	game._update_hud()
	game._update_inspector()

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.06,0.09,0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel: PanelContainer = game._panel(self,Vector2(144,50),Vector2(1312,900),Color("102c38ff"))
	var layout: VBoxContainer = game._column(panel,10)
	var header: HBoxContainer = game._row(layout,14)
	var title: VBoxContainer = game._column(header,1)
	game._label(title,"青屿湾电力交易中心  /  ENERGY EXCHANGE",11,TEAL)
	game._label(title,"让每一度电，都有更好的去处。",27,CREAM)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	game._label(header,"规划中 · 时间暂停",11,MUTED)
	game._button(header,"推进 1 小时",_advance,Vector2(116,40))
	game._button(header,"返回电网  Esc",close,Vector2(130,40))
	var cards: HBoxContainer = game._row(layout,10)
	for spec in [["spot","现货买价","¥0 / MWh"],["retail","当前零售电价","¥145 / MWh"],["exchange","外网功率","0.0 MW"],["profit","本日运营净收益","¥0"],["satisfaction","用户满意度","85 / 100"]]:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",game._style(Color("1b3b48"),10))
		cards.add_child(card)
		var v: VBoxContainer = game._column(card,3)
		game._label(v,spec[1],11,MUTED)
		headline[spec[0]] = game._label(v,spec[2],23,TEAL)
	var graph_row: HBoxContainer = game._row(layout,16)
	var chart_card := PanelContainer.new()
	chart_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_card.add_theme_stylebox_override("panel",game._style(Color("0b2531"),10))
	graph_row.add_child(chart_card)
	forecast_chart = PriceChart.new()
	forecast_chart.custom_minimum_size = Vector2(820,140)
	chart_card.add_child(forecast_chart)
	var forecast_notes: VBoxContainer = game._column(graph_row,9)
	forecast_notes.custom_minimum_size.x = 352
	game._label(forecast_notes,"未来 24 小时 · 参考报价",14,CREAM)
	advice = _text(forecast_notes,"",MUTED,12,348)
	connection_label = _text(forecast_notes,"",ORANGE,12,348)
	var build: Button = game._button(forecast_notes,"＋ 建造市场联络站 · ¥32k",_build_intertie,Vector2(0,34))
	build.tooltip_text = "联络站是跨区交易的物理节点。建成后用线路连到你的电网。"
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(0,340)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size",15)
	tabs.add_theme_color_override("font_selected_color",TEAL)
	tabs.add_theme_color_override("font_unselected_color",MUTED)
	tabs.add_theme_stylebox_override("panel",game._style(Color("153440"),10))
	tabs.add_theme_stylebox_override("tab_selected",game._style(Color("234954"),8,TEAL*Color(1,1,1,0.4)))
	tabs.add_theme_stylebox_override("tab_unselected",game._style(Color("102b37"),8))
	layout.add_child(tabs)
	_build_trade_tab()
	_build_tariff_tab()
	_build_storage_tab()
	_build_ledger_tab()
	message_label = game._label(layout,"配置改变后点击应用；报价与账本来自当前仿真。",12,MUTED)

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var body: VBoxContainer = game._column(scroll,10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return body

func _box(parent: Node, width: float=585) -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x = width
	card.add_theme_stylebox_override("panel",game._style(Color("1b3c49"),10))
	parent.add_child(card)
	return game._column(card,10)

func _text(parent: Node, value: String, color: Color=MUTED, font_size: int=12, width: float=540) -> Label:
	var label: Label = game._label(parent,value,font_size,color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width
	return label

func _select(parent: Node, title: String, choices: Array) -> OptionButton:
	var line: HBoxContainer = game._row(parent,12)
	var label: Label = game._label(line,title,13,CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var select := OptionButton.new()
	select.custom_minimum_size = Vector2(222,36)
	select.add_theme_stylebox_override("normal",game._style(Color("102c38"),7))
	select.add_theme_color_override("font_color",CREAM)
	select.add_theme_font_size_override("font_size",13)
	for choice in choices:
		select.add_item(choice)
	line.add_child(select)
	return select

func _spin(parent: Node, title: String, low: float, high: float, step_: float, suffix: String="¥ / MWh") -> SpinBox:
	var line: HBoxContainer = game._row(parent,12)
	var label: Label = game._label(line,title,13,MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step_
	spin.suffix = suffix
	spin.custom_minimum_size = Vector2(222,35)
	spin.get_line_edit().add_theme_stylebox_override("normal",game._style(Color("102c38"),7))
	spin.get_line_edit().add_theme_color_override("font_color",CREAM)
	spin.get_line_edit().add_theme_font_size_override("font_size",13)
	line.add_child(spin)
	return spin

func _build_trade_tab() -> void:
	var body := _tab("购售电策略")
	var row: HBoxContainer = game._row(body,14)
	var config := _box(row)
	game._label(config,"决定什么时候与外网交易",18,CREAM)
	policy_mode = _select(config,"运行策略",["离网运行 · 禁用交易","缺电保供 · 只补缺额","经济交易 · 择价购售"])
	buy_limit = _spin(config,"最高现货买价",0,500,5)
	sell_floor = _spin(config,"最低外售电价",0,500,5)
	game._button(config,"应用交易策略",_apply_policy,Vector2(0,37))
	var notes := _box(row)
	game._label(notes,"线路会决定交易能否落地",18,TEAL)
	trade_status = _text(notes,"")
	_text(notes,"保供模式：本地电源优先，供应不足才买电。经济交易：比较燃气成本、现货报价与储能策略，在阈值内购售电。")
	_text(notes,"外网通过联络站接入，进口功率必须沿你的线路送达用户。线路跳闸会断开下游；联络站容量和风暴降额限制交易规模。")
	_text(notes,"外售结算价为现货买价的 72%，同一电气岛不会同时购电与售电。高峰时段留出备用容量更稳妥。",ORANGE)

func _build_tariff_tab() -> void:
	var body := _tab("零售电价")
	var row: HBoxContainer = game._row(body,14)
	var config := _box(row)
	game._label(config,"给用户一份可持续的电费账单",18,CREAM)
	tariff_mode = _select(config,"电价方案",["统一电价","峰谷电价","自定峰平谷"])
	tariff_mode.item_selected.connect(_tariff_selected)
	valley_rate = _spin(config,"谷价 · 23:00–07:00",20,500,5)
	flat_rate = _spin(config,"平价 · 07:00–17:00 / 21:00–23:00",20,500,5)
	peak_rate = _spin(config,"峰价 · 17:00–21:00",20,500,5)
	game._button(config,"应用零售电价",_apply_tariff,Vector2(0,37))
	var notes := _box(row)
	game._label(notes,"收入不只取决于单价",18,TEAL)
	tariff_status = _text(notes,"")
	_text(notes,"高价会压低住宅与工业的需求。高账单和停电降低满意度，低于 60 后用户逐步流失。医院不减少需求，保持关键负荷优先。")
	_text(notes,"统一电价使用平价覆盖全天；峰谷方案与自定方案按右上方曲线结算。先观察晚高峰购电成本，再决定峰价与储能策略。")
	_text(notes,"价格单位为 ¥/MWh。普通用户按挂牌价结算，医院适用最高 ¥145/MWh 的医疗保供价；提价无法提高医院账单。",ORANGE)

func _build_storage_tab() -> void:
	var body := _tab("储能与锁价合约")
	var row: HBoxContainer = game._row(body,14)
	var storage := _box(row)
	game._label(storage,"把低价时段留给未来",18,CREAM)
	storage_mode = _select(storage,"电池策略",["保供备用","峰谷套利"])
	charge_price = _spin(storage,"现货低于此价购电充能",0,500,5)
	discharge_price = _spin(storage,"现货高于此价释放储能",0,500,5)
	reserve_soc = _spin(storage,"最低备用电量",0,95,5,"% SOC")
	game._button(storage,"应用储能策略",_apply_storage,Vector2(0,37))
	storage_status = _text(storage,"",MUTED,11)
	var contract := _box(row)
	game._label(contract,"锁定未来 12 小时购电价格",18,TEAL)
	contract_label = _text(contract,"",CREAM,13)
	contract_mw = _spin(contract,"约定购电功率",1,14,1,"MW")
	contract_mw.value_changed.connect(func(_value: float): _update_commitment())
	commitment_label = _text(contract,"",ORANGE,12)
	contract_button = game._button(contract,"签订 12 小时锁价合约",_sign_contract,Vector2(0,37))
	_text(contract,"按约定功率持续付费，即使用不完、线路故障或主动离网也要付款。合约期内不可撤销；超额用电按现货阈值购买。",ORANGE,11)
	_text(contract,"合约对冲涨价，也可能错过低价；先判断负荷与风光预测。每次只允许一份有效合约。",MUTED,11)

func _build_ledger_tab() -> void:
	var body := _tab("运营结算账本")
	game._label(body,"逐小时计费，按游戏日归集",18,CREAM)
	ledger_summary = _text(body,"",TEAL,14,1200)
	ledger_grid = GridContainer.new()
	ledger_grid.columns = 10
	ledger_grid.add_theme_constant_override("h_separation",12)
	ledger_grid.add_theme_constant_override("v_separation",14)
	body.add_child(ledger_grid)
	_text(body,"净收益 = 零售收入 + 外售收入 − 现货购电 − 锁价合约 − 燃气燃料 − 运维 − 失供补偿。",CREAM,12,1200)
	_text(body,"账本仅记录运营现金流；建设、研究、维护派单和委托奖励会改变总资金，单独保留在调度日志中。刷新报价和切换页面不会重复结算。",MUTED,11,1200)

func _tariff_selected(index: int) -> void:
	if syncing:
		return
	if index == 1:
		valley_rate.value = 85
		flat_rate.value = 145
		peak_rate.value = 220
	valley_rate.editable = index != 0
	peak_rate.editable = index != 0
	message_label.text = "草案尚未生效：调整后点击「应用零售电价」。"
	message_label.add_theme_color_override("font_color",ORANGE)

func _apply_policy() -> void:
	_commit(game.sim.set_market_policy(["off","balanced","trade"][policy_mode.selected],buy_limit.value,sell_floor.value))

func _apply_tariff() -> void:
	_commit(game.sim.set_tariff(["flat","tou","custom"][tariff_mode.selected],valley_rate.value,flat_rate.value,peak_rate.value))

func _apply_storage() -> void:
	_commit(game.sim.set_storage_policy(["reserve","arbitrage"][storage_mode.selected],charge_price.value,discharge_price.value,reserve_soc.value/100.0))

func _sign_contract() -> void:
	_commit(game.sim.sign_supply_contract(contract_mw.value,12.0))

func _advance() -> void:
	game.sim.step(1.0)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	refresh(false)
	message_label.text = "已推进 1 游戏小时，供电、交易、账本和资金均已结算。"
	message_label.add_theme_color_override("font_color",TEAL)

func _build_intertie() -> void:
	close()
	game.build_kind = "intertie"
	game._set_tool("build")
	game._notify("选择空地建造市场联络站，再用连线工具接入电网。")

func _commit(result: Dictionary) -> void:
	game._apply(result)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	refresh(true)
	message_label.text = ("✓  " if result.get("ok",false) else "!  ")+str(result.get("message","操作完成"))
	message_label.add_theme_color_override("font_color",TEAL if result.get("ok",false) else ORANGE)

func refresh(sync_inputs: bool=false) -> void:
	if game == null or game.sim.get("market") == null:
		return
	var sim: RefCounted = game.sim
	var state: Dictionary = sim.market.state
	var t: Dictionary = sim.totals
	headline.spot.text = "¥%.2f / MWh" % state.get("spot_price",0)
	headline.retail.text = "¥%.0f / MWh" % state.get("retail_price",145)
	var imports: float = t.get("import_mw",0)
	var exports: float = t.get("export_mw",0)
	headline.exchange.text = "↑ %.1f   ↓ %.1f MW" % [imports,exports]
	var satisfaction: float = state.get("satisfaction",85)
	headline.satisfaction.text = "%.0f / 100" % satisfaction
	headline.satisfaction.add_theme_color_override("font_color",TEAL if satisfaction>=70 else ORANGE)
	var day_net := 0.0
	for entry in sim.market.ledger:
		if int(entry.get("day",0)) == int(sim.day):
			day_net = float(entry.get("net",0))
	headline.profit.text = ("+ " if day_net >= 0 else "− ")+"¥"+game._number(absf(day_net))
	headline.profit.add_theme_color_override("font_color",TEAL if day_net>=0 else RED)
	var forecast: Array = sim.market_forecast()
	forecast_chart.set_points(forecast)
	var low := INF
	var high := 0.0
	for point in forecast:
		low = minf(low,float(point.get("spot",0)))
		high = maxf(high,float(point.get("spot",0)))
	advice.text = "现货参考区间 ¥%.2f–%.2f/MWh\n外售结算价 ¥%.2f/MWh\n预测采用当前天气；风暴可能改变报价。" % [low if is_finite(low) else 0,high,state.get("export_price",0)]
	var capacity: float = t.get("grid_capacity",0)
	connection_label.text = "尚未接入外网。先建设联络站并接线。" if capacity<=0 else "外网可用容量 %.1f MW · 进口与出口共用" % capacity
	trade_status.text = "当前进口 %.2f MW / 外售 %.2f MW\n现货购电 ¥%.0f/h · 外售收入 ¥%.0f/h" % [imports,exports,t.get("import_cost",0),t.get("export_income",0)]
	tariff_status.text = "当前生效电价 ¥%.0f/MWh\n零售收入 ¥%.0f/h · 失供补偿 ¥%.0f/h\n住宅需求系数 %.0f%% · 工业 %.0f%%" % [state.get("retail_price",145),t.get("retail_income",0),t.get("outage_cost",0),100*sim.market.demand_multiplier("home"),100*sim.market.demand_multiplier("factory")]
	storage_status.text = "当前储能 %.1f MWh · 净放电 %.2f MW。\n套利会损耗能量；备用比例与电池功率共同限制出力。" % [t.get("battery_mwh",0),t.get("battery_power",0)]
	var remaining: float = state.get("contract_remaining",0)
	contract_label.text = "已锁定 %.1f MW × ¥%.2f/MWh\n剩余 %.1f 小时；当前合约费用 ¥%.2f/h" % [state.get("contract_mw",0),state.get("contract_price",0),remaining,t.get("contract_cost",0)] if remaining>0 else "当前 12 小时锁价报价：¥%.2f/MWh" % state.get("contract_quote",0)
	contract_button.disabled = remaining>0 or capacity<=0
	contract_mw.max_value = maxf(1,capacity)
	if sync_inputs:
		syncing = true
		policy_mode.select(maxi(0,["off","balanced","trade"].find(state.get("market_mode","balanced"))))
		buy_limit.value = state.get("buy_limit",120)
		sell_floor.value = state.get("sell_floor",90)
		tariff_mode.select(maxi(0,["flat","tou","custom"].find(state.get("tariff_mode","flat"))))
		valley_rate.value = state.get("valley_rate",85)
		flat_rate.value = state.get("flat_rate",145)
		peak_rate.value = state.get("peak_rate",220)
		valley_rate.editable = tariff_mode.selected != 0
		peak_rate.editable = tariff_mode.selected != 0
		storage_mode.select(1 if state.get("storage_mode","reserve") == "arbitrage" else 0)
		charge_price.value = state.get("charge_price",60)
		discharge_price.value = state.get("discharge_price",150)
		reserve_soc.value = float(state.get("reserve_soc",.2))*100
		if contract_mw.value<=1:
			contract_mw.value = minf(5,contract_mw.max_value)
		syncing = false
	_update_commitment()
	_refresh_ledger()

func _update_commitment() -> void:
	if commitment_label == null or game == null or game.sim.get("market") == null:
		return
	var price: float = game.sim.market.state.get("contract_quote",0)
	commitment_label.text = "本次承诺：%.1f MW × 12h × ¥%.2f\n合计约 ¥%s，无论实际用电量都需支付。" % [contract_mw.value,price,game._number(contract_mw.value*12*price)]

func _refresh_ledger() -> void:
	game._clear_children(ledger_grid)
	for title in ["游戏日","零售收入","外售收入","现货购电","锁价合约","燃料成本","运维成本","失供补偿","净收益","购 / 售 MWh"]:
		var heading: Label = game._label(ledger_grid,title,11,MUTED)
		heading.custom_minimum_size.x = 104
	var entries: Array = game.sim.market.ledger
	if entries.is_empty():
		ledger_summary.text = "尚无结算。返回运营或推进一小时，开始积累账单。"
		return
	var total_net := 0.0
	for entry in entries:
		total_net += float(entry.get("net",0))
	for i in range(entries.size()-1,maxi(-1,entries.size()-8),-1):
		var entry: Dictionary = entries[i]
		var values := ["第 %d 天" % entry.get("day",1),"¥"+game._number(entry.get("retail_revenue",0)),"¥"+game._number(entry.get("export_revenue",0)),"¥"+game._number(entry.get("import_cost",0)),"¥"+game._number(entry.get("contract_cost",0)),"¥"+game._number(entry.get("fuel_cost",0)),"¥"+game._number(entry.get("maintenance_cost",0)),"¥"+game._number(entry.get("outage_cost",0)),"¥"+game._number(entry.get("net",0)),"%.1f / %.1f" % [entry.get("import_mwh",0),entry.get("export_mwh",0)]]
		for j in range(values.size()):
			game._label(ledger_grid,values[j],12,TEAL if j==8 and float(entry.get("net",0))>=0 else CREAM)
	ledger_summary.text = "最近 %d 个游戏日累计运营净收益  ¥%s · 当前第 %d 天" % [entries.size(),game._number(total_net),game.sim.day]
