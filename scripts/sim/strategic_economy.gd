extends RefCounted
## Compressed investment, physical forward purchases and regional policy.
## Quotes and rates are pure. Only actions, advance and settle change state.

const DEFAULT_POLICY := {"carbon_price":0.0,"production_subsidy":0.0,"tariff_cap":500.0,"reliability_target":0.98,"reliability_penalty":0.0}
const PROJECT_HOURS := {"substation":2.0,"gas":1.0,"coal":4.0,"ccgt":3.0,"nuclear":8.0,"fusion":12.0,"hydro":4.0,"pumped_storage":4.0,"hvdc":4.0,"battery":0.75}
const FUEL_KINDS := ["gas","ccgt","coal","steam","dc_dynamo"]
var state: Dictionary = {}
var enabled: bool:
	get: return bool(state.get("enabled",false))
	set(value): state.enabled=value

func _init() -> void:
	reset()

func reset() -> void:
	state={"enabled":false,"next_id":1,"projects":[],"loans":[],"day_ahead":[],"reserves":[],"hazards":[],"policy":DEFAULT_POLICY.duplicate(true),
		"market_mode":"reference","bid_markup":1.0,"interest_paid":0.0,"forward_cost":0.0,"imbalance_cost":0.0,"reserve_revenue":0.0,
		"policy_cost":0.0,"policy_income":0.0,"goal":"","goal_hours":0.0,"completed_goals":[]}

func enable(sim: RefCounted) -> Dictionary:
	if sim.campaign.active: return _result(false,"历史关卡按教学规则运行，请在现代经营中投运长期经营。")
	state.enabled=true
	return _result(true,"长期经营已投运：工程工期、日前履约、融资与区域政策可以分别配置。")

func _allowed(sim: RefCounted) -> bool:
	return bool(state.enabled) and not bool(sim.campaign.active)

func start_project(sim: RefCounted, kind: String, cell: Vector2i) -> Dictionary:
	if not _allowed(sim): return _result(false,"请先投运长期经营。")
	_compact_projects()
	if state.projects.size()>=128: return _result(false,"工程队列已满。")
	for p in state.projects:
		if p.status=="building" and p.type=="facility" and int(p.x)==cell.x and int(p.y)==cell.y: return _result(false,"此地块已为工程预留。")
	var preview: Dictionary=sim.preview_build(kind,cell)
	if not preview.ok: return preview
	var site_factor:=1.08 if cell.x>=18 or cell.y>=18 else 1.03
	var cost:=snappedf(float(preview.get("base_cost",preview.cost))*site_factor,0.01)
	if sim.cash<cost: return _result(false,"资金不足，工程报价包含场地与接入准备费用。")
	var hours:=float(PROJECT_HOURS.get(kind,0.5))
	var id:=_next_id()
	state.projects.append({"id":id,"type":"facility","kind":kind,"x":cell.x,"y":cell.y,"a":-1,"b":-1,"cost":cost,"duration":hours,"remaining":hours,"status":"building","completed_id":-1})
	_pay(sim,-cost,"construction","%s工程预付款（含场地）" % sim.catalog[kind].name)
	return _result(true,"工程已开工，地块预留；%.1f小时后投运。" % hours,id)

func start_line_project(sim: RefCounted, a: int, b: int) -> Dictionary:
	if not _allowed(sim): return _result(false,"请先投运长期经营。")
	_compact_projects()
	if state.projects.size()>=128: return _result(false,"工程队列已满。")
	for p in state.projects:
		if p.status=="building" and p.type=="line" and ((int(p.a)==a and int(p.b)==b) or (int(p.a)==b and int(p.b)==a)): return _result(false,"相同走廊已有在建工程。")
	var preview: Dictionary=sim.preview_connection(a,b)
	if not preview.ok: return preview
	var cost:=snappedf(float(preview.get("base_cost",preview.cost))*1.12,0.01)
	if sim.cash<cost: return _result(false,"资金不足，线路工程还需走廊准备费用。")
	var hours:=0.5+float(preview.distance)*0.08
	var id:=_next_id()
	state.projects.append({"id":id,"type":"line","kind":"line","x":0,"y":0,"a":a,"b":b,"cost":cost,"duration":hours,"remaining":hours,"status":"building","completed_id":-1})
	_pay(sim,-cost,"construction","骨干线路工程预付款")
	return _result(true,"线路工程已开工，预计%.1f小时完成。" % hours,id)

