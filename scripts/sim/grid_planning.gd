extends RefCounted
## Decision support sees the same evidence as the operator. Projections run in
## disposable worlds; only advance() records real interruptions and cash events.

var state: Dictionary = {}

func reset(opening_cash: float=180000.0) -> void:
	state={"opening_cash":opening_cash,"cash_balance":opening_cash,"cash_entries":[],"active_outages":{},"outages":[],"next_event":1,"operating_hours":0.0}

func record(sim: RefCounted, amount: float, category: String, description: String) -> void:
	if state.is_empty(): reset(float(sim.cash))
	var difference:=float(sim.cash)-float(state.cash_balance)
	if absf(difference)>0.00001:
		_append(float(sim.elapsed_hours),difference,"opening_adjustment","期初资金调整")
	_append(float(sim.elapsed_hours),amount,category,description)
	sim.cash+=amount

func _append(at: float, amount: float, category: String, description: String) -> void:
	state.cash_balance=float(state.cash_balance)+amount
	var entries: Array=state.cash_entries
	if category=="operations" and not entries.is_empty() and entries[-1].category==category and floorf(float(entries[-1].hour))==floorf(at):
		entries[-1].amount=float(entries[-1].amount)+amount
		entries[-1].balance=float(state.cash_balance)
	else:
		entries.append({"hour":at,"amount":amount,"category":category,"description":description,"balance":float(state.cash_balance)})
	while entries.size()>1000:
		var removed: Dictionary=entries.pop_front()
		state.opening_cash=float(state.opening_cash)+float(removed.amount)

func advance(sim: RefCounted, dt: float) -> void:
	if dt<=0.0: return
	state.operating_hours=float(state.operating_hours)+dt
	var active: Dictionary=state.active_outages
	var seen: Dictionary={}
	for b in sim.buildings:
		if float(b.demand)<=0.00001 or not sim.customer_service_active(int(b.id)): continue
		var key:=str(int(b.id))
		seen[key]=true
		var missing:=maxf(0.0,float(b.demand)-float(b.served))
		if missing>maxf(0.0001,float(b.demand)*0.02):
			if not active.has(key):
				active[key]={"id":int(state.next_event),"facility_id":int(b.id),"name":str(b.name),"city_id":int(b.get("city_id",-1)),"start":float(sim.elapsed_hours)-dt,"end":-1.0,"duration":0.0,"unserved_mwh":0.0,"cost":0.0,"critical":b.kind=="hospital","cause":"用户报告失供；原因待核实","curve":[]}
				state.next_event=int(state.next_event)+1
			var event: Dictionary=active[key]
			event.duration=float(event.duration)+dt
			event.unserved_mwh=float(event.unserved_mwh)+missing*dt
			event.cost=float(event.cost)+missing*dt*60.0
			var curve: Array=event.curve
			var row:={"hour":float(sim.elapsed_hours),"served_fraction":float(b.served)/maxf(0.00001,float(b.demand))}
			if not curve.is_empty() and floorf(float(curve[-1].hour)*4)==floorf(float(sim.elapsed_hours)*4): curve[-1]=row
			else: curve.append(row)
			while curve.size()>96: curve.pop_front()
			for l in sim.lines:
				if int(l.a)!=int(b.id) and int(l.b)!=int(b.id): continue
				var observed: Dictionary=sim.line_observation(int(l.id))
				if bool(observed.get("fault_known",false)) and bool(observed.get("fault",false)):
					event.cause="已核实相连线路故障；检查隔离与备用路径"
		elif active.has(key): _finish(key,float(sim.elapsed_hours))
	for key in active.keys():
		if not seen.has(key): _finish(str(key),float(sim.elapsed_hours))

func _finish(key: String, at: float) -> void:
	var event: Dictionary=state.active_outages[key]
	event.end=at
	event.curve.append({"hour":at,"served_fraction":1.0})
	state.outages.append(event)
	state.active_outages.erase(key)
	while state.outages.size()>200: state.outages.pop_front()

