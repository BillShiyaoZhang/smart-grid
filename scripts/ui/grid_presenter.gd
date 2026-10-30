extends RefCounted
## Operator views deliberately read identity, nameplate data, observations and public totals.
## Raw fault/health/output/online fields never cross this presentation boundary.

static func category_for(kind: String) -> String:
	if kind in ["battery","pumped_storage","flow_battery","community_battery","hydrogen","thermal_storage"]: return "storage"
	if kind in ["sensor","control","relay","soc"]: return "digital"
	if kind in ["home","factory","hospital","academy","cooling"]: return "city"
	if kind in ["substation","intertie","hvdc","condenser"]: return "grid"
	return "power"

static func operating_snapshot(sim: RefCounted) -> Dictionary:
	var demand: float=maxf(0,float(sim.totals.get("demand",0)))
	var served: float=maxf(0,float(sim.totals.get("served",0)))
	return {"hour":float(sim.elapsed_hours),"demand":demand,"served":served,
		"deficit":maxf(0,demand-served),"reliability":clampf(served/demand,0,1) if demand>.000001 else 1.0,
		"cash":float(sim.cash),"net_rate":float(sim.totals.get("income",0))-float(sim.totals.get("expenses",0))}

static func customer_feedback(sim: RefCounted, id: int) -> Dictionary:
	var building: Dictionary=sim.get_building(id)
	if building.is_empty() or str(building.kind) not in ["home","factory","hospital"]: return {}
	if sim.has_method("customer_service_active") and not sim.customer_service_active(id): return {}
	return {"powered":bool(building.get("powered",false)),"text":"用户有供电反馈" if bool(building.get("powered",false)) else "用户报告停电","source":"公开用户供电反馈"}

static func facilities(sim: RefCounted, query: String="", filter: String="all") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var needle: String = query.strip_edges().to_lower()
	var pending: Dictionary = {}
	var connected: Dictionary = {}
	for line in sim.lines:
		connected[int(line.a)]=true
		connected[int(line.b)]=true
	for job in jobs(sim):
		if job.target_type=="facility" and job.phase=="pending": pending[int(job.target_id)]=true
	for building in sim.buildings:
		var id: int = int(building.id)
		var kind: String = str(building.kind)
		var name_text: String = str(building.name)
		if not needle.is_empty() and needle not in (name_text+" "+kind+" "+str(id)).to_lower(): continue
		var observed: Dictionary = sim.facility_observation(id)
		var trusted: bool = bool(observed.get("trusted",false))
		var fault: bool = trusted and (float(observed.get("health",100))<=0.0 or "劣化故障" in str(observed.status))
		var feedback: Dictionary=customer_feedback(sim,id)
		var outage: bool = (trusted and float(observed.get("demand",0))>float(observed.get("served",0))+.01) or (not feedback.is_empty() and not bool(feedback.powered))
		var category: String = category_for(kind)
		var known_issue: bool = fault or outage or pending.has(id) or not connected.has(id)
		var status_text: String = str(observed.status)
		if outage and not trusted: status_text="用户报告停电 · 设备读数待核实"
		known_issue=known_issue or (trusted and ("启动" in status_text or "配套" in status_text or "岗位不足" in status_text))
		if filter in ["power","grid","storage","city","digital"] and category!=filter: continue
		if filter in ["unknown","untrusted"] and trusted: continue
		if filter=="trusted" and not trusted: continue
		if filter=="issues" and not known_issue: continue
		if filter=="fault" and not fault: continue
		if filter=="outage" and not outage: continue
		if filter=="pending" and not pending.has(id): continue
		var row: Dictionary = {"id":id,"name":name_text,"kind":kind,"category":category,"cell":building.cell,
			"capacity":float(building.get("capacity",0)),"energy_capacity":float(building.get("energy_capacity",0)),"status":status_text,"visibility":str(observed.visibility),
			"trusted":trusted,"source":str(observed.get("reason","")),"age_hours":float(observed.get("age_hours",0)),
			"fault":fault,"outage":outage,"pending":pending.has(id),"connected":connected.has(id)}
		for key in ["available","output","served","demand","energy","health"]:
			row[key]=observed.get(key) if trusted else null
		result.append(row)
	return result

