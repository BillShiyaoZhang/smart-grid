extends RefCounted
## Compressed asset management. Only advance/after_solve commit wear or RNG.
## Field jobs share the simulation's two crews, but own their maintenance effects.

const ACTIONS := {
	"inspect":{"name":"现场巡检","hours":0.15,"cost":250.0,"rate":0.0,"spares":0},
	"service":{"name":"计划保养","hours":0.45,"cost":500.0,"rate":0.03,"spares":0},
	"overhaul":{"name":"部件大修","hours":1.5,"cost":1200.0,"rate":0.15,"spares":1},
	"replace":{"name":"设备更换","hours":3.0,"cost":2500.0,"rate":0.65,"spares":2}
}
const STORAGE_WEAR := {"battery":0.08,"community_battery":0.08,"flow_battery":0.02,"pumped_storage":0.005,"hydrogen":0.01,"thermal_storage":0.015}
var enabled := false
var spares := 4
var next_job_id := 1
var jobs: Array[Dictionary] = []
var receipts: Array[Dictionary] = []
var failures := 0

func reset() -> void:
	enabled=false
	spares=4
	next_job_id=1
	jobs.clear()
	receipts.clear()
	failures=0

func enable(sim: RefCounted) -> Dictionary:
	if bool(sim.campaign.active): return _result(false,"历史教学关卡使用情景指定的运维规则。")
	if enabled: return _result(false,"资产风险管理已经启用。")
	enabled=true
	for b in sim.buildings: initialize_building(b)
	for line in sim.lines: initialize_line(line)
	return _result(true,"资产风险管理已启用：检修、寿命和现场物流开始参与实际运行。")

func initialize_building(b: Dictionary) -> void:
	_initialize_asset(b)
	if float(b.get("energy_capacity",0.0))>0.0:
		if not b.has("soh"): b.soh=100.0
		if not b.has("nominal_energy_capacity"): b.nominal_energy_capacity=float(b.energy_capacity)
		if not b.has("throughput_mwh"): b.throughput_mwh=0.0

func initialize_line(line: Dictionary) -> void:
	_initialize_asset(line)

func _initialize_asset(asset: Dictionary) -> void:
	for key in {"age_hours":0.0,"inspected_at":-1.0,"inspected_health":100.0,"lifecycle_busy":false,"lifecycle_failure":false}:
		if not asset.has(key): asset[key]={"age_hours":0.0,"inspected_at":-1.0,"inspected_health":100.0,"lifecycle_busy":false,"lifecycle_failure":false}[key]

func active_jobs() -> int:
	var count:=0
	for job in jobs:
		if job.status in ["travel","work"]: count+=1
	return count

func prune(sim: RefCounted) -> void:
	# Demolition may remove a queued target. Refund before discarding its job so
	# the cash journal and reserved inventory remain reconcilable immediately.
	for index in range(jobs.size()-1,-1,-1):
		var job: Dictionary=jobs[index]
		if not _target(sim,str(job.target_type),int(job.target_id)).is_empty(): continue
		spares=mini(30,spares+int(job.spares))
		if job.status=="queued": _charge(sim,float(job.cost),"maintenance_refund","目标移除，取消排队检修")
		receipts.append({"id":int(job.id),"target_type":str(job.target_type),"target_id":int(job.target_id),"action":str(job.action),"finished_at":float(sim.elapsed_hours),"health":0.0,"status":"cancelled"})
		jobs.remove_at(index)
	while receipts.size()>32: receipts.pop_front()

func risk_rate(asset: Dictionary, is_line: bool=false, severe_weather: bool=false) -> float:
	var health:=clampf(float(asset.get("health",100.0)),0.0,100.0)
	var condition:=1.0+pow(1.0-health/100.0,4.0)*2500.0
	var age:=1.0+minf(20.0,float(asset.get("age_hours",0.0))/400.0)
	var stress:=1.0
	if is_line: stress+=minf(10.0,pow(maxf(0.0,absf(float(asset.get("flow",0.0)))/maxf(0.1,float(asset.get("capacity",1.0)))-1.0),2.0)*5.0)
	return minf(2.0,(0.00005 if is_line else 0.0001)*condition*age*stress*(4.0 if severe_weather else 1.0))