func report(sim: RefCounted) -> Dictionary:
	var events: Array=state.outages.duplicate(true)
	for event in state.active_outages.values(): events.append(event.duplicate(true))
	var lost:=0.0
	var critical_hours:=0.0
	var recovery_hours:=0.0
	var completed:=0
	for event in events:
		lost+=float(event.unserved_mwh)
		if event.critical: critical_hours+=float(event.duration)
		if float(event.end)>=0.0:
			recovery_hours+=float(event.duration)
			completed+=1
	var categories: Dictionary={}
	for entry in state.cash_entries: categories[entry.category]=float(categories.get(entry.category,0.0))+float(entry.amount)
	return {"events":events,"active":state.active_outages.size(),"unserved_mwh":lost,"critical_hours":critical_hours,"mean_recovery_hours":recovery_hours/float(completed) if completed>0 else 0.0,"cash_entries":state.cash_entries.duplicate(true),"cash_categories":categories,"opening_cash":state.opening_cash,"cash_balance":state.cash_balance,
		"dimensions":{"reliability":float(sim.totals.get("reliability_lifetime",1.0)),"affordability":float(sim.market.state.retail_price),"sustainability":float(sim.totals.get("renewable_supply_share",0.0)),"resilience":critical_hours,"finance":float(sim.cash)}}

