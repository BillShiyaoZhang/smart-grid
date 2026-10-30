extends RefCounted
## Department views share evidence, never hidden simulation truth. Queries neither
## commission systems nor forecast, sample, settle, consume RNG, or submit work.
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
const LENSES := ["operations", "planning", "maintenance", "market", "assets", "customers", "digital"]
const TITLES := {"operations":"运行", "planning":"规划", "maintenance":"运维", "market":"市场", "assets":"资产", "customers":"客户", "digital":"数字"}
const PURPOSES := {"operations":"现在能否安全供电，先处理哪一项？", "planning":"下一阶段的容量、接入与备用如何准备？", "maintenance":"有限现场队和备件应该先派到哪里？", "market":"供电选择如何影响现金、价格和履约？", "assets":"哪些已知设备状态值得优先检修或更新？", "customers":"哪些用户受到影响，灵活需求是否可兑现？", "digital":"哪些数据和控制可信，哪里仍需现场核实？"}
const DEPTHS := ["beginner", "operator", "engineer"]

static func snapshot(sim: RefCounted, lens: String = "operations", depth: String = "operator") -> Dictionary:
	if lens not in LENSES: lens = "operations"
	if depth not in DEPTHS: depth = "operator"
	var result := {"lens":lens,"depth":depth,"title":TITLES[lens],"purpose":PURPOSES[lens],"kpis":[],"risks":[],"assets":[],"customers":[],"cross_lens":[]}
	if sim == null: return result
	var context := _context(sim)
	var outcomes := _global(context)
	result.kpis = _lens_kpis(sim, context, outcomes, lens)
	var candidates := _risks(sim, context)
	for risk in candidates:
		if _belongs(risk, lens) and result.risks.size() < 5: result.risks.append(risk.duplicate(true))
	var linked: Array[String] = []
	for risk in candidates:
		var owner: String = str(risk.lens)
		if owner == lens or owner in linked: continue
		var link: Dictionary = risk.duplicate(true)
		link.action_label = "转到" + str(TITLES[owner]) + "核对处置"
		result.cross_lens.append(link)
		linked.append(owner)
		if linked.size() == 3: break
	result.assets = context.assets.duplicate(true)
	result.customers = context.customers.duplicate(true)
	return result

static func global_kpis(sim: RefCounted) -> Array[Dictionary]:
	return [] if sim == null else _global(_context(sim))

static func _context(sim: RefCounted) -> Dictionary:
	var facilities: Array[Dictionary] = Presenter.facilities(sim)
	var lines: Array[Dictionary] = []
	for line in sim.lines:
		var observed: Dictionary = sim.line_observation(int(line.id))
		var confidence := _confidence(observed)
		var current := confidence in ["trusted", "field"]
		lines.append({"id":int(line.id),"a":int(line.a),"b":int(line.b),"capacity":float(line.get("capacity",0)),"confidence":confidence,"source":str(observed.get("reason","线路观测待核实")),"flow":observed.get("flow") if current else null,"health":observed.get("health") if current else null})
	var assets := _asset_rows(sim)
	var customers := _customer_rows(sim, facilities)
	var verified := 0
	var stale := 0
	var suspect := 0
	for row in facilities:
		if row.trusted: verified += 1
		elif row.visibility == "stale": stale += 1
		elif row.visibility == "suspect": suspect += 1
	var overloaded := 0
	var known_lines := 0
	for line in lines:
		if line.confidence in ["trusted", "field"]:
			known_lines += 1
			if line.flow != null and absf(float(line.flow)) > maxf(.001,float(line.capacity)): overloaded += 1
	var critical_outages := 0
	for row in customers:
		if row.critical and row.outage: critical_outages += 1
	var minimum: Variant = null
	var unhealthy := 0
	var unknown_assets := 0
	var current_assets := 0
	var health_confidence := "field"
	for row in assets:
		if row.confidence not in ["trusted", "field"] or row.health == null:
			unknown_assets += 1
			continue
		current_assets += 1
		if row.confidence == "trusted": health_confidence = "trusted"
		minimum = float(row.health) if minimum == null else minf(float(minimum),float(row.health))
		if float(row.health) < 60.0: unhealthy += 1
	var demand := maxf(0,float(sim.totals.get("demand",0)))
	var served := maxf(0,float(sim.totals.get("served",0)))
	return {"facilities":facilities,"lines":lines,"assets":assets,"customers":customers,"verified":verified,"stale":stale,"suspect":suspect,"known_lines":known_lines,"overloaded":overloaded,"critical_outages":critical_outages,"minimum_health":minimum,"health_confidence":health_confidence,"unhealthy":unhealthy,"unknown_assets":unknown_assets,"current_assets":current_assets,"demand":demand,"served":served,"deficit":maxf(0,demand-served),"net":float(sim.totals.get("income",0))-float(sim.totals.get("expenses",0)),"cash":float(sim.cash),"clean":float(sim.totals.get("renewable_supply_share",0))*100.0,"carbon":float(sim.totals.get("carbon",0))}