func advance(sim: RefCounted, dt: float) -> void:
	if not enabled or dt<=0.0 or not is_finite(dt): return
	_advance_jobs(sim,dt)
	for target_type in ["facility","line"]:
		var assets: Array=sim.buildings if target_type=="facility" else sim.lines
		for asset in assets:
			if target_type=="facility": initialize_building(asset)
			else: initialize_line(asset)
			asset.age_hours=float(asset.age_hours)+dt
			if target_type=="line" and not bool(asset.lifecycle_busy): asset.health=maxf(5.0,float(asset.health)-0.01*dt)
			var operating: bool=bool(asset.get("online",true)) if target_type=="facility" else bool(asset.get("closed",false)) and not bool(asset.get("fault",false))
			if not operating or bool(asset.lifecycle_busy) or float(asset.get("repair_remaining",0.0))>0.0: continue
			if sim.get("_is_projection")==true: continue
			var chance:=1.0-exp(-risk_rate(asset,target_type=="line",bool(sim.storm_active))*dt)
			if sim.rng.randf()<chance:
				asset.lifecycle_failure=true
				if target_type=="facility": asset.online=false
				else:
					asset.fault=true
					asset.closed=false
					asset.trip_reason="设备劣化故障"
				failures+=1
				# Physical failure is not itself a trusted measurement.
				sim._log("部分设备出现运行异常，请核实用户报告与设备状态。","warning")

func after_solve(sim: RefCounted, dt: float) -> void:
	if not enabled or dt<=0.0 or not is_finite(dt): return
	for b in sim.buildings:
		if not STORAGE_WEAR.has(str(b.kind)): continue
		initialize_building(b)
		var expected:=float(b.nominal_energy_capacity)*float(b.soh)/100.0
		# External paid capacity upgrades remain part of the nominal asset.
		if float(b.energy_capacity)>expected+0.00001: b.nominal_energy_capacity=float(b.energy_capacity)/maxf(0.01,float(b.soh)/100.0)
		var throughput: float=(maxf(0.0,float(b.get("output",0.0)))+maxf(0.0,float(b.get("charging",0.0))))*dt
		b.throughput_mwh=float(b.throughput_mwh)+throughput
		var cycles:=throughput/maxf(0.0001,2.0*float(b.nominal_energy_capacity))
		b.soh=maxf(60.0,float(b.soh)-cycles*float(STORAGE_WEAR[b.kind])-dt*0.00005)
		b.energy_capacity=float(b.nominal_energy_capacity)*float(b.soh)/100.0
		var previous:=float(b.energy)
		b.energy=minf(previous,float(b.energy_capacity))
		b.renewable_energy_mwh=minf(float(b.energy),float(b.get("renewable_energy_mwh",0.0))*float(b.energy)/maxf(0.0001,previous))
		b.soc=float(b.energy)/maxf(0.0001,float(b.energy_capacity))

func quote(sim: RefCounted,target_type: String,id: int,action: String) -> Dictionary:
	var asset:=_target(sim,target_type,id)
	if not enabled: return _result(false,"请先启用资产风险管理。")
	if asset.is_empty() or not ACTIONS.has(action): return _result(false,"请选择有效设备与检修方式。")
	var rule: Dictionary=ACTIONS[action]
	var price: float=float(sim.catalog.get(str(asset.get("kind","")),{}).get("price",5000.0)) if target_type=="facility" else 5000.0*float(asset.get("level",1))
	var cost:=maxf(float(rule.cost),price*float(rule.rate))
	var travel:=_travel_hours(sim,asset,target_type)
	return {"ok":true,"message":"%s：预计 %.0f 游戏分钟，费用 ¥%.0f，需要备件 %d。" % [rule.name,(travel+float(rule.hours))*60.0,cost,int(rule.spares)],"cost":cost,"travel_hours":travel,"work_hours":float(rule.hours),"spares":int(rule.spares),"id":id}

