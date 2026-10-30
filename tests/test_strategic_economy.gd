extends SceneTree

const Sim = preload("res://scripts/sim/grid_sim.gd")
const Strategy = preload("res://scripts/sim/strategic_economy.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	_test_activation_and_validation()
	_test_loans_and_policy()
	_test_project_delivery_and_cancellation()
	_test_forward_delivery()
	_test_auction_reserves_and_hazards()
	_test_persistence_and_financial_reconciliation()
	print("STRATEGIC ECONOMY: %d checks; %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+description)

func near(a: float,b: float,tolerance: float=0.0001) -> bool:
	return absf(a-b)<=tolerance

func blank() -> RefCounted:
	var sim=Sim.new()
	sim.buildings.clear()
	sim.lines.clear()
	sim.objectives.clear()
	sim.digital.reset(sim)
	sim.digital.next_attack_at=10000
	sim.next_storm_at=10000
	sim.next_building_id=1
	sim.next_line_id=1
	sim.cash=1000000
	sim.strategy.reset()
	sim._refresh()
	return sim

func _test_activation_and_validation() -> void:
	var sim=blank()
	check(not sim.strategy.enabled,"new model preserves legacy rules until commissioned")
	check(not sim.strategy.take_loan(sim,10000).ok,"inactive finance rejects new borrowing")
	check(near(sim.strategy.rates(sim).expenses,0),"inactive policy has no invisible costs")
	check(sim.strategy.enable(sim).ok,"modern operation commissions long-term management")
	var snapshot: Dictionary=sim.strategy.snapshot()
	var clone=Strategy.new()
	clone.restore(JSON.parse_string(JSON.stringify(snapshot)))
	check(clone.snapshot()==snapshot,"JSON numeric conversion restores full strategy state")
	var bad: Dictionary=snapshot.duplicate(true)
	bad.enabled="true"
	check(not Strategy.valid(bad),"malformed activation flag rejected")
	bad=snapshot.duplicate(true)
	bad.policy.tariff_cap=INF
	check(not Strategy.valid(bad),"nonfinite policy rejected")
	bad=snapshot.duplicate(true)
	bad.day_ahead=[{"start":1,"mw":5,"price":100},{"start":1,"mw":5,"price":100}]
	check(not Strategy.valid(bad),"duplicate hourly commitments rejected")
	bad=snapshot.duplicate(true)
	bad.next_id=4
	bad.loans=[{"id":1,"principal":2000,"daily_rate":0.005,"due":72},{"id":1,"principal":2000,"daily_rate":0.005,"due":72}]
	check(not Strategy.valid(bad),"duplicate loan identity rejected")
	var before: Dictionary=sim.snapshot()
	sim.strategy.report(sim)
	sim.strategy.rates(sim)
	sim.strategy.regional_auction(sim)
	check(sim.snapshot()==before,"all strategy queries leave live world unchanged")
	sim.start_campaign(1)
	check(not sim.strategy.enable(sim).ok,"historic teaching retains configured mechanics")

func _test_loans_and_policy() -> void:
	var sim=blank()
	sim.strategy.enable(sim)
	var starting: float=sim.cash
	var loan: Dictionary=sim.strategy.take_loan(sim,24000,24)
	check(loan.ok and near(sim.cash,starting+24000),"borrowing credits actual principal once")
	check(near(sim.strategy.rates(sim).interest_cost,5),"loan pays explicit daily0.5percent rate")
	var cash_before: float=sim.cash
	sim.strategy.settle(sim,1)
	check(near(sim.cash,cash_before) and near(sim.strategy.state.interest_paid,5),"settle records already-accounted interest without double charging")
	sim.elapsed_hours=25
	check(near(sim.strategy.rates(sim).interest_cost,10),"past-due debt has explicit doubled interest")
	check(sim.strategy.repay_loan(sim,int(loan.id),4000).ok,"partial principal repayment available")
	check(near(sim.strategy.report(sim).debt,20000) and near(sim.cash,cash_before-4000),"repayment decreases cash and debt consistently")
	var policy_before: Dictionary=sim.strategy.state.policy.duplicate(true)
	check(not sim.strategy.configure_policy(sim,{"carbon_price":20,"tariff_cap":-5}).ok and sim.strategy.state.policy==policy_before,"invalid policy edits are atomic")
	check(sim.strategy.configure_policy(sim,{"carbon_price":30,"production_subsidy":15,"tariff_cap":120,"reliability_penalty":25}).ok,"scenario policy applies valid fields")
	sim.totals={"carbon":2.0,"renewable_output":3.0,"demand":10.0,"served":8.0,"reliability":0.8}
	var rates: Dictionary=sim.strategy.rates(sim)
	check(near(rates.carbon_cost,60) and near(rates.subsidy_income,45) and near(rates.reliability_penalty,50),"policy rates follow actual emissions, renewable power and unserved load")
	check(near(sim.strategy.retail_cap(),120),"affordability ceiling is available to retail settlement")
	check(sim.strategy.set_goal(sim,"affordable").ok,"five-dimensional long term goal can be selected")

func _test_project_delivery_and_cancellation() -> void:
	var sim=blank()
	sim.strategy.enable(sim)
	var opening: float=sim.cash
	var result: Dictionary=sim.strategy.start_project(sim,"gas",Vector2i(4,4))
	check(result.ok and sim.buildings.is_empty(),"prepaid project does not supply power before completion")
	check(sim.strategy.cell_reserved(Vector2i(4,4)),"construction footprint is reserved")
	check(not sim.strategy.start_project(sim,"gas",Vector2i(4,4)).ok,"two projects cannot occupy one site")
	var paid: float=opening-sim.cash
	check(near(paid,38000*1.03),"site preparation enters upfront project cash cost")
	sim.strategy.advance(sim,0.5)
	check(sim.buildings.is_empty(),"construction lead time is real")
	var clone=Strategy.new()
	clone.restore(JSON.parse_string(JSON.stringify(sim.strategy.snapshot())))
	check(near(clone.state.projects[0].remaining,0.5),"unfinished construction round trips")
	var before_completion: float=sim.cash
	sim.strategy.advance(sim,0.5)
	check(sim.buildings.size()==1 and sim.get_building(1).kind=="gas","completed project creates actual electrical asset")
	check(near(sim.cash,before_completion),"commissioning never charges prepaid construction twice")
	check(near(sim.get_building(1).refund_basis,paid),"asset carries real invested capital into later demolition")
	var cancelled: Dictionary=sim.strategy.start_project(sim,"substation",Vector2i(6,4))
	var cancellation_cash: float=sim.cash
	var cost: float=sim.strategy.state.projects[-1].cost
	check(sim.strategy.cancel_project(sim,int(cancelled.id)).ok and near(sim.cash,cancellation_cash+cost*0.8),"early cancellation refunds only unbuilt share at disclosed80percent")
	check(not sim.strategy.cell_reserved(Vector2i(6,4)),"cancelled site becomes available")
	sim._add_building("home",Vector2i(8,4))
	var line_project: Dictionary=sim.strategy.start_line_project(sim,1,2)
	check(line_project.ok and sim.lines.is_empty(),"line corridors also require construction time")
	sim.strategy.advance(sim,5)
	check(sim.lines.size()==1 and sim.lines[0].a==1 and sim.lines[0].b==2,"completed corridor creates real conductive branch")
	var line_count: int=sim.lines.size()
	sim.strategy.advance(sim,5)
	check(sim.lines.size()==line_count,"project completion is idempotent")

func _test_forward_delivery() -> void:
	var sim=blank()
	sim._add_building("intertie",Vector2i(4,4))
	sim._add_building("factory",Vector2i(6,4))
	sim._add_line(1,2)
	sim._refresh()
	sim.strategy.enable(sim)
	check(sim.strategy.submit_day_ahead(sim,[5.0]).ok,"hourly physical schedule accepted against built intertie")
	check(not sim.strategy.submit_day_ahead(sim,[3.0]).ok,"accepted hour cannot be overwritten")
	check(near(sim.strategy.committed_mw(sim),0),"new plan starts next full hour")
	sim.step(1.25)
	check(near(sim._day_ahead_delivered,5),"scheduled imports delivered through actual intertie")
	check(near(sim.totals.import_mw,sim.totals.served),"scheduled energy never creates additional physical supply")
	check(float(sim.strategy.state.forward_cost)>0,"forward commitment is actually settled")
	check(float(sim.totals.get("day_ahead_cost",0))>0,"live expense report includes commitment cost")
	var live: Dictionary=sim.snapshot()
	sim.strategy.rates(sim)
	sim._refresh()
	check(sim.snapshot()==live,"repeated quote refresh cannot bill forward energy")
	sim.lines[0].closed=false
	sim._refresh()
	check(near(sim.totals.import_mw,0) and near(sim._day_ahead_delivered,0),"disconnected forward contract cannot deliver to islanded load")
	check(sim.strategy.rates(sim).day_ahead_cost>0 and sim.strategy.rates(sim).imbalance_cost>0,"undeliverable take-or-pay commitment remains a paid risk, never a windfall")

func _test_auction_reserves_and_hazards() -> void:
	var sim=blank()
	sim.strategy.enable(sim)
	var auction: Dictionary=sim.strategy.clear_auction([{"mw":10,"price":30},{"mw":20,"price":80}],15)
	check(auction.ok and near(auction.price,80) and near(auction.served,15),"marginal accepted block sets uniform clearing price")
	check(near(sim.strategy.clear_auction([{"mw":10,"price":30}],20).unserved,10),"scarcity is visible rather than inventing supply")
	check(sim.strategy.configure_market(sim,"auction").ok,"regional auction is an optional actual price source")
	check(near(sim.strategy.spot_price(sim,123),sim.strategy.regional_auction(sim).price),"auction controls wholesale quotation")
	sim._add_building("gas",Vector2i(4,4))
	sim._add_building("home",Vector2i(6,4))
	sim._add_line(1,2)
	sim._refresh()
	check(sim.strategy.reserve(sim,1,6,2).ok,"spare dispatchable capacity enters reserve service")
	check(near(sim.strategy.generation_limit(sim,sim.get_building(1),24),18),"reserve withholds exact MW from normal dispatch")
	check(not sim.strategy.reserve(sim,1,6,2).ok,"same unit cannot sell duplicate reserve")
	check(sim.strategy.rates(sim).reserve_income>0,"available standby capacity earns service revenue")
	var weak=blank()
	weak._add_building("gas",Vector2i(4,4))
	weak.get_building(1).health=5.0
	weak.strategy.enable(weak)
	weak._refresh()
	check(not weak.strategy.reserve(weak,1,22,2).ok,"health-derated capacity cannot be sold as nominal standby")
	sim.get_building(1).online=false
	check(near(sim.strategy.rates(sim).reserve_income,0) and sim.strategy.rates(sim).reserve_penalty>0,"failed standby cannot earn reserve revenue")
	sim.get_building(1).online=true
	check(sim.strategy.trigger_hazard(sim,"heatwave",Vector2i(6,4),3,2).ok,"spatial heatwave can be run as regional scenario")
	check(sim.strategy.demand_factor(sim,sim.get_building(2))>1 and sim.strategy.available_factor(sim,sim.get_building(1))<1,"one heatwave correlates demand and thermal derating")
	check(sim.strategy.trigger_hazard(sim,"fuel",Vector2i(4,4),2,2).ok,"fuel supply interruption supported")
	check(sim.strategy.available_factor(sim,sim.get_building(1))<0.3,"fuel scarcity constrains real generation availability")
	var snapshot: Dictionary=sim.strategy.snapshot()
	check(Strategy.valid(JSON.parse_string(JSON.stringify(snapshot))),"active reserves and hazards validate after JSON roundtrip")
	sim.strategy.advance(sim,2)
	check(near(sim.strategy.demand_factor(sim,sim.get_building(2)),1) and near(sim.strategy.available_factor(sim,sim.get_building(1)),1),"regional operating restrictions expire on actual elapsed time")
	check(sim.strategy.trigger_hazard(sim,"flood",Vector2i(5,4),4,1).ok,"flood scenario starts")
	check(sim.lines[0].fault and not sim.lines[0].closed,"flood creates correlated persistent physical damage requiring repair")
	var cash_before: float=sim.cash
	sim.strategy.advance(sim,1)
	check(sim.lines[0].fault and near(sim.cash,cash_before),"weather ending neither repairs permanent damage nor bills query costs")
	var penalty: float=sim.strategy.demolition_penalty(1)
	check(penalty>0,"standby demolition liability can be previewed before confirmation")
	sim.buildings.erase(sim.get_building(1))
	sim.strategy.prune(sim)
	check(sim.strategy.state.reserves.is_empty() and near(sim.cash,cash_before-penalty),"demolished standby target settles liability and leaves no dangling save reference")

func _test_persistence_and_financial_reconciliation() -> void:
	var sim=blank()
	sim._add_building("intertie",Vector2i(4,4))
	sim._add_building("factory",Vector2i(6,4))
	sim._add_line(1,2)
	sim._refresh()
	sim.strategy.enable(sim)
	sim.strategy.take_loan(sim,24000,72)
	sim.strategy.start_project(sim,"substation",Vector2i(8,8))
	sim.strategy.submit_day_ahead(sim,[5.0,7.0])
	sim.strategy.configure_policy(sim,{"carbon_price":10,"production_subsidy":5,"tariff_cap":130})
	sim.strategy.trigger_hazard(sim,"heatwave",Vector2i(6,4),3,2)
	sim.step(0.25)
	var path: String="user://test_strategy_persistence.json"
	check(sim.save_game(path).ok,"full advanced strategy snapshot passes simulation save validation")
	var clone=Sim.new()
	check(clone.load_game(path).ok,"full advanced strategy snapshot restores through real loader")
	check(near(clone.cash,sim.cash) and clone.strategy.snapshot()==sim.strategy.snapshot(),"investment, debt, policy and remaining scenario survive persistence")
	var before: float=sim.cash
	var ledger_before: float=0
	for row in sim.market.ledger: ledger_before+=float(row.net)
	var duration:=0.75
	sim.step(duration)
	clone.step(duration)
	check(near(sim.cash,clone.cash) and sim.strategy.snapshot()==clone.strategy.snapshot(),"restored projects and settlement evolve deterministically")
	var ledger_after: float=0
	for row in sim.market.ledger: ledger_after+=float(row.net)
	check(near(sim.cash-before,ledger_after-ledger_before),"market ledger net includes policy and finance exactly once")
	check(near(sim.strategy.state.interest_paid,5.0),"one hour accrues exactly one hour of interest")
	check(sim.get_building(3).is_empty(),"two hour engineering project stays uncommissioned after one hour")
	var dirty: Dictionary=sim.snapshot()
	dirty.strategy.day_ahead[0].mw=-1
	var dirty_path: String="user://test_strategy_invalid.json"
	var file=FileAccess.open(dirty_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(dirty))
	file.close()
	var live: Dictionary=clone.snapshot()
	check(not clone.load_game(dirty_path).ok and clone.snapshot()==live,"invalid forward data cannot partially replace a live session")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dirty_path))
