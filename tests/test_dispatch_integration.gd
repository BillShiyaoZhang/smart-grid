extends SceneTree
## Real mixed-source dispatch, storage provenance, goals and persistence.
const Sim = preload("res://scripts/sim/grid_sim.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_merit_order()
	_test_export_cost()
	_test_clean_storage()
	_test_mixed_storage()
	_test_shared_contract_and_retry()
	_test_persistence()
	print("DISPATCH INTEGRATION: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+message)

func near(a: float,b: float) -> bool:
	return absf(a-b)<0.00001

func blank() -> RefCounted:
	var s = Sim.new()
	s.buildings.clear(); s.lines.clear(); s.objectives.clear()
	s.next_building_id=1; s.next_line_id=1; s.cash=1000000.0
	s.next_storm_at=100000.0
	s.digital.reset(s); s.digital.next_attack_at=100000.0
	s.evolution.unlocked.assign(s.evolution.TECHNOLOGIES.keys())
	return s

func link(s: RefCounted,a: int,b: int) -> void:
	var line: Dictionary = s._add_line(a,b)
	line.capacity=1000.0

func hot(s: RefCounted,kind: String,cell: Vector2i) -> Dictionary:
	var b: Dictionary = s._add_building(kind,cell)
	b.startup_remaining=0.0; b.ramp_mw=float(b.capacity)
	return b

func balanced(s: RefCounted) -> void:
	check(absf(float(s.totals.energy_balance_error))<0.000001,"merit dispatch conserves total MW")
	for b in s.buildings:
		var flow := 0.0
		for line in s.lines:
			if int(line.a)==int(b.id): flow+=float(line.flow)
			if int(line.b)==int(b.id): flow-=float(line.flow)
		check(absf(float(b.output)-float(b.served)-float(b.charging)-flow)<0.0001,"merit dispatch conserves nodal injections")

func _test_merit_order() -> void:
	var s = blank()
	var hydro := hot(s,"hydro",Vector2i(3,3))
	var gas := hot(s,"gas",Vector2i(4,3))
	var load: Dictionary = s._add_building("hospital",Vector2i(5,3))
	var terminal: Dictionary = s._add_building("intertie",Vector2i(6,3))
	link(s,hydro.id,gas.id); link(s,gas.id,load.id); link(s,load.id,terminal.id)
	s.time_hours=2.0
	check(s.set_market_policy("trade",125,500).ok,"mixed-source economic policy is accepted")
	check(near(gas.output,0.0) and near(hydro.output,load.served),"free hydro beats both gas and inexpensive imports")
	check(near(s.totals.import_mw,0.0) and near(s.totals.fuel_cost,0.0),"economic trading avoids needless purchases with sufficient free hydro")
	balanced(s)
	s=blank()
	var coal := hot(s,"coal",Vector2i(3,3))
	gas=hot(s,"gas",Vector2i(4,3))
	load=s._add_building("factory",Vector2i(5,3)); load.base_demand=30.0
	terminal=s._add_building("intertie",Vector2i(6,3))
	link(s,coal.id,gas.id); link(s,gas.id,load.id); link(s,load.id,terminal.id)
	s.time_hours=2.0
	check(s.set_market_policy("trade",125,500).ok,"coal-versus-spot fixture uses valid economic policy")
	check(near(gas.output,0.0) and near(s.totals.import_mw,0.0),"coal priced43 beats spot44.67 and gas68 while honoring committed output")
	balanced(s)

func _test_export_cost() -> void:
	var s = blank()
	var dynamo := hot(s,"dc_dynamo",Vector2i(3,3))
	var terminal: Dictionary = s._add_building("intertie",Vector2i(4,3))
	link(s,dynamo.id,terminal.id)
	s.time_hours=8.0; s.set_market_policy("trade",0,0)
	check(float(s.market.state.export_price)<108.0 and near(s.totals.export_mw,0.0) and near(dynamo.output,0.0),"high-cost early generators cannot export at a fuel loss")
	s.time_hours=19.0; s._refresh()
	check(float(s.market.state.export_price)>108.0 and float(s.totals.export_mw)>0.0,"high-cost unit exports only above its own marginal fuel cost")
	check(float(s.totals.export_income)>float(s.totals.fuel_cost),"incremental export revenue covers actual selected generation cost")
	balanced(s)

func solar_storage() -> RefCounted:
	var s=blank()
	s.time_hours=12.0
	var solar: Dictionary=s._add_building("solar",Vector2i(3,3))
	var battery: Dictionary=s._add_building("battery",Vector2i(4,3))
	battery.energy=0.0; battery.renewable_energy_mwh=0.0
	var load: Dictionary=s._add_building("hospital",Vector2i(5,3))
	link(s,solar.id,battery.id); link(s,battery.id,load.id)
	s._refresh()
	return s

func _test_clean_storage() -> void:
	var s=solar_storage()
	s.set_sandbox_goal("clean")
	s.step(1.0)
	var battery: Dictionary=s.get_building(2)
	check(float(battery.energy)>5.0 and near(battery.energy,battery.renewable_energy_mwh),"solar charging stores its actual renewable MWh after conversion losses")
	var held: Dictionary=battery.duplicate(true)
	for i in 10: s._refresh(); s.market_forecast()
	check(near(battery.energy,held.energy) and near(battery.renewable_energy_mwh,held.renewable_energy_mwh),"query refreshes never create or consume provenance")
	s.time_hours=20.0; s._refresh()
	var clean_before: float=s.sandbox_goal_hours
	s.step(.25)
	check(near(s.totals.renewable_share,0.0) and near(s.totals.renewable_supply_share,1.0),"generation mix and delivered renewable supply are distinct at night")
	check(float(s.sandbox_goal_hours)>clean_before,"solar battery supply preserves continuous clean operating progress")
	check(near(battery.energy,battery.renewable_energy_mwh),"discharging removes renewable stock with the same efficiency loss")
	balanced(s)

func _test_mixed_storage() -> void:
	var s=blank()
	var battery: Dictionary=s._add_building("battery",Vector2i(3,3))
	battery.energy=10.0; battery.renewable_energy_mwh=4.0
	var load: Dictionary=s._add_building("hospital",Vector2i(4,3))
	link(s,battery.id,load.id)
	s._refresh(); s.step(.1)
	check(near(s.totals.renewable_supply_share,.4),"mixed storage discharges the stored proportional source mix")
	check(near(float(battery.renewable_energy_mwh)/float(battery.energy),.4),"remaining stock preserves source fraction")
	s=blank()
	battery=s._add_building("battery",Vector2i(3,3)); battery.energy=0.0
	var terminal: Dictionary=s._add_building("intertie",Vector2i(4,3))
	link(s,battery.id,terminal.id)
	s.time_hours=2.0
	check(s.set_market_policy("trade",125,500).ok,"coal-versus-spot fixture uses valid economic policy"); s.set_storage_policy("arbitrage",60,150,0)
	s.step(.1)
	check(float(battery.energy)>0.0 and near(battery.renewable_energy_mwh,0.0),"unknown external purchases do not become renewable storage")
	balanced(s)

func _test_shared_contract_and_retry() -> void:
	var s=blank()
	var a: Dictionary=s._add_building("intertie",Vector2i(3,3))
	var first: Dictionary=s._add_building("hospital",Vector2i(4,3))
	var b: Dictionary=s._add_building("intertie",Vector2i(8,3))
	var second: Dictionary=s._add_building("hospital",Vector2i(9,3))
	link(s,a.id,first.id); link(s,b.id,second.id)
	check(s.set_market_policy("balanced",0,500).ok,"contract fixture forbids spot purchases")
	check(s.sign_supply_contract(5.0,12.0).ok,"shared contract is signed against two real terminal islands")
	check(near(s.totals.import_mw,5.0) and near(s.totals.contract_import_mw,5.0),"separate islands cannot each reuse the full prepaid delivery budget")
	check(near(float(first.served)+float(second.served),5.0),"shared contract serves at most its committed physical power")
	balanced(s)
	s=blank()
	var reactor := hot(s,"nuclear",Vector2i(3,3))
	reactor.ramp_mw=.5
	var cooling: Dictionary=s._add_building("cooling",Vector2i(4,3))
	var academy: Dictionary=s._add_building("academy",Vector2i(5,3))
	var battery: Dictionary=s._add_building("battery",Vector2i(6,3))
	battery.energy=1.0; battery.renewable_energy_mwh=1.0
	link(s,reactor.id,cooling.id); link(s,cooling.id,academy.id); link(s,academy.id,battery.id)
	s._solve(1.0)
	check(near(reactor.output,0.0) and near(battery.energy,0.0),"failed auxiliary supply blocks reactor and commits one battery withdrawal across retries")
	check(near(battery.output,.94) and near(battery.renewable_energy_mwh,0.0),"retry preserves discharge efficiency and provenance exactly once")
	balanced(s)

func _test_persistence() -> void:
	var s=solar_storage(); s.step(.5)
	var path := "user://test_dispatch_provenance.json"
	check(s.save_game(path).ok,"source-aware storage and assets save")
	var restored=Sim.new()
	check(restored.load_game(path).ok,"schema5 source-aware state loads")
	check(near(restored.get_building(2).renewable_energy_mwh,s.get_building(2).renewable_energy_mwh),"provenance survives a real save round trip")
	var data: Dictionary=s.snapshot()
	data.schema_version=4
	for b in data.buildings:
		for key in ["ownership","invested_capital","refund_basis","renewable_energy_mwh"]: b.erase(key)
	var file=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	check(restored.load_game(path).ok and near(restored.get_building(2).renewable_energy_mwh,0.0),"legacy unknown stored energy migrates conservatively")
	data=s.snapshot(); data.buildings[1].renewable_energy_mwh=float(data.buildings[1].energy)+1.0
	file=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	var old_cash: float=restored.cash
	check(not restored.load_game(path).ok and near(restored.cash,old_cash),"invalid source stock rejects without replacing live state")
	data=s.snapshot(); data.buildings[1].refund_basis=float(data.buildings[1].invested_capital)+1.0
	file=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	check(not restored.load_game(path).ok,"refunds cannot exceed invested funds in a save")
	DirAccess.remove_absolute(path)