func maintenance(sim: RefCounted,target_type: String,id: int,action: String,priority: int=0) -> Dictionary:
	var estimate:=quote(sim,target_type,id,action)
	if not estimate.ok: return estimate
	var asset:=_target(sim,target_type,id)
	if bool(asset.get("lifecycle_busy",false)) or float(asset.get("repair_remaining",0.0))>0.0: return _result(false,"设备已有检修任务。")
	if sim.get("digital")!=null and sim.digital.get("field_jobs") is Array:
		for field_job in sim.digital.field_jobs:
			if (target_type=="line" and int(field_job.get("line_id",-1))==id) or (target_type=="facility" and int(field_job.get("building_id",-1))==id): return _result(false,"该设备已有现场操作，请等待回执后检修。")
	for job in jobs:
		if job.target_type==target_type and int(job.target_id)==id: return _result(false,"设备已有排队或现场任务。")
	if jobs.size()>=64: return _result(false,"现场队列已满，请先完成已有任务。")
	if action=="service" and (bool(asset.get("lifecycle_failure",false)) or bool(asset.get("fault",false)) or (target_type=="facility" and not bool(asset.get("online",true)))): return _result(false,"故障设备需要大修或更换；保养只适用于可运行设备。")
	if int(estimate.spares)>spares: return _result(false,"关键备件不足，请先补充库存。")
	if float(sim.cash)<float(estimate.cost): return _result(false,"资金不足。")
	_charge(sim,-float(estimate.cost),"maintenance","%s #%d %s" % ["设施" if target_type=="facility" else "线路",id,ACTIONS[action].name])
	spares-=int(estimate.spares)
	var job: Dictionary={"id":next_job_id,"target_type":target_type,"target_id":id,"action":action,"priority":clampi(priority,0,2),"status":"queued","travel_remaining":float(estimate.travel_hours),"work_remaining":float(estimate.work_hours),"cost":float(estimate.cost),"spares":int(estimate.spares),"queued_at":float(sim.elapsed_hours),"original_online":bool(asset.get("online",true)),"original_closed":bool(asset.get("closed",true))}
	next_job_id+=1
	jobs.append(job)
	_dispatch(sim)
	return {"ok":true,"message":estimate.message+" 已加入现场队列。","id":int(job.id)}

func restock(sim: RefCounted,count: int=1) -> Dictionary:
	if not enabled or count<1 or count>20 or spares+count>30: return _result(false,"备件采购数量须为1—20，库存上限30。")
	var cost:=700.0*count
	if float(sim.cash)<cost: return _result(false,"资金不足。")
	_charge(sim,-cost,"spares","采购关键备件 ×%d" % count)
	spares+=count
	return _result(true,"关键备件已补充。")

func set_priority(job_id: int,priority: int) -> Dictionary:
	if priority<0 or priority>2: return _result(false,"优先级应为0—2。")
	for job in jobs:
		if int(job.id)==job_id and job.status=="queued":
			job.priority=priority
			return _result(true,"排队优先级已更新。")
	return _result(false,"只可调整尚未出发的任务。")

func cancel(sim: RefCounted,job_id: int) -> Dictionary:
	for index in jobs.size():
		var job: Dictionary=jobs[index]
		if int(job.id)!=job_id: continue
		if job.status!="queued": return _result(false,"现场队已出发，无法取消。")
		spares+=int(job.spares)
		_charge(sim,float(job.cost),"maintenance_refund","取消未出发的检修任务")
		jobs.remove_at(index)
		return _result(true,"排队任务已取消，费用和备件已退还。")
	return _result(false,"没有此排队任务。")

func _dispatch(sim: RefCounted) -> void:
	jobs.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.id)<int(b.id) if int(a.priority)==int(b.priority) else int(a.priority)>int(b.priority))
	for job in jobs:
		if job.status!="queued": continue
		if int(sim.active_repairs())>=2: break
		var asset:=_target(sim,str(job.target_type),int(job.target_id))
		if asset.is_empty(): continue
		job.status="travel"
		asset.lifecycle_busy=true

func _advance_jobs(sim: RefCounted,dt: float) -> void:
	_dispatch(sim)
	var finished: Array[int]=[]
	for job in jobs:
		var asset:=_target(sim,str(job.target_type),int(job.target_id))
		if asset.is_empty():
			# Demolition never silently consumes reserved stock or queued money.
			spares=mini(30,spares+int(job.spares))
			if job.status=="queued": _charge(sim,float(job.cost),"maintenance_refund","目标移除，取消排队检修")
			finished.append(int(job.id))
			continue
		if job.status=="queued": continue
		var remaining:=dt
		if job.status=="travel":
			var travel:=minf(remaining,float(job.travel_remaining))
			job.travel_remaining=maxf(0.0,float(job.travel_remaining)-travel)
			remaining-=travel
			if float(job.travel_remaining)<=0.000001:
				job.status="work"
				if job.action!="inspect":
					if job.target_type=="facility": asset.online=false
					else: asset.closed=false
		if job.status=="work":
			job.work_remaining=maxf(0.0,float(job.work_remaining)-remaining)
			if float(job.work_remaining)<=0.000001:
				_complete(sim,job,asset)
				finished.append(int(job.id))
	for id in finished:
		for index in range(jobs.size()-1,-1,-1):
			if int(jobs[index].id)==id: jobs.remove_at(index)
	_dispatch(sim)

