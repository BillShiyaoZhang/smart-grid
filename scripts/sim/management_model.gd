extends RefCounted
## Player-facing operating intent and the gradual, outcome-based management route.
## Queries never advance the world; history is sampled only by advance().
const DEFAULT := {"active":false,"stage":0,"hold_hours":0.0,"best_hours":0.0,
	"interruption":"","night_seen":false,"first_storm_prepared":false,
	"operating_intent":"legacy_custom","allow_export":false,
	"storage_intent":"legacy_custom","storage_reserve":0.2,
	"best_records":[0.0,0.0,0.0,0.0,0.0],"sandbox_best":{"regional":0.0,"clean":0.0,"profitable":0.0},"sandbox_interruption":"","history":[]}
const TITLES := ["点亮工业园","稳住昼夜供需","选择清洁而盈利的方案","建立备用，迎接风暴","逐城拓展服务"]
const DESCRIPTIONS := ["接通工业园，让全城稳定供电一小时。","运行到夜间，观察风光与储能，持续可靠供电一小时。",
	"在可靠供电的同时，让实际清洁供电达到35%，并保持运营不亏损两小时。",
	"先建设备用和安排现场队，准备完成后再迎接首次风暴；随后恢复可靠供电。",
	"查看潜在城市，规划并接入一座新城，再明确开通服务。"]
const REQUIRED := [1.0,1.0,2.0,1.0,1.0]
var state: Dictionary = DEFAULT.duplicate(true)

func reset() -> void:
	state=DEFAULT.duplicate(true)

func start(sim: RefCounted) -> void:
	reset()
	state.active=true
	state.operating_intent="economic"
	state.storage_intent="supply"
	sim.digital.reset(sim)
	sim.next_storm_at=1e10
	sim.storm_warning_sent=false
	# Preserve the familiar island assets, but introduce their controls gradually.
	sim.objectives.assign([
		{"id":"industry","title":TITLES[0],"description":DESCRIPTIONS[0],"reward":12000,"done":false,"progress":0.0},
		{"id":"renewable","title":TITLES[1],"description":DESCRIPTIONS[1],"reward":18000,"done":false,"progress":0.0},
		{"id":"smart","title":TITLES[2],"description":DESCRIPTIONS[2],"reward":20000,"done":false,"progress":0.0},
		{"id":"resilience","title":TITLES[3],"description":DESCRIPTIONS[3],"reward":25000,"done":false,"progress":0.0},
		{"id":"regional","title":TITLES[4],"description":DESCRIPTIONS[4],"reward":0,"done":false,"progress":0.0}])

func allows(feature: String) -> bool:
	if not state.active: return true
	var stage:=int(state.stage)
	if feature=="natural_events": return bool(state.first_storm_prepared)
	if feature=="cyber_events": return stage>=4
	if feature in ["market","external_supply"]: return stage>=1
	if feature in ["digital","remote","auto_restore","demand_response","storage_control","security"]: return stage>=3
	if feature=="storm": return stage>=3
	return true

func can_build(kind: String) -> bool:
	if not state.active: return true
	var stage:=int(state.stage)
	if kind in ["sensor","control","relay","soc"]: return stage>=3
	if kind in ["intertie","hvdc"]: return stage>=1
	return true

func conditions(sim: RefCounted) -> Array[Dictionary]:
	var stage:=mini(4,int(state.stage))
	var reliable:=float(sim.totals.get("reliability",1.0))
	var result: Array[Dictionary]=[_condition("供电率",reliable*100.0,98.0,"%")]
	match stage:
		0:
			var industrial:=false
			for b in sim.buildings:
				if b.kind=="factory" and float(b.get("served",0))>=float(b.get("demand",0))*0.98 and float(b.get("demand",0))>0: industrial=true
			result.append(_condition("工业园已得到供电",1.0 if industrial else 0.0,1.0,""))
		1: result.append(_condition("已观察夜间运行",1.0 if state.night_seen else 0.0,1.0,""))
		2:
			result.append(_condition("实际清洁供电",float(sim.totals.get("renewable_supply_share",0))*100.0,35.0,"%"))
			var net:=float(sim.totals.get("income",0))-float(sim.totals.get("expenses",0))
			result.append(_condition("运营净收益",net,0.0,"¥/h"))
		3:
			result.append(_condition("首次风暴已完成恢复",1.0 if int(sim.restored_storms)>0 else 0.0,1.0,""))
		4:
			var supplied:=0
			for city in sim.region.cities:
				if int(city.id)>0 and city.get("service_phase","active")=="active" and float(city.get("service",0))>=0.98: supplied+=1
			result.append(_condition("新城可靠服务",float(supplied),1.0,"座"))
	return result

func status(sim: RefCounted) -> Dictionary:
	var stage:=int(state.stage)
	var finished:=stage>=5
	return {"active":bool(state.active),"stage":stage,"title":"经营路线完成 · 自由运营" if finished else TITLES[stage],
		"description":"继续扩张城市，选择长期目标或探索高级运维。" if finished else DESCRIPTIONS[stage],
		"progress":1.0 if finished else clampf(float(state.hold_hours)/float(REQUIRED[stage]),0,1),
		"elapsed_hours":float(state.hold_hours),"remaining_hours":0.0 if finished else maxf(0,float(REQUIRED[stage])-float(state.hold_hours)),
		"required_hours":0.0 if finished else float(REQUIRED[stage]),"best_hours":float(state.best_hours),
		"interruption":str(state.interruption),"conditions":[] if finished else conditions(sim),
		"first_storm_ready":bool(state.active) and stage>=3 and not bool(state.first_storm_prepared),
		"first_storm_prepared":bool(state.first_storm_prepared),"completed":finished}