static func _item(id: String, severity: String, title: String, detail: String, target_type: String="global", target_id: int=-1, action: String="diagnose", source: String="公开运行指标") -> Dictionary:
	return {"id":id,"severity":severity,"title":title,"detail":detail,"target_type":target_type,
		"target_id":target_id,"action":action,"source":source}

static func alerts(sim: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var demand: float = float(sim.totals.get("demand",0))
	var served: float = float(sim.totals.get("served",0))
	if demand-served>.01:
		result.append(_item("supply","critical","供电不足 · 缺额 %.1f MW" % (demand-served),"先查看供电诊断，再核实电源、连接与线路瓶颈。"))
	if bool(sim.storm_active):
		result.append(_item("storm","warning","风暴持续中","检查已知故障、备用容量和现场队。","global",-1,"diagnose","公开气象"))
	elif sim.feature_enabled("natural_events") and float(sim.totals.get("storm_in",99))<=1.0:
		result.append(_item("storm","warning","风暴即将到来","检查备用路径与维修队；预计一游戏小时内抵达。","global",-1,"diagnose","公开气象预警"))
	for line in sim.lines:
		var id: int = int(line.id)
		var observed: Dictionary = sim.line_observation(id)
		if str(observed.get("visibility","unknown")) not in ["verified","patrol"]: continue
		var source: String = str(observed.get("reason","可信线路观测"))
		if bool(observed.get("fault_known",false)) and bool(observed.get("fault",false)):
			result.append(_item("line_fault_%d" % id,"critical","线路 %02d · 故障已确认" % id,"定位线路并派遣抢修；可先检查备用路径。","line",id,"repair",source))
		elif observed.get("flow")!=null and float(line.get("capacity",0))>0:
			var ratio: float = absf(float(observed.flow))/float(line.capacity)
			if ratio>=.85:
				result.append(_item("line_load_%d" % id,"critical" if ratio>=1 else "warning","线路 %02d · 负载 %.0f%%" % [id,ratio*100],"检查线路容量、备用路径或削峰方案。","line",id,"inspect",source))
	for facility in facilities(sim):
		if facility.fault:
			result.append(_item("facility_fault_%d" % int(facility.id),"critical",str(facility.name)+" · 设备故障","观测已核实设备损伤；定位后检查维修队。","facility",int(facility.id),"repair",str(facility.source)))
		if not facility.trusted: continue
		var measured: Dictionary=sim.facility_observation(int(facility.id))
		if sim.engineering.enabled and measured.get("voltage")!=null and float(measured.voltage)>0 and (float(measured.voltage)<.95 or float(measured.voltage)>1.05):
			result.append(_item("voltage_%d" % int(facility.id),"warning",str(facility.name)+" · 电压质量异常","可信测量 %.3f pu；检查馈线长度、线路等级、变电容量或本地储能。" % float(measured.voltage),"facility",int(facility.id),"inspect",str(facility.source)))
		if sim.engineering.enabled and measured.get("transformer_loading")!=null and float(measured.transformer_loading)>.95:
			result.append(_item("transformer_%d" % int(facility.id),"warning",str(facility.name)+" · 变电容量紧张","可信负载 %.0f%%；可增容、转移负荷或在下游部署灵活资源。" % (float(measured.transformer_loading)*100),"facility",int(facility.id),"inspect",str(facility.source)))
	for incident in sim.digital.incidents:
		if not bool(incident.get("detected",false)) or str(incident.get("status",""))!="active": continue
		var target: int = int(incident.get("target_id",-1))
		result.append(_item("incident_%d" % int(incident.id),"critical","设备 %02d · 已检测网络事件" % target,"查看已检测事件并核实设备，再安排隔离与恢复。","facility",target,"security","已检测网络事件"))
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return _severity_order(str(a.severity))<_severity_order(str(b.severity)))
	return result

static func _severity_order(value: String) -> int:
	return 0 if value=="critical" else (1 if value=="warning" else 2)