func _complete(sim: RefCounted,job: Dictionary,asset: Dictionary) -> void:
	asset.lifecycle_busy=false
	match str(job.action):
		"service": asset.health=minf(95.0,float(asset.health)+15.0)
		"overhaul": asset.health=maxf(float(asset.health),90.0)
		"replace":
			asset.health=100.0
			asset.age_hours=0.0
			if asset.has("soh"):
				asset.soh=100.0
				asset.energy_capacity=float(asset.nominal_energy_capacity)
				asset.throughput_mwh=0.0
	if job.action!="inspect":
		asset.lifecycle_failure=false
		if job.target_type=="facility": asset.online=true
		else:
			asset.closed=bool(job.original_closed) if job.action=="service" else true
			asset.fault=false
			asset.heat=0.0
			asset.trip_reason=""
	asset.inspected_at=float(sim.elapsed_hours)
	asset.inspected_health=float(asset.health)
	if asset.has("soh"):
		asset.inspected_soh=float(asset.soh)
		asset.inspected_throughput_mwh=float(asset.throughput_mwh)
	if sim.get("digital")!=null:
		if job.target_type=="facility": sim.digital._sample_facility(sim,asset,"field")
		else: sim.digital._sample(sim,asset,"patrol")
	receipts.append({"id":int(job.id),"target_type":str(job.target_type),"target_id":int(job.target_id),"action":str(job.action),"finished_at":float(sim.elapsed_hours),"health":float(asset.health)})
	while receipts.size()>32: receipts.pop_front()
	sim._log("%s #%d %s完成。" % ["设施" if job.target_type=="facility" else "线路",int(job.target_id),ACTIONS[job.action].name],"success")

func _travel_hours(sim: RefCounted,asset: Dictionary,target_type: String) -> float:
	var destination:=Vector2.ZERO
	if target_type=="facility": destination=Vector2(asset.cell)
	else:
		var a: Dictionary=sim.get_building(int(asset.a))
		var b: Dictionary=sim.get_building(int(asset.b))
		if not a.is_empty() and not b.is_empty(): destination=(Vector2(a.cell)+Vector2(b.cell))*0.5
	var distance:=destination.distance_to(Vector2(6,7))
	for b in sim.buildings:
		if str(b.kind) in ["substation","control"] and bool(b.get("online",true)): distance=minf(distance,destination.distance_to(Vector2(b.cell)))
	return 0.1+distance/20.0

func report(sim: RefCounted) -> Dictionary:
	var assets: Array[Dictionary]=[]
	for target_type in ["facility","line"]:
		var targets: Array=sim.buildings if target_type=="facility" else sim.lines
		for asset in targets:
			var observation: Dictionary=sim.facility_observation(int(asset.id)) if target_type=="facility" else sim.line_observation(int(asset.id))
			var fresh: bool=bool(observation.get("trusted",false)) if target_type=="facility" else bool(observation.get("fault_known",false))
			var inspected:=float(asset.get("inspected_at",-1.0))>=0.0
			var health: Variant=observation.get("health") if fresh else (float(asset.get("inspected_health",100.0)) if inspected else null)
			var row: Dictionary={"target_type":target_type,"id":int(asset.id),"name":str(asset.get("name","线路 #%d" % int(asset.id))),"age_hours":float(asset.get("age_hours",0.0)),"health":health,"current_verified":fresh,"inspected_at":float(asset.get("inspected_at",-1.0)),"busy":bool(asset.get("lifecycle_busy",false)),"risk_per_hour":null,"soh":null,"throughput_mwh":null}
			if fresh and health!=null:
				var known_asset: Dictionary=asset.duplicate()
				known_asset.health=float(health)
				known_asset.flow=float(observation.get("flow",0.0)) if observation.get("flow")!=null else 0.0
				row.risk_per_hour=risk_rate(known_asset,target_type=="line",bool(sim.storm_active))
			if fresh and asset.has("soh") and observation.get("soh")!=null:
				row.soh=float(observation.soh)
				row.throughput_mwh=observation.get("throughput_mwh",null)
			elif inspected and asset.has("inspected_soh"):
				row.soh=float(asset.inspected_soh)
				row.throughput_mwh=float(asset.get("inspected_throughput_mwh",0.0))
			assets.append(row)
	return {"enabled":enabled,"spares":spares,"active_jobs":active_jobs(),"jobs":jobs.duplicate(true),"receipts":receipts.duplicate(true),"assets":assets,"failures":failures}

func snapshot() -> Dictionary:
	return {"enabled":enabled,"spares":spares,"next_job_id":next_job_id,"jobs":jobs.duplicate(true),"receipts":receipts.duplicate(true),"failures":failures}

func restore(data: Dictionary) -> void:
	if not data.is_empty() and not valid_snapshot(data): return
	reset()
	if data.is_empty(): return
	enabled=bool(data.enabled)
	spares=int(data.spares)
	next_job_id=int(data.next_job_id)
	failures=int(data.failures)
	jobs.assign(data.jobs.duplicate(true))
	receipts.assign(data.receipts.duplicate(true))