func cell_reserved(cell: Vector2i) -> bool:
	for p in state.projects:
		if p.status=="building" and p.type=="facility" and int(p.x)==cell.x and int(p.y)==cell.y: return true
	return false

func demolition_penalty(building_id: int) -> float:
	var penalty:=0.0
	for r in state.reserves:
		if int(r.target)==building_id: penalty+=float(r.mw)*float(r.remaining)*float(r.price)*2.0
	return penalty

func prune(sim: RefCounted) -> void:
	for r in state.reserves.duplicate():
		if sim.get_building(int(r.target)).is_empty():
			_pay(sim,-float(r.mw)*float(r.remaining)*float(r.price)*2.0,"reserve_default","拆除备用提供方，结清剩余履约责任")
			state.reserves.erase(r)
	for p in state.projects:
		if p.status=="building" and p.type=="line" and (sim.get_building(int(p.a)).is_empty() or sim.get_building(int(p.b)).is_empty()):
			p.status="blocked"
			p.remaining=0.0
	for h in state.hazards:
		for id in h.affected_buildings.duplicate():
			if sim.get_building(int(id)).is_empty(): h.affected_buildings.erase(id)

func cancel_project(sim: RefCounted, id: int) -> Dictionary:
	for p in state.projects:
		if int(p.id)!=id or p.status not in ["building","blocked"]: continue
		var blocked: bool=p.status=="blocked"
		var remaining_fraction:=float(p.remaining)/float(p.duration)
		var refund:=float(p.cost)*(0.35 if blocked else remaining_fraction*0.8)
		p.status="cancelled"
		p.remaining=0.0
		_pay(sim,refund,"refund","取消工程，退回未施工部分的80%")
		return _result(true,"受阻工程撤销，按35%%回收¥%.0f。" % refund if blocked else "工程取消，退回¥%.0f；已施工及准备费用不退。" % refund,id)
	return _result(false,"没有此在建工程。")

func take_loan(sim: RefCounted, amount: float, hours: float=72.0) -> Dictionary:
	if not _allowed(sim): return _result(false,"请先投运长期经营。")
	if not _number(amount,1000,500000) or not _number(hours,24,720): return _result(false,"贷款为¥1,000—500,000，期限24—720小时。")
	var debt:=0.0
	for loan in state.loans: debt+=float(loan.principal)
	if debt+amount>1000000.0 or state.loans.size()>=16: return _result(false,"总授信额度为¥1,000,000。")
	var id:=_next_id()
	state.loans.append({"id":id,"principal":amount,"daily_rate":0.005,"due":float(sim.elapsed_hours)+hours})
	_pay(sim,amount,"loan","工程贷款本金，日利率0.5%，逾期翻倍")
	return _result(true,"贷款到账¥%.0f；%.0f小时后到期，可提前偿还。" % [amount,hours],id)

func repay_loan(sim: RefCounted, id: int, amount: float) -> Dictionary:
	if not _number(amount,0.01,1000000): return _result(false,"无效还款金额。")
	for loan in state.loans:
		if int(loan.id)!=id: continue
		var payment:=minf(float(loan.principal),amount)
		if sim.cash<payment: return _result(false,"资金不足。")
		loan.principal=maxf(0,float(loan.principal)-payment)
		_pay(sim,-payment,"repayment","偿还贷款本金")
		if float(loan.principal)<=0.000001: state.loans.erase(loan)
		return _result(true,"已还本金¥%.0f。" % payment,id)
	return _result(false,"贷款不存在。")