func forecast(sim: RefCounted, settings: Dictionary={}, hours: int=24) -> Dictionary:
	if hours<1 or hours>24: return {"ok":false,"message":"预测范围为1—24小时。"}
	var projected: RefCounted=sim.get_script().new()
	projected._is_projection=true
	var restored: Dictionary=projected.restore_snapshot(sim.snapshot())
	if not restored.ok: return {"ok":false,"message":"当前状态无法建立推演副本。"}
	var assumptions: Array[String]=["按15分钟步长推演当前运行方案，工程损耗采用参考近似。采用当前电价规则、公开城市需求与典型天气；未预知的灾害、网络事件和随机故障不作精确预报。"]
	if projected.active_repairs()>0 or not projected.lifecycle.jobs.is_empty() or not projected.digital.pending_commands.is_empty():
		assumptions.append("已受理的在途指令和工单继续按原队列执行，完成时可能覆盖本次假设设点；比较不会撤销这些操作。")
	var unknown:=0
	for b in projected.buildings:
		var observed: Dictionary=sim.facility_observation(int(b.id))
		if not bool(observed.get("trusted",false)):
			unknown+=1
			b.health=100.0
			b.online=true
			b.repair_remaining=0.0
			b.lifecycle_busy=false
			b.lifecycle_failure=false
			if projected.evolution.is_storage(str(b.kind)):
				b.energy_capacity=float(b.get("nominal_energy_capacity",b.energy_capacity))
				b.soh=100.0
				b.energy=float(b.energy_capacity)*0.5
				b.renewable_energy_mwh=0.0
			b.ramp_mw=0.0
			b.startup_remaining=float(projected.evolution.STARTUP.get(str(b.kind),0.0))
		else:
			b.health=float(observed.health)
			b.online=bool(observed.online) if observed.get("online")!=null else true
			if projected.evolution.is_storage(str(b.kind)):
				b.energy=float(observed.energy)
				b.soh=float(observed.soh) if observed.get("soh")!=null else 100.0
				b.energy_capacity=float(b.get("nominal_energy_capacity",b.energy_capacity))*float(b.soh)/100.0
			b.ramp_mw=maxf(0.0,float(observed.ramp_mw)) if observed.get("ramp_mw")!=null else maxf(0.0,float(observed.output))
			b.startup_remaining=float(observed.startup_remaining) if observed.get("startup_remaining")!=null else float(projected.evolution.STARTUP.get(str(b.kind),0.0))
		# The internal cause flag is never telemetry. Observed online/health state
		# already carries the visible operational constraint.
		b.lifecycle_failure=false
	for l in projected.lines:
		var observed: Dictionary=sim.line_observation(int(l.id))
		if str(observed.get("visibility","unknown")) not in ["verified","patrol"]:
			l.closed=true
			l.fault=false
			l.repair_remaining=0.0
			l.lifecycle_busy=false
			l.lifecycle_failure=false
			l.heat=0.0
			l.health=100.0
			l.trip_reason=""
		else:
			l.closed=bool(observed.closed)
			l.fault=bool(observed.get("fault",false))
			l.health=float(observed.health)
			l.heat=float(observed.heat)
		l.lifecycle_failure=false
	var meter_unknown:=0
	var customer_report: Dictionary=sim.customers.report(sim)
	for display in customer_report.customers:
		var row: Dictionary=projected.customers.devices[str(int(display.id))]
		if display.telemetry_visibility=="verified":
			for key in ["energy_mwh","ev_remaining_mwh","shift_debt_mwh","fatigue"]: row[key]=float(display[key])
		else:
			meter_unknown+=1
			row.energy_mwh=float(row.battery_mwh)*.5
			row.ev_remaining_mwh=float(row.ev_target_mwh)
			row.shift_debt_mwh=0.0
			row.fatigue=0.0
	if meter_unknown>0: assumptions.append("%d个缺少新鲜电表读数的街区按用户侧储能半电量、声明的充电需求及零待回补量估算。" % meter_unknown)
	for job in projected.lifecycle.jobs:
		if job.target_type=="line":
			var target: Dictionary=projected.get_line(int(job.target_id))
			job.original_closed=bool(target.get("closed",true))
		else:
			job.original_online=bool(projected.get_building(int(job.target_id)).get("online",true))
	projected.rng.seed=42
	projected.next_storm_at=1e12
	projected.storm_active=false
	projected.storm_remaining=0.0
	projected.campaign.active=false
	projected.management.state.active=false
	projected.digital.next_attack_at=1e12
	projected.digital.incidents.clear()
	for key in projected.digital.devices:
		var device: Dictionary=projected.digital.devices[key]
		device.compromised=false
		device.intrusion=false
		device.dos_remaining=0.0
		device.spoof_remaining=0.0
	projected.strategy.clear_projection_hazards()
	if unknown>0: assumptions.append("%d座缺少可信读数的设施按健康可用估算；未知储能按半电量、未知线路按健康闭合估算。" % unknown)
	if settings.has("generator_id"):
		var target: Dictionary=projected.get_building(int(settings.generator_id))
		if target.is_empty() or not projected.evolution.is_generator(str(target.kind)): return {"ok":false,"message":"请选择可调度机组。"}
		if not _number(settings.get("dispatch",1.0),0,1): return {"ok":false,"message":"出力比例无效。"}
		target.dispatch=float(settings.get("dispatch",1.0))
		target.enabled=target.dispatch>0.0
	if settings.has("reserve"):
		if not _number(settings.reserve,0,.9): return {"ok":false,"message":"备用比例无效。"}
		projected.market.state.reserve_soc=float(settings.reserve)
		projected.management.state.storage_reserve=float(settings.reserve)
		for b in projected.buildings:
			if projected.evolution.is_storage(str(b.kind)):
				b.storage_reserve=float(settings.reserve)
				b.reserve_soc=float(settings.reserve)
	if settings.has("imports"):
		projected.management.state.operating_intent="economic" if bool(settings.imports) else "island"
		projected.market.state.market_mode="balanced" if bool(settings.imports) else "off"
	if settings.has("outage_line"):
		var line: Dictionary=projected.get_line(int(settings.outage_line))
		if line.is_empty(): return {"ok":false,"message":"线路不存在。"}
		line.closed=false
		line.fault=true
	if settings.has("outage_facility"):
		var target: Dictionary=projected.get_building(int(settings.outage_facility))
		if target.is_empty(): return {"ok":false,"message":"设施不存在。"}
		target.online=false
	var maintenance_quote: Dictionary={}
	if settings.has("maintenance"):
		var instruction: Variant=settings.maintenance
		if not instruction is Dictionary or instruction.get("target_type") not in ["facility","line"] or not _number(instruction.get("target_id"),1,1e9) or floorf(float(instruction.target_id))!=float(instruction.target_id) or not projected.lifecycle.ACTIONS.has(instruction.get("action")):
			return {"ok":false,"message":"请选择有效检修对象和处置方式。"}
		var target_type:=str(instruction.target_type)
		var target_id:=int(instruction.target_id)
		var action:=str(instruction.action)
		maintenance_quote=projected.lifecycle.quote(projected,target_type,target_id,action)
		if not maintenance_quote.ok: return {"ok":false,"message":"检修推演无法提交："+str(maintenance_quote.message)}
		var request: Dictionary=projected.lifecycle.maintenance(projected,target_type,target_id,action)
		if not request.ok: return {"ok":false,"message":"检修推演无法提交："+str(request.message)}
		maintenance_quote=maintenance_quote.duplicate(true)
		maintenance_quote.target_type=target_type
		maintenance_quote.target_id=target_id
		maintenance_quote.action=action
		maintenance_quote.title=str(projected.lifecycle.ACTIONS[action].name)
		maintenance_quote.initial_status="queued"
		for job in projected.lifecycle.jobs:
			if int(job.id)==int(request.id): maintenance_quote.initial_status=str(job.status)
		assumptions.append("%s #%d 的%s按实际现场队、备件、路程及作业停运在副本中排队；报价不含等待空闲队伍的未定时长，不预报随机故障或保证可靠性提升。" % ["设施" if target_type=="facility" else "线路",target_id,maintenance_quote.title])
	projected._solve(0.0)
	var rows: Array=[]
	# Include up-front planned maintenance, rather than hiding its cost by
	# starting the cash comparison after the disposable work order was charged.
	var start_cash:=float(sim.cash)
	var start_served:=float(projected.total_served_mwh)
	var start_demand:=float(projected.total_demand_mwh)
	var start_carbon:=float(projected.carbon_tonnes)
	var max_loading:=0.0
	var min_voltage:=1.0
	var min_reserve:=INF
	var clean_energy:=0.0
	var critical_points: Dictionary={}
	var critical_point_hours:=0.0
	var uncertainty:=0.08+minf(.32,float(unknown)/maxf(1.0,float(projected.buildings.size()))*.35)
	assumptions.append("清洁供电、关键负荷点失供点时和备用余量采用15分钟参考采样；关键负荷按医院负荷点计，不代表户数。排放仅计本地发电，不含外购电隐含排放。方案参数假设从推演起点采用，实际控制仍须另行提交并等待执行。")
	for offset in hours:
		for _quarter in 4:
			var previous_served:=float(projected.total_served_mwh)
			projected.step(0.25)
			var sample: Dictionary=projected.totals
			clean_energy+=maxf(0.0,float(projected.total_served_mwh)-previous_served)*clampf(float(sample.get("renewable_supply_share",0.0)),0,1)
			max_loading=maxf(max_loading,float(sample.max_loading))
			min_voltage=minf(min_voltage,float(sample.get("min_voltage",1.0)))
			var available_power:=0.0
			for building in projected.buildings:
				available_power+=float(building.available)
				if building.kind=="hospital" and projected.customer_service_active(int(building.id)) and float(building.demand)>0.00001 and float(building.served)<float(building.demand)*0.98:
					critical_points[int(building.id)]=true
					critical_point_hours+=0.25
			min_reserve=minf(min_reserve,available_power+float(sample.grid_capacity)-float(sample.demand))
		var t: Dictionary=projected.totals
		var demand:=float(t.demand)
		var wind:=0.0
		var solar:=0.0
		var available:=0.0
		for b in projected.buildings:
			if b.kind=="wind": wind+=float(b.available)
			if b.kind=="solar": solar+=float(b.available)
			available+=float(b.available)
		max_loading=maxf(max_loading,float(t.max_loading))
		min_voltage=minf(min_voltage,float(t.get("min_voltage",1.0)))
		rows.append({"offset":offset+1,"day":int(projected.day),"hour":float(projected.time_hours),"demand":demand,"served":float(t.served),"generation":float(t.generation),"clean_served":float(t.served)*float(t.get("renewable_supply_share",0.0)),"carbon_tph":float(t.get("carbon",0.0)),"demand_low":demand*(1.0-uncertainty),"demand_high":demand*(1.0+uncertainty),"wind":wind,"solar":solar,"net_load":demand-wind-solar,"storage_mwh":float(t.battery_mwh),"imports":float(t.import_mw),"unserved":float(t.outage),"reserve_mw":available+float(t.grid_capacity)-demand,"max_loading":float(t.max_loading),"min_voltage":float(t.get("min_voltage",1.0)),"price":float(t.market_price)})
	var served_energy:=maxf(0.0,float(projected.total_served_mwh)-start_served)
	var demand_energy:=maxf(0.0,float(projected.total_demand_mwh)-start_demand)
	var local_carbon:=maxf(0.0,float(projected.carbon_tonnes)-start_carbon)
	return {"ok":true,"rows":rows,"assumptions":assumptions,"confidence":"参考" if unknown>0 or meter_unknown>0 else "较高","unknown_facilities":unknown,
		"horizon_hours":hours,"sample_hours":0.25,"source_elapsed_hours":float(sim.elapsed_hours),"source_day":int(sim.day),"source_time_hours":float(sim.time_hours),
		"net_cash":float(projected.cash)-start_cash,"served_mwh":served_energy,"demand_mwh":demand_energy,"unserved_mwh":maxf(0.0,demand_energy-served_energy),
		"clean_served_mwh":clean_energy,"clean_supply_share":clean_energy/served_energy if served_energy>0.000001 else 0.0,"local_carbon_tonnes":local_carbon,
		"local_carbon_kg_per_served_mwh":local_carbon*1000.0/served_energy if served_energy>0.000001 else null,
		"critical_unserved_points":critical_points.size(),"critical_unserved_point_hours":critical_point_hours,"min_reserve_mw":min_reserve,
		"max_loading":max_loading,"min_voltage":min_voltage,"maintenance_quote":maintenance_quote,"settings":settings.duplicate(true)}