static func _kpi(id: String, label: String, value: Variant, unit: String, detail: String, source: String = "公开经营指标", confidence: String = "public", target_type: String = "global", target_id: int = -1) -> Dictionary:
	return {"id":id,"label":label,"value":value,"unit":unit,"detail":detail,"source":source,"confidence":confidence,"target_type":target_type,"target_id":target_id}

static func _global(c: Dictionary) -> Array[Dictionary]:
	return [
		_kpi("supply","供电",float(c.served)/float(c.demand)*100.0 if float(c.demand)>.000001 else 100.0,"%","已供 %.1f / 需求 %.1f MW · 缺额 %.1f MW" % [c.served,c.demand,c.deficit],"公开供需与供电反馈"),
		_kpi("reliability","运行安全",int(c.overloaded)+int(c.critical_outages),"项","已核实超载 %d 条 · 医院停电反馈 %d 处；未知线路不计为正常" % [c.overloaded,c.critical_outages],"当前可信线路观测与公开关键负荷反馈"),
		_kpi("economy","经营",c.net,"¥/h","运营净收益 · 现金 ¥%.0f；投资与贷款另见现金记录" % float(c.cash)),
		_kpi("carbon","清洁供电",c.clean,"%","实际可再生供电占比 · 当前排放 %.2f 吨/h" % float(c.carbon),"公开交付电量与排放汇总"),
		_kpi("asset","设备状态",c.minimum_health,"%","当前已核实最低健康；低于60%% %d 项 · 当前状态未知 %d 项" % [c.unhealthy,c.unknown_assets],"当前可信遥测或现场核实；未知不作零值", "unknown" if c.minimum_health == null else str(c.health_confidence)),
		_kpi("observability","可观测性",float(c.verified)/float(c.facilities.size())*100.0 if not c.facilities.is_empty() else null,"%","设施当前可信 %d / %d · 线路已核实 %d / %d · 过时 %d" % [c.verified,c.facilities.size(),c.known_lines,c.lines.size(),c.stale],"当前观测覆盖清单","public" if not c.facilities.is_empty() else "unknown")
	]

static func _outcome(outcomes: Array[Dictionary], id: String) -> Dictionary:
	for row in outcomes:
		if row.id == id: return row.duplicate(true)
	return {}