func submit_day_ahead(sim: RefCounted, schedule: Array) -> Dictionary:
	if not _allowed(sim): return _result(false,"请先投运长期经营。")
	if schedule.is_empty() or schedule.size()>24: return _result(false,"提交1—24个逐小时实物购电承诺。")
	var start_hour:=floorf(float(sim.elapsed_hours))+1.0
	var capacity:=0.0
	for b in sim.buildings:
		if b.online and sim.evolution.is_terminal(str(b.kind)): capacity+=float(b.capacity)
	if capacity<=0: return _result(false,"需要已建设的市场联络容量。")
	var rows: Array=[]
	for i in schedule.size():
		if not _number(schedule[i],0,capacity): return _result(false,"每小时购电承诺不能超过已建联络容量。")
		var start:=start_hour+float(i)
		for row in state.day_ahead:
			if absf(float(row.start)-start)<0.000001: return _result(false,"该小时已有生效承诺，不能覆盖或取消。")
		var clock:=float(sim.time_hours)+start-float(sim.elapsed_hours)
		var target_day:=int(sim.day)+int(floorf(clock/24.0))
		var quote:=float(sim.market.quote_for(target_day,fposmod(clock,24),sim.weather,1.0))
		rows.append({"start":start,"mw":float(schedule[i]),"price":quote})
	if state.day_ahead.size()+rows.size()>240: return _result(false,"未完成的日前计划过多。")
	state.day_ahead.append_array(rows)
	return _result(true,"日前实物计划已承诺；未交付电量仍付费，实时偏差另计5%履约费。")

func committed_mw(sim: RefCounted) -> float:
	if not _allowed(sim): return 0.0
	var t:=_settlement_time(sim)
	for row in state.day_ahead:
		if t>=float(row.start)-0.0000001 and t<float(row.start)+1.0-0.0000001: return float(row.mw)
	return 0.0

func reserve(sim: RefCounted, building_id: int, mw: float, hours: float=4.0) -> Dictionary:
	if not _allowed(sim): return _result(false,"请先投运长期经营。")
	if not _number(mw,0.1,1000) or not _number(hours,0.25,24): return _result(false,"备用数量或期限无效。")
	var b: Dictionary=sim.get_building(building_id)
	if b.is_empty() or not b.online or not b.get("enabled",true): return _result(false,"备用提供方需要在线。")
	if not sim.evolution.is_generator(str(b.kind)) and not sim.evolution.is_storage(str(b.kind)): return _result(false,"备用由可调度机组或储能提供。")
	if float(b.get("startup_remaining",0))>0.000001: return _result(false,"启动中的机组不能提供备用。")
	for r in state.reserves:
		if int(r.target)==building_id: return _result(false,"此设备已有备用承诺。")
	var free_power:=maxf(0,float(b.capacity)-maxf(0,float(b.output)))
	if sim.evolution.is_generator(str(b.kind)): free_power=maxf(0,float(b.get("reserve_available_mw",b.available))-maxf(0,float(b.output)))
	if free_power+0.000001<mw: return _result(false,"闲置可用功率不足，不能重复出售运行容量。")
	if sim.evolution.is_storage(str(b.kind)) and float(b.energy)*sim.evolution.storage_efficiency(b)<mw*hours: return _result(false,"储能电量不足以覆盖备用期限。")
	state.reserves.append({"id":_next_id(),"target":building_id,"mw":mw,"remaining":hours,"price":18.0})
	return _result(true,"已承诺%.1fMW备用，功率将保留，履约获得¥18/MW·h。" % mw)

func reserved_mw(building_id: int) -> float:
	if not bool(state.enabled): return 0.0
	for r in state.reserves:
		if int(r.target)==building_id and float(r.remaining)>0: return float(r.mw)
	return 0.0

func configure_policy(sim: RefCounted, settings: Dictionary) -> Dictionary:
	if not _allowed(sim): return _result(false,"请先投运长期经营。")
	var candidate: Dictionary=state.policy.duplicate(true)
	var bounds: Dictionary={"carbon_price":[0.0,1000.0],"production_subsidy":[0.0,500.0],"tariff_cap":[20.0,500.0],"reliability_target":[0.5,1.0],"reliability_penalty":[0.0,500.0]}
	for key in settings:
		if not bounds.has(key) or not _number(settings[key],float(bounds[key][0]),float(bounds[key][1])): return _result(false,"政策字段或范围无效。")
		candidate[key]=float(settings[key])
	state.policy=candidate
	return _result(true,"情景政策已应用，后续实际结算生效。")

func retail_cap() -> float:
	return float(state.policy.tariff_cap) if state.enabled else 500.0

func configure_market(sim: RefCounted, mode: String, bid_markup: float=1.0) -> Dictionary:
	if not _allowed(sim): return _result(false,"请先投运长期经营。")
	if mode not in ["reference","auction"] or not _number(bid_markup,0.5,2.0): return _result(false,"无效市场设置。")
	state.market_mode=mode
	state.bid_markup=bid_markup
	return _result(true,"区域市场采用%s。" % ("统一价格出清" if mode=="auction" else "参考价格"))

