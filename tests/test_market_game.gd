extends SceneTree
## End-to-end market UI coverage using real controls and simulation commands.
var game: Node
var desk: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func button_in(parent: Node, caption: String) -> Button:
	if parent is Button and caption in parent.text:
		return parent
	for child in parent.get_children():
		var found := button_in(child,caption)
		if found != null:
			return found
	return null

func press(parent: Node, caption: String) -> void:
	var button := button_in(parent,caption)
	check(button != null,"action exists: " + caption)
	if button != null:
		button.pressed.emit()

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func connect_assets(a: int,b: int) -> void:
	game._set_tool("line")
	game._handle_map_click(game.sim.get_building(a).cell)
	game._handle_map_click(game.sim.get_building(b).cell)

func ledger_net() -> float:
	var value := 0.0
	for row in game.sim.market.ledger:
		value += float(row.net)
	return value

func energy() -> float:
	var value := 0.0
	for building in game.sim.buildings:
		if building.kind == "battery":
			value += float(building.energy)
	return value

func same_values(a: Variant,b: Variant) -> bool:
	# JSON preserves meaning rather than binary float identity.
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for field in a:
			if not b.has(field) or not same_values(a[field],b[field]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same_values(a[i],b[i]):
				return false
		return true
	return a == b

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	desk = game.market_panel
	check(desk != null and not desk.visible,"market desk is created and initially hidden")
	check(game.build_buttons.has("intertie"),"market terminal is available in construction palette")
	key(KEY_M)
	check(desk.visible and game._modal_open(),"M opens market as a modal")
	var before_hours: float = game.sim.elapsed_hours
	game._process(1.0)
	check(is_equal_approx(float(game.sim.elapsed_hours),before_hours),"market planning pauses automatic simulation time")
	key(KEY_ESCAPE)
	check(not desk.visible and not game._modal_open(),"Escape returns to grid")
	press(game.root_ui,"电力市场")
	check(desk.visible,"top navigation opens market")
	desk.close()
	press(game.root_ui,"电价 · 交易 · 结算")
	check(desk.visible,"market ticker opens trading desk")
	check(desk.tabs.get_tab_count() == 4 and desk.headline.size() == 5,"four market tabs and five live indicators are available")
	check(desk.forecast_chart.points.size() == 24,"forecast chart contains twenty-four actual market quotes")
	check(desk.forecast_chart.points[0].has("day") and desk.forecast_chart.points[0].has("hour"),"forecast quotes retain their simulation time")

	# Draft controls do not execute policy changes or settlement.
	var cash_before: float = game.sim.cash
	var energy_before := energy()
	var old_rate: float = game.sim.market.state.flat_rate
	desk.flat_rate.value = 180
	desk.buy_limit.value = 250
	desk.refresh(false)
	check(is_equal_approx(float(desk.flat_rate.value),180) and is_equal_approx(float(desk.buy_limit.value),250),"live refresh preserves unapplied user drafts")
	check(is_equal_approx(float(game.sim.market.state.flat_rate),old_rate),"editing tariff draft does not change simulation tariff")
	check(is_equal_approx(float(game.sim.cash),cash_before) and is_equal_approx(energy(),energy_before),"draft edits and refresh do not settle cash or battery energy")
	desk.close()
	connect_assets(2,6)
	var demand_before: float = game.sim.totals.demand
	var income_before: float = game.sim.totals.retail_income
	desk.open()
	desk.tariff_mode.select(0)
	desk.flat_rate.value = 180
	press(desk,"应用零售电价")
	check(is_equal_approx(float(game.sim.market.state.retail_price),180),"apply tariff button changes effective retail price")
	check(float(game.sim.totals.demand) < demand_before and float(game.sim.totals.retail_income) > income_before,"higher applied tariff changes demand and revenue")

	# Every forecast route and tab refresh must remain observational.
	var state_before: Dictionary = game.sim.market.snapshot().duplicate(true)
	cash_before = game.sim.cash
	energy_before = energy()
	for i in range(4):
		desk.tabs.current_tab = i
		desk.refresh(i % 2 == 0)
		game.sim.market_forecast()
	check(game.sim.market.snapshot() == state_before,"forecast and tab refresh do not mutate market state or ledger")
	check(is_equal_approx(float(game.sim.cash),cash_before) and is_equal_approx(energy(),energy_before),"forecast and tab refresh never create money or energy")
	press(desk,"建造市场联络站")
	check(not desk.visible and game.tool == "build" and game.build_kind == "intertie","market build action closes modal and enters terminal placement")
	var terminal_cell := Vector2i(4,6)
	game._handle_map_click(terminal_cell)
	var terminal_id: int = game._building_at(terminal_cell)
	check(terminal_id > 0 and game.sim.get_building(terminal_id).kind == "intertie" and game.visuals.has(terminal_id),"market terminal placement creates a real simulation and visual asset")
	check(is_zero_approx(float(game.sim.totals.import_mw)),"unconnected terminal cannot import to city")
	connect_assets(terminal_id,2)
	var terminal_line: int = game.sim.lines.back().id
	check(float(game.sim.totals.grid_capacity) > 0.0,"connected terminal exposes physical exchange capacity")

	# Add real load so imports are necessary even with initial battery reserves.
	game.build_buttons.factory.pressed.emit()
	var factory_cell := Vector2i(11,10)
	game._handle_map_click(factory_cell)
	var factory_id: int = game._building_at(factory_cell)
	connect_assets(factory_id,2)
	game.sim.set_dispatch(1,0.0)
	desk.open()
	desk.policy_mode.select(1)
	desk.buy_limit.value = 500
	desk.sell_floor.value = 0
	press(desk,"应用交易策略")
	check(game.sim.market.state.market_mode == "balanced" and float(game.sim.market.state.buy_limit) == 500,"policy application uses selected mode and price threshold")
	check(float(game.sim.totals.import_mw) > 0.0 and absf(float(game.sim.get_line(terminal_line).flow)) > 0.0,"physical imports supply load through terminal cable")
	game.sim.toggle_line(terminal_line)
	desk.refresh(false)
	check(is_zero_approx(float(game.sim.totals.import_mw)) and is_zero_approx(float(game.sim.totals.export_mw)),"opening terminal cable stops both import and export")
	game.sim.toggle_line(terminal_line)

	desk.storage_mode.select(1)
	desk.charge_price.value = 50
	desk.discharge_price.value = 150
	desk.reserve_soc.value = 35
	press(desk,"应用储能策略")
	check(game.sim.market.state.storage_mode == "arbitrage" and is_equal_approx(float(game.sim.market.state.reserve_soc),0.35),"storage controls apply arbitrage and fractional reserve SOC")
	var valid_charge: float = game.sim.market.state.charge_price
	desk.charge_price.value = 200
	desk.discharge_price.value = 100
	press(desk,"应用储能策略")
	check(is_equal_approx(float(game.sim.market.state.charge_price),valid_charge) and desk.message_label.text.begins_with("!"),"invalid storage thresholds are rejected with feedback")

	desk.contract_mw.value = 3
	var quantity_pattern := RegEx.new()
	quantity_pattern.compile("承诺：([0-9.]+) MW")
	var quantity_match := quantity_pattern.search(desk.commitment_label.text)
	check(quantity_match != null and is_equal_approx(float(quantity_match.get_string(1)),3.0) and "12h" in desk.commitment_label.text and "无论" in desk.commitment_label.text,"contract UI presents quantity duration and take-or-pay commitment before signing")
	cash_before = game.sim.cash
	press(desk,"签订 12 小时锁价合约")
	check(float(game.sim.market.state.contract_mw) == 3 and float(game.sim.market.state.contract_remaining) == 12,"contract button creates the reviewed twelve-hour commitment")
	check(desk.contract_button.disabled and is_equal_approx(float(game.sim.cash),cash_before),"active contract disables signing and does not bill before time advances")
	var contract_before: Dictionary = game.sim.market.state.duplicate(true)
	desk._sign_contract()
	check(game.sim.market.state == contract_before and desk.message_label.text.begins_with("!"),"repeated active contract signing is rejected without changing commitment")

	# Advance is the explicit settlement boundary even while the modal stays open.
	var old_net := ledger_net()
	cash_before = game.sim.cash
	before_hours = game.sim.elapsed_hours
	press(desk,"推进 1 小时")
	var net_delta := ledger_net() - old_net
	check(is_equal_approx(float(game.sim.elapsed_hours),before_hours+1.0) and desk.visible,"advance button settles exactly one game hour while market remains open")
	check(is_equal_approx(float(game.sim.cash)-cash_before,net_delta),"operating ledger net exactly matches settled cash movement")
	check(game.sim.market.ledger.size() > 0 and float(game.sim.market.ledger.back().contract_cost) > 0.0 and float(game.sim.market.ledger.back().import_mwh) > 0.0,"ledger includes actual contract charges and delivered imports")
	check(float(game.sim.market.state.contract_remaining) < 12 and float(game.sim.market.state.contract_remaining) > 10.9,"settlement reduces active contract duration")
	check(desk.ledger_grid.get_child_count() > 10 and "净收益" in desk.ledger_summary.text,"settled rows and net summary are rendered in ledger tab")
	cash_before = game.sim.cash
	energy_before = energy()
	old_net = ledger_net()
	for i in range(5):
		desk.refresh(false)
	check(is_equal_approx(float(game.sim.cash),cash_before) and is_equal_approx(energy(),energy_before) and is_equal_approx(ledger_net(),old_net),"repeated post-settlement refresh cannot double bill or dispatch batteries")

	# Asset inspector entry points reach the same desk and correct tab.
	desk.close()
	game._set_tool("select")
	game._handle_map_click(game.sim.get_building(9).cell)
	press(game.inspector_box,"储能策略与电价")
	check(desk.visible and desk.tabs.current_tab == 2,"battery inspector opens storage strategy tab")
	desk.close()
	game._handle_map_click(terminal_cell)
	press(game.inspector_box,"打开电力交易中心")
	check(desk.visible,"terminal inspector opens market desk")
	key(KEY_M)
	check(not desk.visible,"M also closes an open trading desk")

	# Reopening after snapshot load must bind the current market model.
	var path := "/tmp/tidal_market_ui_save.json"
	var saved_market: Dictionary = game.sim.market.snapshot().duplicate(true)
	check(game.sim.save_game(path).ok,"market integration state saves successfully")
	game.sim.set_tariff("flat",85,100,220)
	check(game.sim.load_game(path).ok,"market integration state reloads successfully")
	desk.open()
	check(same_values(game.sim.market.snapshot(),saved_market) and is_equal_approx(float(desk.flat_rate.value),180),"reopened desk reflects loaded state and ledger rather than stale model")
	DirAccess.remove_absolute(path)
	game._new_game()
	check(not desk.visible and game.sim.market.ledger.is_empty() and float(game.sim.market.state.contract_remaining) == 0.0,"new game closes desk and clears contracts and ledger")
	desk.open()
	check(is_equal_approx(float(desk.flat_rate.value),145),"new game desk refreshes default tariff")
	desk.close()

	# A second, midday fixture proves that sale controls drive real outward flow.
	game.sim.time_hours = 12.0
	game.sim._refresh()
	game.build_buttons.intertie.pressed.emit()
	game._handle_map_click(terminal_cell)
	terminal_id = game._building_at(terminal_cell)
	connect_assets(terminal_id,2)
	terminal_line = game.sim.lines.back().id
	game.build_buttons.solar.pressed.emit()
	game._handle_map_click(Vector2i(5,4))
	connect_assets(game._building_at(Vector2i(5,4)),2)
	desk.open()
	desk.policy_mode.select(2)
	desk.buy_limit.value = 500
	desk.sell_floor.value = 0
	press(desk,"应用交易策略")
	check(game.sim.market.state.market_mode == "trade" and float(game.sim.totals.export_mw) > 0.0,"trade policy exports real midday renewable surplus")
	check(float(game.sim.get_building(terminal_id).export_mw) > 0.0 and is_zero_approx(float(game.sim.totals.import_mw)),"terminal records outward flow without simultaneous imports")
	game.sim.toggle_line(terminal_line)
	desk.refresh(false)
	check(is_zero_approx(float(game.sim.totals.export_mw)),"disconnecting terminal also stops positive outward trade")
	desk.close()
	print("MARKET GAME TESTS: %d checks; %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