static func _lens_kpis(sim: RefCounted, c: Dictionary, outcomes: Array[Dictionary], lens: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Dictionary = {"operations":["supply","reliability","observability"],"planning":["supply","carbon","economy"],"maintenance":["asset","reliability"],"market":["economy"],"assets":["asset","observability"],"customers":["supply"],"digital":["observability"]}
	for id in ids[lens]: result.append(_outcome(outcomes,str(id)))
	var lifecycle: RefCounted = sim.get("lifecycle")
	var strategy: RefCounted = sim.get("strategy")
	var market: RefCounted = sim.get("market")
	if lens in ["operations","maintenance"]:
		result.append(_kpi("crews","现场队",sim.active_repairs(),"/2","包含抢修、巡检、设施设置、检修与微电网切换","已受理现场作业"))
	if lens in ["maintenance","assets"] and lifecycle != null:
		result.append(_kpi("spares","关键备件",int(lifecycle.spares),"件","资产管理%s；大修与更换需要备件" % ("已投运" if lifecycle.enabled else "尚未投运"),"公开库存"))
		var queued := 0
		for job in lifecycle.jobs:
			if job.get("status","") == "queued": queued += 1
		result.append(_kpi("maintenance_queue","待派检修",queued,"项","已受理但尚未出发的检修任务","检修工单"))
	if lens == "planning":
		result.append(_outcome(outcomes,"observability"))
		result.append(_kpi("planning_horizon","推演范围",24,"h","在发展工作台计算独立副本；这里只显示当前证据，不自动推演","推演工具口径"))
	if lens == "market":
		result.append(_kpi("cash","可用现金",c.cash,"¥","建设、维修与偿债都受实际现金约束","公开现金余额"))
		if market != null:
			result.append(_kpi("spot","现货价格",market.state.get("spot_price"),"¥/MWh","按实际交付和现有承诺结算","公开市场报价"))
			result.append(_kpi("retail","零售价格",market.state.get("retail_price"),"¥/MWh","电价影响客户负荷与满意度","已发布零售电价"))
		if strategy != null:
			var debt := 0.0
			for loan in strategy.state.get("loans",[]): debt += float(loan.get("principal",0))
			result.append(_kpi("debt","贷款本金",debt,"¥","贷款到账不作营业收入；本金与利息分别记录","已签贷款合同"))
	if lens == "customers":
		result.append(_kpi("critical_feedback","医院停电反馈",int(c.critical_outages),"处","关键负荷的公开供电反馈；不据此判断线路原因","用户供电反馈"))
		if market != null: result.append(_kpi("satisfaction","用户满意度",market.state.get("satisfaction"),"%","受实际供电与电价影响","公开客户经营指标"))
		var known_ev := 0.0
		var metered := 0
		var missing := 0
		for row in c.customers:
			if not row.get("metered",false): continue
			if row.ev_remaining_mwh == null: missing += 1
			else: known_ev += float(row.ev_remaining_mwh); metered += 1
		result.append(_kpi("ev_obligation","已知待充电量",known_ev if metered>0 else null,"MWh","仅计 %d 个可信电表；%d 个电表当前未知，未按零计算" % [metered,missing],"可信街区电表","trusted" if metered>0 else "unknown"))
	if lens in ["customers","operations"]:
		var reliability: RefCounted = sim.get("reliability_metrics")
		if reliability != null:
			var summary: Dictionary = reliability.report(sim).get("summary",{})
			var available := float(summary.get("elapsed_hours",0))>0 and int(summary.get("enrolled_points",0))>0
			var scope: String = "负荷点口径 · 窗口 %.1f h · 分母 %d 个累计纳入负荷点；不是居民户数" % [float(summary.get("elapsed_hours",0)),int(summary.get("enrolled_points",0))]
			result.append(_kpi("ens","累计失供电量",summary.get("ens_mwh") if available else null,"MWh",scope,"公开负荷供电结果的持久统计","public" if available else "unknown"))
			if lens == "customers":
				result.append(_kpi("saidi","平均停电时长",summary.get("saidi_minutes") if available else null,"分钟/点",scope,"累计失供点分钟 / 累计纳入负荷点","public" if available else "unknown"))
				result.append(_kpi("saifi","平均停电次数",summary.get("saifi") if available else null,"次/点",scope,"持续失供事件数 / 累计纳入负荷点；98%供电阈值","public" if available else "unknown"))
	if lens == "digital":
		result.append(_kpi("line_visibility","线路可核实",c.known_lines,"条","%d 条线路中当前核实 %d 条；待核实不是健康" % [c.lines.size(),c.known_lines],"当前线路观测清单"))
		var detected := 0
		var digital: RefCounted = sim.get("digital")
		if digital != null:
			for event in digital.incidents:
				if event.get("detected",false) and event.get("status","") == "active": detected += 1
			result.append(_kpi("detected_incidents","已检测事件",detected,"项","只统计已检测且仍在处置的事件","已检测安全告警"))
			result.append(_kpi("remote_pending","远程在途",digital.pending_commands.size(),"项","到达时重新验证，已排队不等于已生效","已受理命令队列"))
	return result

static func _confidence(observed: Dictionary) -> String:
	var visibility: String = str(observed.get("visibility","unknown"))
	if visibility == "verified": return "trusted"
	if visibility in ["field","patrol"]: return "field"
	if visibility == "stale": return "stale"
	return "unknown"

static func _asset_rows(sim: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var identities: Dictionary = {}
	var near_hospital: Dictionary = {}
	var near_customer: Dictionary = {}
	for b in sim.buildings: identities[int(b.id)] = {"name":str(b.name),"kind":str(b.kind),"cell":b.cell}
	for line in sim.lines:
		for pair in [[int(line.a),int(line.b)],[int(line.b),int(line.a)]]:
			var other: Dictionary = identities.get(pair[1],{})
			if other.get("kind","") == "hospital": near_hospital[pair[0]] = true
			if other.get("kind","") in ["home","factory","hospital"]: near_customer[pair[0]] = true
	var lifecycle: RefCounted = sim.get("lifecycle")
	var reported: Array = lifecycle.report(sim).get("assets",[]) if lifecycle != null else []
	for row in reported:
		var kind: String = str(row.target_type)
		var id: int = int(row.id)
		var identity: Dictionary = identities.get(id,{}) if kind == "facility" else {}
		var observed: Dictionary = sim.facility_observation(id) if kind == "facility" else sim.line_observation(id)
		var confidence := _confidence(observed)
		var health: Variant = observed.get("health") if confidence in ["trusted","field"] else null
		var source := str(observed.get("reason","状态待核实"))
		if health == null and float(row.get("inspected_at",-1)) >= 0 and row.get("health") != null:
			health = row.health
			confidence = "stale"
			source = "历史巡检记录；不代表当前状态"
		var criticality := 1
		var consequence := "一般设施；仅按公开用途归类"
		if kind == "facility":
			if identity.get("kind","") == "hospital" or near_hospital.has(id):
				criticality = 3
				consequence = "医院或其相邻设施；关键负荷后果代理"
			elif identity.get("kind","") in ["home","factory","substation"] or near_customer.has(id):
				criticality = 2
				consequence = "用户负荷或其相邻供电设施；服务后果代理"
		else:
			var line: Dictionary = sim.get_line(id)
			var a: Dictionary = identities.get(int(line.get("a",-1)),{})
			var b: Dictionary = identities.get(int(line.get("b",-1)),{})
			if a.get("kind","") == "hospital" or b.get("kind","") == "hospital":
				criticality = 3
				consequence = "线路端点含医院；关键负荷后果代理"
			elif a.get("kind","") in ["home","factory","substation"] or b.get("kind","") in ["home","factory","substation"]:
				criticality = 2
				consequence = "线路端点含用户或变电站；服务后果代理"
		result.append({"id":id,"name":str(identity.get("name",row.get("name","设备"))),"kind":str(identity.get("kind","line")),"target_type":kind,"target_id":id,"cell":identity.get("cell",Vector2i(-1,-1)),"health":health,"confidence":confidence,"source":source,"criticality":[.2,.6,1.0][criticality-1],"criticality_level":criticality,"criticality_label":["一般设施","用户与输配电","关键负荷邻接"][criticality-1],"criticality_detail":consequence+"；仅按公开物理拓扑与用途，不推断备用通路或实际失供。","consequence":consequence,"criticality_source":"公开物理拓扑与客户类型；不是实际失效概率，也不推断备用通路","inspected_at":float(row.get("inspected_at",-1)),"soh":row.get("soh"),"age_hours":float(row.get("age_hours",0)),"current_verified":confidence in ["trusted","field"]})
	# Keep identity stable regardless of observation arrival or dictionary ordering.
	result.sort_custom(func(a: Dictionary,b: Dictionary): return str(a.target_type)<str(b.target_type) if a.target_type!=b.target_type else int(a.id)<int(b.id))
	return result

static func _customer_rows(sim: RefCounted, facilities: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var metered: Dictionary = {}
	var model: RefCounted = sim.get("customers")
	if model != null:
		for row in model.report(sim).get("customers",[]): metered[int(row.id)] = row
	for facility in facilities:
		if facility.kind not in ["home","factory","hospital"]: continue
		var id: int = int(facility.id)
		var feedback := Presenter.customer_feedback(sim,id)
		if feedback.is_empty(): continue
		var row: Dictionary = {"id":id,"target_id":id,"target_type":"facility","name":facility.name,"kind":facility.kind,"cell":facility.cell,"critical":facility.kind=="hospital","powered":feedback.get("powered"),"outage":not bool(feedback.get("powered",true)),"affected":not bool(feedback.get("powered",true)),"feedback":str(feedback.get("text","供电反馈待核实")),"source":"公开用户供电反馈","confidence":"public","served":facility.get("served"),"demand":facility.get("demand"),"metered":false,"meter_confidence":"unknown","energy_mwh":null,"ev_remaining_mwh":null,"shift_debt_mwh":null,"fatigue":null,"ev_mw":0.0,"deadline_hour":7.0,"controllable":false}
		if metered.has(id):
			var meter: Dictionary = metered[id]
			row.metered = bool(meter.get("metered",false))
			row.meter_confidence = "trusted" if meter.get("telemetry_visibility","") == "verified" else ("stale" if meter.get("telemetry_visibility","") == "stale" else "unknown")
			for key in ["energy_mwh","ev_remaining_mwh","shift_debt_mwh","fatigue"]: row[key] = meter.get(key) if row.meter_confidence == "trusted" else null
			row.ev_mw = float(meter.get("ev_mw",0))
			row.deadline_hour = float(meter.get("deadline_hour",7))
			row.controllable = bool(meter.get("controllable",false))
		result.append(row)
	return result

static func _risk(id: String, severity: String, title: String, detail: String, source: String, confidence: String, lens: String, action: String, consequence: String, urgency: String = "尽快核实", target_type: String = "global", target_id: int = -1, order: int = 8) -> Dictionary:
	return {"id":id,"severity":severity,"title":title,"detail":detail,"source":source,"confidence":confidence,"target_type":target_type,"target_id":target_id,"action":action,"lens":lens,"consequence":consequence,"urgency":urgency,"_order":order}

static func _risks(sim: RefCounted, c: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for customer in c.customers:
		if customer.outage:
			rows.append(_risk("customer_%d" % customer.id,"critical",str(customer.name)+" · "+("医院" if customer.critical else "用户")+"报告停电","供电结果已知，设备与线路原因仍需可信观测或巡检。","公开用户供电反馈","public","customers","inspect","关键服务受到影响" if customer.critical else "用户失供及补偿持续增加","立即处置","facility",int(customer.id),0 if customer.critical else 1))
	var diagnosis: Dictionary = Presenter.diagnosis(sim)
	var causes: Array = Presenter.alerts(sim)
	causes.append_array(diagnosis.get("causes",[]))
	var seen: Dictionary = {}
	for cause in causes:
		var id := str(cause.get("id",""))
		if seen.has(id) or id == "unverified" or id.begins_with("customer_outage_") or id.begins_with("outage_"): continue
		seen[id] = true
		var lens := "operations"
		var order := 5
		var consequence := "影响当前交付与备用余量"
		if id.begins_with("line_load_"):
			order = 2
			consequence = "持续超载可能触发本地保护并减少供电"
		elif "fault" in id:
			lens = "maintenance"; order = 3; consequence = "已确认的损伤需要维修与恢复核对"
		elif id.begins_with("voltage_") or id.begins_with("transformer_") or id.begins_with("unconnected_") or id == "available_supply":
			lens = "planning"; order = 4; consequence = "容量、接入或供电质量限制实际交付"
		elif str(cause.get("action","")) in ["observe","security"] or id == "unverified":
			lens = "digital"; order = 9; consequence = "信息不足会阻止可信诊断与远程处置"
		var target_type := str(cause.get("target_type","global"))
		var target_id := int(cause.get("target_id",-1))
		var confidence := "public"
		if target_type == "line": confidence = _confidence(sim.line_observation(target_id))
		elif target_type == "facility" and str(cause.get("action","")) != "connect": confidence = _confidence(sim.facility_observation(target_id))
		if str(cause.get("action","")) == "security": confidence = "public"
		if id == "available_supply": confidence = "trusted"
		if id == "unverified": confidence = "unknown"
		rows.append(_risk(id,str(cause.get("severity","info")),str(cause.get("title","待核实事项")),str(cause.get("detail","")),str(cause.get("source","公开运行指标")),confidence,lens,str(cause.get("action","inspect")),consequence,"立即处置" if cause.get("severity","") == "critical" else "尽快核实",target_type,target_id,order))
	_finance_risks(sim,c,rows)
	_asset_risks(c,rows)
	var lifecycle: RefCounted = sim.get("lifecycle")
	if lifecycle != null and lifecycle.enabled:
		var queued := 0
		for job in lifecycle.jobs:
			if job.get("status","") == "queued": queued += 1
		if queued>0 and sim.active_repairs()>=2:
			rows.append(_risk("crew_queue","warning","现场队已满 · %d项检修等待" % queued,"调整尚未出发任务的优先级，核对关键负荷处置顺序。","已受理现场工单","public","maintenance","jobs","关键任务可能等待队伍释放","当前班次","global",-1,6))
		if int(lifecycle.spares)<1:
			rows.append(_risk("spares","warning","关键备件不足","当前库存为零；大修和更换提交前需要采购。","公开备件库存","public","maintenance","spares","已确认故障可能无法安排大修","当前班次","global",-1,7))
	_customer_deadlines(sim,c,rows)
	if int(c.facilities.size())>int(c.verified):
		rows.append(_risk("observation_gap","warning" if float(c.deficit)>.01 else "info","%d座设施当前读数待核实" % (int(c.facilities.size())-int(c.verified)),"当前可信 %d 座，过时 %d 座。空白不是零，也不能由拓扑推断故障。" % [c.verified,c.stale],"观测覆盖清单","unknown","digital","observe","未知状态会影响处置选择和规划可信度","尽快核实","global",-1,9))
	rows.sort_custom(func(a: Dictionary,b: Dictionary):
		if int(a._order)!=int(b._order): return int(a._order)<int(b._order)
		if _severity(str(a.severity))!=_severity(str(b.severity)): return _severity(str(a.severity))<_severity(str(b.severity))
		return str(a.id)<str(b.id))
	for row in rows: row.erase("_order")
	return rows

static func _finance_risks(sim: RefCounted, c: Dictionary, rows: Array[Dictionary]) -> void:
	if float(c.cash)<0:
		rows.append(_risk("cash_negative","critical","现金余额为负","现金 ¥%.0f；先核对运营支出、建设与偿债计划。" % float(c.cash),"公开现金余额","public","market","finance","维修和新增投资可能无法支付","立即处置","global",-1,4))
	elif float(c.net)<-.01:
		var runway := float(c.cash)/-float(c.net)
		rows.append(_risk("operating_loss","warning","运营净收益为负","净支出 ¥%.0f/h；按当前不变支出约可维持 %.1f h，此为静态换算，不是预测。" % [-float(c.net),runway],"当前公开收支与现金余额","public","market","finance","持续净支出会压缩建设与恢复预算","当前班次","global",-1,6 if runway<24 else 10))
	var strategy: RefCounted = sim.get("strategy")
	if strategy == null: return
	for loan in strategy.state.get("loans",[]):
		var remaining := float(loan.get("due",0))-float(sim.elapsed_hours)
		if remaining>24: continue
		rows.append(_risk("loan_%d" % int(loan.id),"critical" if remaining<=0 else "warning","贷款 #%d · %s" % [int(loan.id),"已到期" if remaining<=0 else "24小时内到期"],"本金 ¥%.0f · 距到期 %.1f h；逾期利息增加。" % [float(loan.get("principal",0)),remaining],"已签贷款合同","public","market","finance","到期债务占用可用于供电和抢修的现金","立即处置" if remaining<=0 else "24小时内","global",-1,5 if remaining<=0 else 8))
	for project in strategy.state.get("projects",[]):
		if project.get("status","") != "blocked": continue
		rows.append(_risk("project_%d" % int(project.id),"warning","工程 #%d · 接入受阻" % int(project.id),"核对工程端点和取消退款选项；未投运工程不计为可用容量。","工程进度回执","public","planning","project","计划容量不能按期投运","当前班次","global",-1,7))

static func _asset_risks(c: Dictionary, rows: Array[Dictionary]) -> void:
	for asset in c.assets:
		if asset.health == null or float(asset.health)>=60: continue
		var current: bool = asset.confidence in ["trusted","field"]
		var title: String = str(asset.name)+(" · 健康状态偏低" if current else " · 历史低健康待复核")
		var detail: String = "已知健康 %.0f%%；%s。%s" % [float(asset.health),asset.consequence,"按实际停运影响和队伍资源安排检修。" if current else "该巡检已过时，先核实当前状态。"]
		rows.append(_risk("asset_%s_%d" % [asset.target_type,asset.id],"warning",title,detail,str(asset.source),str(asset.confidence),"assets","maintenance" if current else "observe",str(asset.consequence),"当前班次" if current else "尽快核实",str(asset.target_type),int(asset.id),6 if current and int(asset.criticality_level)==3 else 8 if current else 11))

static func _customer_deadlines(sim: RefCounted, c: Dictionary, rows: Array[Dictionary]) -> void:
	for customer in c.customers:
		if customer.ev_remaining_mwh == null or float(customer.ev_remaining_mwh)<=.001 or float(customer.ev_mw)<=0: continue
		var remaining := fposmod(float(customer.deadline_hour)-float(sim.time_hours),24.0)
		if remaining<.000001: remaining=24.0
		var need := float(customer.ev_remaining_mwh)/float(customer.ev_mw)
		if remaining>2.0 and need<=remaining: continue
		rows.append(_risk("charging_%d" % int(customer.id),"warning",str(customer.name)+" · 充电义务接近期限","可信待充 %.1f MWh · 截止前 %.1f h · 按额定功率至少 %.1f h；实际供电可能延长。" % [customer.ev_remaining_mwh,remaining,need],"当前可信街区电表与用户充电合同","trusted","customers","customer","到期未完成电量会产生客户补偿","期限前核对","facility",int(customer.id),6))

static func _belongs(risk: Dictionary, lens: String) -> bool:
	if risk.lens == lens: return true
	if lens == "operations": return str(risk.severity)=="critical" or str(risk.id) in ["crew_queue","storm"]
	if lens == "planning": return str(risk.id) in ["supply","observation_gap","operating_loss","storm","available_supply"]
	if lens == "maintenance": return str(risk.id).begins_with("asset_") or (risk.lens == "customers" and risk.action == "inspect")
	return false

static func _severity(value: String) -> int:
	return 0 if value == "critical" else (1 if value == "warning" else 2)