static func diagnosis(sim: RefCounted) -> Dictionary:
	var demand: float = float(sim.totals.get("demand",0))
	var served: float = float(sim.totals.get("served",0))
	var deficit: float = maxf(0,demand-served)
	var causes: Array[Dictionary] = []
	var connected: Dictionary = {}
	for line in sim.lines:
		connected[int(line.a)]=true
		connected[int(line.b)]=true
	var unknown_count: int = 0
	var known_available: float = 0.0
	var storage_upper_bound: float = 0.0
	var known_demand: float = 0.0
	for facility in facilities(sim):
		var id: int = int(facility.id)
		var name_text: String = str(facility.name)
		if not connected.has(id):
			causes.append(_item("unconnected_%d" % id,"warning",name_text+" · 未接电力线路","设施尚无电力连接；连接后核实实际供电。","facility",id,"connect","公开电力拓扑"))
		if not bool(facility.trusted):
			unknown_count+=1
			if bool(facility.outage) and connected.has(id):
				causes.append(_item("customer_outage_%d" % id,"warning",name_text+" · 用户报告停电","用户供电反馈可确认失供；线路原因与设备读数仍需现场核实。","facility",id,"inspect","公开用户供电反馈"))
			continue
		var status_text: String = str(facility.status)
		known_demand+=float(facility.demand)
		if str(facility.category)=="power": known_available+=maxf(0.0,float(facility.available))
		if str(facility.category)=="storage" and float(facility.energy)>.0001: storage_upper_bound+=float(facility.capacity)
		if facility.fault:
			causes.append(_item("fault_%d" % id,"critical",name_text+" · 设备故障","已核实健康状态；检查维修队与备用电源。","facility",id,"repair",str(facility.source)))
		elif "启动" in status_text or "配套" in status_text or "冷却" in status_text or "岗位不足" in status_text:
			causes.append(_item("availability_%d" % id,"warning",name_text+" · 可用出力受限",status_text,"facility",id,"inspect",str(facility.source)))
		elif bool(facility.outage):
			causes.append(_item("outage_%d" % id,"warning",name_text+" · 实际供电不足","可信观测显示 %.1f / %.1f MW；检查相连线路与本地可用电源。" % [facility.served,facility.demand],"facility",id,"inspect",str(facility.source)))
	for alert in alerts(sim):
		if str(alert.id).begins_with("line_") or str(alert.id).begins_with("voltage_") or str(alert.id).begins_with("transformer_"): causes.append(alert)
	for line in sim.lines:
		var observed: Dictionary = sim.line_observation(int(line.id))
		if str(observed.get("visibility","")) in ["verified","patrol"] and not bool(observed.get("closed",true)) and not bool(observed.get("fault",false)):
			causes.append(_item("open_%d" % int(line.id),"warning","线路 %02d · 开关已断开" % int(line.id),"已核实开关断开；检查它是否影响当前供电，再安排现场或远程合闸。","line",int(line.id),"inspect",str(observed.get("reason","可信线路观测"))))
	var external_upper_bound: float = maxf(0.0,float(sim.totals.get("grid_capacity",0)))
	var supply_upper_bound: float = known_available+storage_upper_bound+external_upper_bound
	if deficit>.01 and unknown_count==0 and supply_upper_bound+.01<known_demand:
		causes.push_front(_item("available_supply","critical","已核实可用电源不足","可信电源可用 %.1f MW；即使计入储能额定放电 %.1f MW 与公开外网容量 %.1f MW，总上限仍低于可信需求 %.1f MW。检查机组启动、储能和可调备用。" % [known_available,storage_upper_bound,external_upper_bound,known_demand],"global",-1,"inspect","完整可信设施观测与公开外网容量"))
	if deficit>.01 and unknown_count>0:
		causes.append(_item("unverified","info","部分运行状态待核实","%d 座设施缺少当前可信观测；不能据此断言故障或容量不足。可建立遥测或派现场队核实线路。" % unknown_count,"global",-1,"observe","观测覆盖情况"))
	if deficit>.01 and causes.is_empty():
		causes.append(_item("supply_capacity","warning","供给与交付需要核实","公开指标显示有缺额；比较可信可用出力、负荷与线路读数，避免仅按额定容量扩建。"))
	# Each item is rendered once, with known actionable problems before uncertainty.
	var unique: Array[Dictionary]=[]
	var seen: Dictionary={}
	for cause in causes:
		var key: String=str(cause.get("target_type",""))+":"+str(cause.get("target_id",-1))+":"+str(cause.get("action",""))
		if key in seen: continue
		seen[key]=true
		unique.append(cause)
	unique.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if _severity_order(str(a.severity))!=_severity_order(str(b.severity)): return _severity_order(str(a.severity))<_severity_order(str(b.severity))
		return str(a.get("action",""))=="connect" and str(b.get("action",""))!="connect")
	return {"served":served,"demand":demand,"deficit":deficit,"reliability":float(sim.totals.get("reliability",1)),
		"summary":"当前缺额 %.1f MW；按已知证据检查下列项目。" % deficit if deficit>.01 else "当前供电满足需求；关注备用与已知风险。",
		"causes":unique,"unknown_count":unknown_count}