func clear_auction(offers: Array, demand: float) -> Dictionary:
	if not _number(demand,0,1000000) or offers.size()>128: return {"ok":false,"price":0.0,"served":0.0,"unserved":0.0,"allocations":[]}
	var sorted: Array=[]
	for offer in offers:
		if not offer is Dictionary or not _number(offer.get("mw"),0,1000000) or not _number(offer.get("price"),0,10000): return {"ok":false,"price":0.0,"served":0.0,"unserved":0.0,"allocations":[]}
		sorted.append(offer.duplicate(true))
	sorted.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.price)<float(b.price))
	var remaining:=demand
	var price:=0.0
	var allocations: Array=[]
	for offer in sorted:
		var accepted:=minf(remaining,float(offer.mw))
		if accepted>0:
			price=float(offer.price)
			allocations.append({"name":str(offer.get("name","区域供应方")),"mw":accepted,"price":float(offer.price)})
		remaining-=accepted
		if remaining<=0.000001: break
	if remaining>0.000001: price=500.0
	return {"ok":true,"price":price,"served":demand-remaining,"unserved":remaining,"allocations":allocations}

func regional_auction(sim: RefCounted) -> Dictionary:
	var clock: float=float(sim._pricing_hour) if float(sim._pricing_hour)>=0 else float(sim.time_hours)
	var sun:=maxf(0.0,sin((clock-6.0)*PI/12.0))*(.34 if sim.storm_active else (.60 if sim.weather=="多云" else 1.0))
	return auction_at(clock,sun,0.5 if _hazard_kind("fuel") else 1.0)

func auction_at(clock: float, sun: float, fuel_factor: float=1.0) -> Dictionary:
	var demand:=72.0+(38.0 if clock>=17 and clock<21 else 0.0)
	var mark:=float(state.bid_markup)
	return clear_auction([{"name":"区域风光","mw":20.0+sun*28.0,"price":24.0*mark},{"name":"区域基荷","mw":42.0*fuel_factor,"price":72.0*mark},{"name":"快速调峰","mw":60.0*fuel_factor,"price":180.0*mark}],demand)