func advance(sim: RefCounted, dt: float) -> void:
	if dt<=0: return
	_sample(sim)
	if not state.active or int(state.stage)>=5: return
	if float(sim.time_hours)>=19.0 or float(sim.time_hours)<6.0: state.night_seen=true
	var checks:=conditions(sim)
	var interruption:=""
	for condition in checks:
		if not condition.met:
			interruption=str(condition.label)+"未达标"
			break
	var stage:=int(state.stage)
	if interruption.is_empty():
		state.hold_hours=float(state.hold_hours)+dt
		state.best_hours=maxf(float(state.best_hours),float(state.hold_hours))
		state.best_records[stage]=maxf(float(state.best_records[stage]),float(state.hold_hours))
		state.interruption=""
	else:
		if float(state.hold_hours)>0.000001: state.interruption=interruption+"，连续计时重新开始；最佳纪录已保留。"
		state.hold_hours=0.0
	if stage<sim.objectives.size(): sim.objectives[stage].progress=clampf(float(state.hold_hours)/float(REQUIRED[stage]),0,1)
	if float(state.hold_hours)+0.000001>=float(REQUIRED[stage]):
		if stage<sim.objectives.size() and not bool(sim.objectives[stage].done):
			sim.objectives[stage].done=true
			sim.objectives[stage].progress=1.0
			sim.record_cash_change(float(sim.objectives[stage].reward),"reward","经营成果奖励")
		state.stage=stage+1
		if stage==3: sim.digital.next_attack_at=float(sim.elapsed_hours)+12.0
		state.hold_hours=0.0
		state.best_hours=float(state.best_records[mini(4,stage+1)])
		state.interruption=""
		sim._log("经营成果「%s」已达成。%s" % [TITLES[stage],"下一步："+TITLES[stage+1] if stage<4 else "可继续自由经营。"],"success")

func prepare_storm(sim: RefCounted) -> Dictionary:
	if not state.active or int(state.stage)<3: return sim._fail("先完成接网、昼夜与清洁盈利经营任务，再安排首次风暴。")
	if state.first_storm_prepared: return sim._fail("首次风暴已安排，请按气象预警准备。")
	state.first_storm_prepared=true
	sim.next_storm_at=float(sim.elapsed_hours)+1.0
	sim.storm_warning_sent=false
	sim._log("准备完成：首次风暴将在1游戏小时后抵达，之后进入自然预报周期。","warning")
	return sim._ok("首次风暴已安排，留有1游戏小时准备。")

func _sample(sim: RefCounted) -> void:
	var row: Dictionary={"hour":float(sim.elapsed_hours),"day":int(sim.day),"time":float(sim.time_hours),
		"served":float(sim.totals.get("served",0)),"demand":float(sim.totals.get("demand",0)),
		"generation":float(sim.totals.get("generation",0))+float(sim.totals.get("import_mw",0)),
		"net":float(sim.totals.get("income",0))-float(sim.totals.get("expenses",0)),
		"reliability":float(sim.totals.get("reliability",1)),"clean":float(sim.totals.get("renewable_supply_share",0)),
		"satisfaction":float(sim.market.state.satisfaction),"storm":bool(sim.storm_active)}
	var history: Array=state.history
	if not history.is_empty() and floorf(float(history[-1].hour)*12)==floorf(float(row.hour)*12): history[-1]=row
	else: history.append(row)
	while history.size()>300 or (history.size()>2 and float(history[-1].hour)-float(history[0].hour)>24): history.pop_front()

func snapshot() -> Dictionary:
	return state.duplicate(true)

func load_snapshot(data: Dictionary) -> void:
	state=data.duplicate(true)
	state.stage=int(state.stage)

static func valid_snapshot(data: Variant, elapsed: float) -> bool:
	if not data is Dictionary: return false
	for key in DEFAULT:
		if not data.has(key): return false
	for key in ["active","night_seen","first_storm_prepared","allow_export"]:
		if not data[key] is bool: return false
	if not _number(data.stage,0,5) or floorf(float(data.stage))!=float(data.stage): return false
	if data.operating_intent not in ["legacy_custom","economic","self_supply","island"] or data.storage_intent not in ["legacy_custom","supply","peak","arbitrage"]: return false
	if not _number(data.storage_reserve,0,0.9) or not data.interruption is String or data.interruption.length()>300: return false
	if not data.sandbox_interruption is String or data.sandbox_interruption.length()>300 or not data.sandbox_best is Dictionary: return false
	for key in ["regional","clean","profitable"]:
		if not _number(data.sandbox_best.get(key),0,1e12): return false
	for key in ["hold_hours","best_hours"]:
		if not _number(data[key],0,1e12): return false
	if not data.best_records is Array or data.best_records.size()!=5: return false
	for value in data.best_records:
		if not _number(value,0,1e12): return false
	if not data.history is Array or data.history.size()>300: return false
	var last:=-1.0
	for row in data.history:
		if not row is Dictionary or not _number(row.get("hour"),0,elapsed+0.00001) or float(row.hour)<last: return false
		last=float(row.hour)
		for key in ["served","demand","generation"]:
			if not _number(row.get(key),0,1e9): return false
		for key in ["reliability","clean"]:
			if not _number(row.get(key),0,1): return false
		if not _number(row.get("net"),-1e12,1e12) or not _number(row.get("satisfaction"),0,100) or not row.get("storm") is bool: return false
		if not _number(row.get("day"),1,1e9) or not _number(row.get("time"),0,24): return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _condition(label: String,value: float,target: float,unit: String) -> Dictionary:
	return {"label":label,"value":value,"target":target,"unit":unit,"known":true,"met":value+0.000001>=target}