static func jobs(sim: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for method in ["remote","field"]:
		var queue: Array = sim.digital.pending_commands if method=="remote" else sim.digital.field_jobs
		for command in queue:
			var facility: bool = str(command.get("kind",""))=="facility"
			var title: String = ("远程" if method=="remote" else "现场")+("设施设置" if facility else ("线路巡检" if command.get("kind","")=="patrol" else "线路开关"))
			result.append({"id":int(command.id),"command_id":int(command.id),"key":"digital:%s:%d" % [method,int(command.id)],"source":"数字控制工单","phase":"pending","method":method,"crew_active":method=="field","work_stage":"field",
				"target_type":"facility" if facility else "line","target_id":int(command.get("building_id",-1) if facility else command.get("line_id",-1)),
				"title":title,"remaining":float(command.remaining),"duration":float(command.get("duration",0)),"started_at":float(command.get("started_at",-1)),"message":"已受理，等待实际执行；远程到达时重新验证。" if method=="remote" else "现场队执行中，完成后查看回执。"})
	# Physical maintenance also occupies the same two field crews. Its timing is a
	# submitted work order, not hidden electrical or fault telemetry.
	for target in [[sim.buildings,"facility"],[sim.lines,"line"],[sim.digital.links,"communication"]]:
		for item in target[0]:
			if float(item.get("repair_remaining",0))<=.000001: continue
			result.append({"id":-int(item.id)-1000,"command_id":-int(item.id)-1000,"key":"repair:%s:%d" % [target[1],int(item.id)],"source":"现场抢修工单","phase":"pending","method":"field","crew_active":true,"work_stage":"work",
				"target_type":target[1],"target_id":int(item.id),"title":"设施检修" if target[1]=="facility" else ("线路抢修" if target[1]=="line" else "通信链路修复"),
				"remaining":float(item.repair_remaining),"duration":float(item.get("repair_duration",0)),"started_at":float(item.get("repair_started_at",-1)),"message":"现场作业中，完成后核对恢复状态。"})
	# Submitted maintenance orders are public records, including waiting jobs. A
	# waiting order has no known departure time and must never consume a crew lane.
	for job in sim.lifecycle.jobs:
		var stage: String=str(job.status)
		var remaining: float=float(job.travel_remaining)+float(job.work_remaining)
		result.append({"id":int(job.id),"command_id":int(job.id),"key":"lifecycle:%d" % int(job.id),"source":"资产检修工单",
			"phase":"queued" if stage=="queued" else "pending","method":"field","crew_active":stage in ["travel","work"],"work_stage":stage,
			"target_type":str(job.target_type),"target_id":int(job.target_id),"title":str(sim.lifecycle.ACTIONS[job.action].name),
			"remaining":remaining,"duration":0.0,"travel_remaining":float(job.travel_remaining),"work_remaining":float(job.work_remaining),"priority":int(job.priority),"queued_at":float(job.queued_at),
			"message":"等待空闲现场队；排队时长未定。" if stage=="queued" else ("现场队赶往设备，完成后查看回执。" if stage=="travel" else "现场作业中，完成后核对恢复状态。")})
	# Microgrid switching shares the same crew pool, but targets a partition. A
	# member facility is a navigable map target; the title retains partition ID.
	for grid in sim.customers.microgrids:
		var target_id: int=int(grid.members[0]) if not grid.members.is_empty() else -1
		var pending: Dictionary=grid.pending
		if not pending.is_empty():
			var method: String=str(pending.method)
			result.append({"id":int(grid.id),"command_id":int(grid.id),"key":"microgrid:%d:pending" % int(grid.id),"source":"微电网切换工单",
				"phase":"pending","method":method,"crew_active":method=="field","work_stage":"travel",
				"target_type":"facility","target_id":target_id,"title":"%s #%d · %s" % [str(grid.name),int(grid.id),"离网切换" if bool(pending.island) else "边界重联"],
				"remaining":float(pending.remaining),"duration":0.0,"message":str(grid.receipt)})
		elif str(grid.receipt)!="已登记，尚未离网":
			# The model stores the latest explicit receipt, without its original
			# method or timestamp. Preserve that boundary instead of inventing either.
			var message: String=str(grid.receipt)
			var phase: String="executed" if message.begins_with("已离网") or message=="边界重联完成" else ("rejected" if message.begins_with("切换被拒绝") else ("cancelled" if "作业取消" in message else "reported"))
			result.append({"id":int(grid.id),"command_id":int(grid.id),"key":"microgrid:%d:receipt" % int(grid.id),"source":"微电网最近回执",
				"phase":phase,"method":"microgrid","crew_active":false,"target_type":"facility","target_id":target_id,
				"title":"%s #%d · 切换回执" % [str(grid.name),int(grid.id)],"remaining":0.0,"message":message})
	var receipts: Array = sim.operation_receipts() if sim.has_method("operation_receipts") else []
	for index in range(receipts.size()-1,-1,-1):
		var receipt: Dictionary = receipts[index]
		if str(receipt.get("phase","")) not in ["executed","rejected"]: continue
		var action: String = str(receipt.get("action",""))
		result.append({"id":int(receipt.get("command_id",-1)),"command_id":int(receipt.get("command_id",-1)),"key":"digital:receipt:%s:%d:%d:%s" % [action,int(receipt.get("command_id",-1)),int(receipt.get("target_id",-1)),str(receipt.get("elapsed_hours",0))],"source":"操作执行回执","phase":str(receipt.phase),"crew_active":false,
			"method":str(receipt.get("method","field")),"target_type":"facility" if action=="facility" else "line", "target_id":int(receipt.get("target_id",-1)),
			"title":"设施设置" if action=="facility" else ("线路巡检" if action=="inspect" else "线路开关"),"remaining":0.0,
			"message":str(receipt.get("message","已完成。")),"elapsed_hours":float(receipt.get("elapsed_hours",0))})
	for index in range(sim.lifecycle.receipts.size()-1,-1,-1):
		var receipt: Dictionary=sim.lifecycle.receipts[index]
		var cancelled: bool=str(receipt.get("status",""))=="cancelled"
		result.append({"id":int(receipt.id),"command_id":int(receipt.id),"key":"lifecycle:%d:receipt" % int(receipt.id),"source":"资产检修回执",
			"phase":"cancelled" if cancelled else "executed","method":"field","crew_active":false,"target_type":str(receipt.target_type),"target_id":int(receipt.target_id),
			"title":str(sim.lifecycle.ACTIONS[receipt.action].name),"remaining":0.0,"elapsed_hours":float(receipt.finished_at),
			"message":"目标已移除，检修任务已取消。" if cancelled else "现场作业已完成；核对设备状态与供电结果。"})
	return result

static func facility_marker(sim: RefCounted, id: int) -> Dictionary:
	var observed: Dictionary = sim.facility_observation(id)
	var feedback: Dictionary=customer_feedback(sim,id)
	if not feedback.is_empty() and not bool(feedback.powered): return {"text":"!","color_key":"warning"}
	if not bool(observed.get("trusted",false)): return {"text":"?","color_key":"muted"}
	if float(observed.get("health",100))<=0: return {"text":"×","color_key":"critical"}
	if float(observed.get("demand",0))>float(observed.get("served",0))+.01: return {"text":"!","color_key":"warning"}
	return {"text":"","color_key":"normal"}