static func valid(data: Variant) -> bool:
	return valid_snapshot(data)

static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("enabled") is bool: return false
	if not _integer(data.get("spares"),0,30) or not _integer(data.get("next_job_id"),1,1000000000) or not _integer(data.get("failures"),0,1000000000): return false
	if not data.get("jobs") is Array or data.jobs.size()>64 or not data.get("receipts") is Array or data.receipts.size()>32: return false
	if not bool(data.enabled) and not data.jobs.is_empty(): return false
	var job_ids: Dictionary={}
	var targets: Dictionary={}
	var active:=0
	for job in data.jobs:
		if not job is Dictionary or not _integer(job.get("id"),1,int(data.next_job_id)-1) or job_ids.has(int(job.id)): return false
		if job.get("target_type") not in ["facility","line"] or not _integer(job.get("target_id"),1,1000000000) or not ACTIONS.has(job.get("action")): return false
		var target_key: String=str(job.target_type)+":"+str(job.target_id)
		if targets.has(target_key): return false
		targets[target_key]=true
		job_ids[int(job.id)]=true
		if not _integer(job.get("priority"),0,2) or job.get("status") not in ["queued","travel","work"]: return false
		if job.status!="queued": active+=1
		if not _number(job.get("travel_remaining"),0.0,100.0) or not _number(job.get("work_remaining"),0.0,4.0): return false
		if not _number(job.get("cost"),0.0,1e12) or not _integer(job.get("spares"),0,2) or not _number(job.get("queued_at"),0.0,1e12): return false
		if not job.get("original_online") is bool or not job.get("original_closed") is bool: return false
	if active>2: return false
	for receipt in data.receipts:
		if not receipt is Dictionary or not _integer(receipt.get("id"),1,int(data.next_job_id)-1) or receipt.get("target_type") not in ["facility","line"]: return false
		if not _integer(receipt.get("target_id"),1,1000000000) or not ACTIONS.has(receipt.get("action")) or not _number(receipt.get("finished_at"),0.0,1e12) or not _number(receipt.get("health"),0.0,100.0): return false
	return true

static func validate_asset(asset: Dictionary) -> bool:
	for key in ["age_hours","throughput_mwh","nominal_energy_capacity","inspected_throughput_mwh"]:
		if asset.has(key) and not _number(asset[key],0.0,1e12): return false
	if asset.has("soh") and not _number(asset.soh,60.0,100.0): return false
	if asset.has("inspected_soh") and not _number(asset.inspected_soh,60.0,100.0): return false
	if asset.has("inspected_at") and not _number(asset.inspected_at,-1.0,1e12): return false
	if asset.has("inspected_health") and not _number(asset.inspected_health,0.0,100.0): return false
	for key in ["lifecycle_busy","lifecycle_failure"]:
		if asset.has(key) and not asset[key] is bool: return false
	return true

static func valid_references(data: Dictionary,buildings: Array,lines: Array,elapsed: float) -> bool:
	if not valid_snapshot(data): return false
	var references: Dictionary={}
	for target_type in ["facility","line"]:
		for asset in (buildings if target_type=="facility" else lines):
			if not asset is Dictionary or not validate_asset(asset): return false
			if float(asset.get("inspected_at",-1.0))>elapsed+0.000001: return false
			references[target_type+":"+str(int(asset.id))]=asset
	var busy: Dictionary={}
	for job in data.jobs:
		var key: String=str(job.target_type)+":"+str(int(job.target_id))
		if not references.has(key) or float(job.queued_at)>elapsed+0.000001: return false
		if job.status!="queued": busy[key]=true
	for key in references:
		if bool(references[key].get("lifecycle_busy",false))!=busy.has(key): return false
	for receipt in data.receipts:
		if float(receipt.finished_at)>elapsed+0.000001: return false
	return true

func _target(sim: RefCounted,target_type: String,id: int) -> Dictionary:
	if target_type=="facility": return sim.get_building(id)
	if target_type=="line": return sim.get_line(id)
	return {}

func _charge(sim: RefCounted,amount: float,category: String,description: String) -> void:
	if sim.has_method("record_cash_change"): sim.record_cash_change(amount,category,description)
	else: sim.cash+=amount

func _result(ok: bool,message: String) -> Dictionary:
	return {"ok":ok,"message":message,"id":-1}

static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant,low: int,high: int) -> bool:
	return _number(value,low,high) and floorf(float(value))==float(value)