func forecast_prices(sim: RefCounted, points: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for offset in points.size():
		var row: Dictionary=points[offset].duplicate(true)
		row.retail=minf(float(row.retail),retail_cap())
		if _allowed(sim) and state.market_mode=="auction":
			var expected_weather: String=sim.weather if offset<3 or sim.weather!="风暴" else "多云"
			var sun:=maxf(0.0,sin((float(row.hour)-6.0)*PI/12.0))*(.34 if expected_weather=="风暴" else (.60 if expected_weather=="多云" else 1.0))
			var fuel_factor:=1.0
			for h in state.hazards:
				if h.kind=="fuel" and float(h.remaining)>float(offset): fuel_factor=.5
			row.spot=float(auction_at(float(row.hour),sun,fuel_factor).price)
		result.append(row)
	return result

func spot_price(sim: RefCounted, fallback: float) -> float:
	return float(regional_auction(sim).price) if _allowed(sim) and state.market_mode=="auction" else fallback

func trigger_hazard(sim: RefCounted, kind: String, center: Vector2i=Vector2i(8,8), radius: float=6.0, hours: float=4.0) -> Dictionary:
	if not _allowed(sim): return _result(false,"请先投运长期经营。")
	if kind not in ["heatwave","flood","fuel"] or center.x<0 or center.y<0 or center.x>47 or center.y>47 or not _number(radius,1,48) or not _number(hours,0.25,48): return _result(false,"无效灾害情景。")
	if state.hazards.size()>=4: return _result(false,"同时运行的区域灾害已达上限。")
	var h: Dictionary={"id":_next_id(),"kind":kind,"x":center.x,"y":center.y,"radius":radius,"duration":hours,"remaining":hours,"affected_buildings":[]}
	if kind=="flood":
		for b in sim.buildings:
			if b.kind=="substation" and b.online and Vector2(b.cell).distance_to(Vector2(center))<=radius:
				b.online=false
				b.health=minf(float(b.health),65)
				h.affected_buildings.append(int(b.id))
		for line in sim.lines:
			var a: Dictionary=sim.get_building(int(line.a))
			var b: Dictionary=sim.get_building(int(line.b))
			if a.is_empty() or b.is_empty(): continue
			var midpoint: Vector2=(Vector2(a.cell)+Vector2(b.cell))*0.5
			if midpoint.distance_to(Vector2(center))<=radius:
				line.closed=false
				line.fault=true
				line.health=minf(float(line.health),40)
				line.trip_reason="洪水损坏"
	state.hazards.append(h)
	if sim.has_method("_log"): sim._log("区域%s预警已生效，持续%.1f小时；检查负荷、配套与备用路径。" % [_hazard_name(kind),hours],"warning")
	return _result(true,"%s情景已开始，区域相关影响会进入实际运行。" % _hazard_name(kind),int(h.id))

func demand_factor(sim: RefCounted, b: Dictionary) -> float:
	if not _allowed(sim): return 1.0
	var factor:=1.0
	for h in state.hazards:
		if h.kind=="heatwave" and _inside(b,h):
			factor*=1.22 if b.kind in ["home","hospital"] else (1.12 if b.kind in ["factory","cooling"] else 1.0)
	return factor

func available_factor(sim: RefCounted, b: Dictionary) -> float:
	if not _allowed(sim): return 1.0
	var factor:=1.0
	for h in state.hazards:
		if not _inside(b,h): continue
		if h.kind=="fuel" and b.kind in FUEL_KINDS: factor*=0.25
		if h.kind=="heatwave" and b.kind in ["gas","ccgt","coal","nuclear","fusion"]: factor*=0.85
	return factor

func generation_limit(sim: RefCounted, b: Dictionary, available: float) -> float:
	return maxf(0,available*available_factor(sim,b)-reserved_mw(int(b.id))) if _allowed(sim) else available

func rates(sim: RefCounted) -> Dictionary:
	var result: Dictionary={"income":0.0,"expenses":0.0,"day_ahead_cost":0.0,"imbalance_cost":0.0,"carbon_cost":0.0,"subsidy_income":0.0,"reserve_income":0.0,"reserve_penalty":0.0,"interest_cost":0.0,"reliability_penalty":0.0}
	if not _allowed(sim): return result
	var t:=_settlement_time(sim)
	var spot:=float(sim.market.state.spot_price)
	for row in state.day_ahead:
		if t>=float(row.start)-0.0000001 and t<float(row.start)+1.0-0.0000001:
			result.day_ahead_cost=float(row.mw)*float(row.price)
			var actual:=maxf(0,float(sim.totals.get("import_mw",0))-float(sim.totals.get("contract_import_mw",0)))
			result.imbalance_cost=absf(actual-float(row.mw))*spot*0.05
			break
	for loan in state.loans:
		var late:=2.0 if t>=float(loan.due) else 1.0
		result.interest_cost+=float(loan.principal)*float(loan.daily_rate)/24.0*late
	for r in state.reserves:
		var b: Dictionary=sim.get_building(int(r.target))
		var available:=0.0
		if not b.is_empty() and b.online and b.get("enabled",true) and float(b.get("startup_remaining",0))<=0.000001:
			var potential:=float(b.capacity)*available_factor(sim,b)
			if sim.evolution.is_generator(str(b.kind)): potential=minf(potential,float(b.get("reserve_available_mw",float(b.available)+float(r.mw))))
			available=maxf(0,potential-maxf(0,float(b.output)))
			if sim.evolution.is_storage(str(b.kind)): available=minf(available,float(b.energy)*sim.evolution.storage_efficiency(b)/maxf(0.05,float(r.remaining)))
		var fulfilled:=minf(float(r.mw),available)
		result.reserve_income+=fulfilled*float(r.price)
		result.reserve_penalty+=(float(r.mw)-fulfilled)*float(r.price)*2.0
	result.carbon_cost=maxf(0,float(sim.totals.get("carbon",0)))*float(state.policy.carbon_price)
	result.subsidy_income=maxf(0,float(sim.totals.get("renewable_output",0)))*float(state.policy.production_subsidy)
	if float(sim.totals.get("reliability",1))<float(state.policy.reliability_target): result.reliability_penalty=maxf(0,float(sim.totals.get("demand",0))-float(sim.totals.get("served",0)))*float(state.policy.reliability_penalty)
	result.income=float(result.subsidy_income)+float(result.reserve_income)
	result.expenses=float(result.day_ahead_cost)+float(result.imbalance_cost)+float(result.carbon_cost)+float(result.reserve_penalty)+float(result.interest_cost)+float(result.reliability_penalty)
	return result

func advance(sim: RefCounted, dt: float) -> void:
	if not _allowed(sim) or dt<=0: return
	for p in state.projects:
		if p.status!="building": continue
		p.remaining=maxf(0,float(p.remaining)-dt)
		if float(p.remaining)>0.000001: continue
		if p.type=="facility":
			var cell:=Vector2i(int(p.x),int(p.y))
			if not sim.building_at(cell).is_empty() or sim.buildings.size()>=512:
				p.status="blocked"
				continue
			var b: Dictionary=sim._add_building(str(p.kind),cell,{"invested_capital":float(p.cost),"refund_basis":float(p.cost)})
			p.completed_id=int(b.id)
			sim.construction_count+=1
		else:
			var a: Dictionary=sim.get_building(int(p.a))
			var b: Dictionary=sim.get_building(int(p.b))
			var duplicate:=false
			for line in sim.lines:
				if (int(line.a)==int(p.a) and int(line.b)==int(p.b)) or (int(line.a)==int(p.b) and int(line.b)==int(p.a)): duplicate=true
			if a.is_empty() or b.is_empty() or duplicate or sim.lines.size()>=2000:
				p.status="blocked"
				continue
			p.completed_id=int(sim._add_line(int(p.a),int(p.b)).id)
		p.status="completed"
		if sim.has_method("_log"): sim._log("长期工程 #%d 已投运。" % int(p.id),"success")
	for h in state.hazards.duplicate():
		h.remaining=maxf(0,float(h.remaining)-dt)
		if float(h.remaining)>0.000001: continue
		for id in h.affected_buildings:
			var b: Dictionary=sim.get_building(int(id))
			if not b.is_empty() and float(b.repair_remaining)<=0: b.online=true
		state.hazards.erase(h)

func settle(sim: RefCounted, dt: float) -> void:
	if not _allowed(sim) or dt<=0: return
	var paid: Dictionary=rates(sim)
	state.interest_paid+=float(paid.interest_cost)*dt
	state.forward_cost+=float(paid.day_ahead_cost)*dt
	state.imbalance_cost+=float(paid.imbalance_cost)*dt
	state.reserve_revenue+=float(paid.reserve_income)*dt
	state.policy_cost+=(float(paid.carbon_cost)+float(paid.reliability_penalty))*dt
	state.policy_income+=float(paid.subsidy_income)*dt
	for r in state.reserves.duplicate():
		r.remaining=maxf(0,float(r.remaining)-dt)
		if float(r.remaining)<=0.000001: state.reserves.erase(r)
	var cutoff:=float(sim.elapsed_hours)-24.0
	for row in state.day_ahead.duplicate():
		if float(row.start)+1.0<cutoff: state.day_ahead.erase(row)
	if not str(state.goal).is_empty():
		var reliable:=float(sim.totals.get("reliability",1))>=float(state.policy.reliability_target)
		var passed:=reliable
		match str(state.goal):
			"affordable": passed=passed and float(sim.market.state.retail_price)<=145.0
			"sustainable": passed=passed and float(sim.totals.get("renewable_supply_share",0))>=0.5
			"resilient": passed=passed and state.hazards.is_empty() and int(sim.storm_count)>0 and int(sim.restored_storms)>=int(sim.storm_count)
			"solvent": passed=passed and float(sim.cash)>=0 and float(sim.totals.get("income",0))>=float(sim.totals.get("expenses",0))
		state.goal_hours=float(state.goal_hours)+dt if passed else 0.0
		if float(state.goal_hours)>=24 and str(state.goal) not in state.completed_goals: state.completed_goals.append(str(state.goal))

func set_goal(sim: RefCounted, goal: String) -> Dictionary:
	if not _allowed(sim) or goal not in ["reliable","affordable","sustainable","resilient","solvent"]: return _result(false,"选择可靠、可负担、可持续、韧性或财务目标。")
	if str(state.goal)!=goal: state.goal_hours=0.0
	state.goal=goal
	return _result(true,"长期目标已选择，需要连续达标24游戏小时。")

func report(sim: RefCounted) -> Dictionary:
	var debt:=0.0
	for loan in state.loans: debt+=float(loan.principal)
	var critical_demand:=0.0
	var critical_served:=0.0
	for b in sim.buildings:
		if b.kind=="hospital":
			critical_demand+=float(b.demand)
			critical_served+=float(b.served)
	var result: Dictionary=state.duplicate(true)
	result.debt=debt
	result.rates=rates(sim)
	result.committed_mw=committed_mw(sim)
	result.metrics={"reliability":float(sim.totals.get("reliability_lifetime",1)),"affordability":minf(1.0,145.0/maxf(1,float(sim.market.state.retail_price))),"sustainability":float(sim.totals.get("renewable_supply_share",0)),"resilience":critical_served/critical_demand if critical_demand>0 else 1.0,"financial_cash":float(sim.cash),"debt":debt}
	result.auction=regional_auction(sim) if state.market_mode=="auction" else {}
	result.goal_complete=str(state.goal) in state.completed_goals
	return result

func clear_projection_hazards() -> void:
	# All model hazards are already public, active scenarios; no hidden future
	# incidents are stored here. Remove asset IDs, which are not forecast evidence.
	for h in state.hazards: h.affected_buildings=[]

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(data: Dictionary) -> void:
	reset()
	if not valid(data): return
	state.merge(data.duplicate(true),true)
	state.next_id=int(state.next_id)
	for p in state.projects:
		for key in ["id","x","y","a","b","completed_id"]: p[key]=int(p[key])
	for loan in state.loans: loan.id=int(loan.id)
	for r in state.reserves:
		r.id=int(r.id)
		r.target=int(r.target)
	for h in state.hazards:
		for key in ["id","x","y"]: h[key]=int(h[key])
		for i in h.affected_buildings.size(): h.affected_buildings[i]=int(h.affected_buildings[i])

static func valid(data: Dictionary) -> bool:
	if not data.get("enabled") is bool or not _integer(data.get("next_id"),1,100000000): return false
	for key in ["projects","loans","day_ahead","reserves","hazards","completed_goals"]:
		if not data.get(key) is Array: return false
	if data.projects.size()>128 or data.loans.size()>16 or data.day_ahead.size()>240 or data.reserves.size()>512 or data.hazards.size()>4 or data.completed_goals.size()>5: return false
	if not data.get("policy") is Dictionary: return false
	if not _number(data.policy.get("carbon_price"),0,1000) or not _number(data.policy.get("production_subsidy"),0,500) or not _number(data.policy.get("reliability_penalty"),0,500): return false
	if not _number(data.policy.get("tariff_cap"),20,500) or not _number(data.policy.get("reliability_target"),0.5,1): return false
	if data.get("market_mode") not in ["reference","auction"] or not _number(data.get("bid_markup"),0.5,2): return false
	if data.get("goal") not in ["","reliable","affordable","sustainable","resilient","solvent"] or not _number(data.get("goal_hours"),0,1000000): return false
	var completed: Dictionary={}
	for value in data.completed_goals:
		if value not in ["reliable","affordable","sustainable","resilient","solvent"] or completed.has(value): return false
		completed[value]=true
	for key in ["interest_paid","forward_cost","imbalance_cost","reserve_revenue","policy_cost","policy_income"]:
		if not _number(data.get(key),0,1e15): return false
	var ids: Dictionary={}
	for p in data.projects:
		if not p is Dictionary or not _id_valid(p,ids,data) or p.get("type") not in ["facility","line"] or p.get("status") not in ["building","completed","cancelled","blocked"] or not p.get("kind") is String: return false
		for key in ["x","y"]:
			if not _integer(p.get(key),0,47): return false
		for key in ["a","b","completed_id"]:
			if not _integer(p.get(key),-1,100000000): return false
		if not _number(p.get("cost"),0,1e12) or not _number(p.get("duration"),0.01,1000) or not _number(p.get("remaining"),0,float(p.duration)): return false
	for loan in data.loans:
		if not loan is Dictionary or not _id_valid(loan,ids,data) or not _number(loan.get("principal"),0.01,500000) or not _number(loan.get("daily_rate"),0,0.1) or not _number(loan.get("due"),0,1e9): return false
	var starts: Dictionary={}
	for row in data.day_ahead:
		if not row is Dictionary or not _integer(row.get("start"),0,1e9) or not _number(row.get("mw"),0,1e6) or not _number(row.get("price"),0,1e5): return false
		if starts.has(int(row.start)): return false
		starts[int(row.start)]=true
	var reserved_targets: Dictionary={}
	for r in data.reserves:
		if not r is Dictionary or not _id_valid(r,ids,data) or not _integer(r.get("target"),1,100000000) or not _number(r.get("mw"),0.1,1000) or not _number(r.get("remaining"),0.0000001,24) or not _number(r.get("price"),0,10000): return false
		if reserved_targets.has(int(r.target)): return false
		reserved_targets[int(r.target)]=true
	for h in data.hazards:
		if not h is Dictionary or not _id_valid(h,ids,data) or h.get("kind") not in ["heatwave","flood","fuel"] or not _integer(h.get("x"),0,47) or not _integer(h.get("y"),0,47) or not _number(h.get("radius"),1,48) or not _number(h.get("duration"),0.25,48) or not _number(h.get("remaining"),0.0000001,float(h.duration)): return false
		if not h.get("affected_buildings") is Array or h.affected_buildings.size()>512: return false
		for id in h.affected_buildings:
			if not _integer(id,1,100000000): return false
	return true

static func references_valid(data: Dictionary, building_ids: Dictionary, line_ids: Dictionary, catalog: Dictionary) -> bool:
	if not valid(data): return false
	for p in data.projects:
		if p.type=="facility" and not catalog.has(str(p.kind)): return false
		if p.type=="line" and p.status=="building" and (not building_ids.has(int(p.a)) or not building_ids.has(int(p.b))): return false
		if p.status=="completed" and int(p.completed_id)>0 and (not building_ids.has(int(p.completed_id)) if p.type=="facility" else not line_ids.has(int(p.completed_id))):
			# Completed infrastructure may subsequently be demolished.
			continue
	for r in data.reserves:
		if not building_ids.has(int(r.target)): return false
	for h in data.hazards:
		for id in h.affected_buildings:
			if not building_ids.has(int(id)): return false
	return true

func _settlement_time(sim: RefCounted) -> float:
	# _pricing_hour is the interval midpoint set by the simulation. Reconstruct
	# its absolute timestamp so midnight and hour boundaries do not double bill.
	if float(sim.get("_pricing_hour"))>=0.0:
		var midpoint:=float(sim.get("_pricing_hour"))
		var pricing_day:=int(sim.get("_pricing_day"))
		return float(sim.elapsed_hours)+(float(pricing_day)-float(sim.day))*24.0+midpoint-float(sim.time_hours)
	return float(sim.elapsed_hours)

func _inside(b: Dictionary, hazard: Dictionary) -> bool:
	return Vector2(b.cell).distance_to(Vector2(float(hazard.x),float(hazard.y)))<=float(hazard.radius)

func _hazard_kind(kind: String) -> bool:
	for h in state.hazards:
		if h.kind==kind: return true
	return false

func _hazard_name(kind: String) -> String:
	return {"heatwave":"热浪","flood":"洪水","fuel":"燃料供应中断"}.get(kind,kind)

func _next_id() -> int:
	var id:=int(state.next_id)
	state.next_id=id+1
	return id

func _compact_projects() -> void:
	# The cash journal retains investment history; keep recent finished jobs in
	# the workbench without imposing a lifetime cap on city construction.
	if state.projects.size()<96: return
	for project in state.projects.duplicate():
		if state.projects.size()<64: break
		if project.status in ["completed","cancelled"]: state.projects.erase(project)

static func _id_valid(item: Dictionary, ids: Dictionary, data: Dictionary) -> bool:
	if not _integer(item.get("id"),1,int(data.next_id)-1) or ids.has(int(item.id)): return false
	ids[int(item.id)]=true
	return true

func _pay(sim: RefCounted, amount: float, category: String, description: String) -> void:
	sim.record_cash_change(amount,category,description)

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value,float(minimum),float(maximum)) and floorf(float(value))==float(value)

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

func _result(ok: bool, message: String, id: int=-1) -> Dictionary:
	return {"ok":ok,"message":message,"id":id}