func compare(sim: RefCounted, plans: Array) -> Dictionary:
	if plans.is_empty() or plans.size()>3: return {"ok":false,"message":"请选择1—3个运行方案。"}
	var results: Array=[]
	for plan in plans:
		if not plan is Dictionary: return {"ok":false,"message":"运行方案格式无效。"}
		var result:=forecast(sim,plan)
		if not result.ok: return result
		results.append(result)
	return {"ok":true,"plans":results}

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(data: Dictionary) -> void:
	state=data.duplicate(true)

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func valid(data: Variant) -> bool:
	if not data is Dictionary: return false
	for key in ["opening_cash","cash_balance"]:
		if not _number(data.get(key),-1e15,1e15): return false
	if not _number(data.get("operating_hours"),0,1e12) or not _number(data.get("next_event"),1,1e12): return false
	if not data.get("cash_entries") is Array or data.cash_entries.size()>1000: return false
	var balance:=float(data.opening_cash)
	for entry in data.cash_entries:
		if not entry is Dictionary or not _number(entry.get("hour"),0,1e12) or not _number(entry.get("amount"),-1e15,1e15) or not _number(entry.get("balance"),-1e15,1e15): return false
		if not entry.get("category") is String or not entry.get("description") is String: return false
		balance+=float(entry.amount)
		if absf(balance-float(entry.balance))>.01: return false
	if absf(balance-float(data.cash_balance))>.01: return false
	if not data.get("active_outages") is Dictionary or data.active_outages.size()>512 or not data.get("outages") is Array or data.outages.size()>200: return false
	var events: Array=data.outages.duplicate()
	events.append_array(data.active_outages.values())
	for event in events:
		if not event is Dictionary: return false
		for key in ["id","facility_id","start","duration","unserved_mwh","cost"]:
			if not _number(event.get(key),0,1e15): return false
		if not _number(event.get("end"),-1,1e12) or not _number(event.get("city_id"),-1,1e9) or not event.get("critical") is bool: return false
		if not event.get("name") is String or not event.get("cause") is String or not event.get("curve") is Array or event.curve.size()>97: return false
		for row in event.curve:
			if not row is Dictionary or not _number(row.get("hour"),0,1e12) or not _number(row.get("served_fraction"),0,1): return false
	return true
