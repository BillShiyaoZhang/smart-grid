extends RefCounted
## Historical archetypes and deliberately compressed operating constraints.
## All figures are game balance values, not equipment specifications. In
## particular converter hosting is an aggregate stability margin, not an AC solve.

const ERAS := [
	{"name":"电气黎明", "years":"1880—1910", "description":"爱迪生式本地直流、交流变压与蒸汽机；供电距离决定城市尺度。"},
	{"name":"区域互联", "years":"1910—1950", "description":"大型汽轮机、水电与继电保护，让分散的小电网连成区域。"},
	{"name":"大电力时代", "years":"1950—1990", "description":"核能、抽蓄与跨区输电；规模经济也带来重资产与慢启停。"},
	{"name":"数字调度", "years":"1990—2010", "description":"联合循环、电力电子与可信遥测，把设备能力变成调度选择。"},
	{"name":"灵活电网", "years":"2010—2040", "description":"分布式储能、液流与氢储能，优化功率、时长和效率的取舍。"},
	{"name":"未来实验室", "years":"2040+ · 推演", "description":"先进冷却、长时储能与假想聚变；未来技术依旧需要基础设施。"}
]

const EXTRA_CATALOG := {
	"dc_dynamo":{"name":"直流发电坊", "price":10000.0, "capacity":7.0, "demand":0.0, "era":0, "description":"早期本地电源。便宜、即开即用，但接入远距离线路会严重降额，燃料昂贵。", "color":"cba077"},
	"steam":{"name":"往复式蒸汽站", "price":24000.0, "capacity":17.0, "demand":0.0, "era":0, "description":"交流时代蒸汽电源；预热 1 小时，最低稳定负荷 35%，高碳高燃料费。", "color":"b68f78"},
	"coal":{"name":"煤炭汽轮机组", "price":68000.0, "capacity":48.0, "demand":0.0, "era":1, "description":"低燃料成本的重型机组；预热 3 小时、缓慢爬坡、45% 最低负荷，不能随夜间需求骤降。", "color":"99928b"},
	"hydro":{"name":"径流水电站", "price":62000.0, "capacity":30.0, "demand":0.0, "era":1, "description":"只能建于东北水系（x≥18、y≤5）。季节来水限制出力；下泄不足 25% 要支付生态补偿，不能免费拦水。", "color":"78b3bc"},
	"cooling":{"name":"循环冷却设施", "price":23000.0, "capacity":0.0, "demand":1.0, "era":2, "description":"同电气岛为一座核能机组冷却。湿冷高效却怕炎热缺水；干冷多耗电、降低机组功率。", "color":"90bfcd"},
	"academy":{"name":"电力工程学院", "price":28000.0, "capacity":0.0, "demand":0.6, "era":2, "description":"同电气岛提供 8 个高级运行岗位。核能占 6、聚变占 10；岗位不能重复使用，学院有持续工资。", "color":"e0c286"},
	"nuclear":{"name":"压水堆核电站", "price":180000.0, "capacity":90.0, "demand":0.0, "era":2, "description":"需要同岛冷却设施与 6 个技术岗位。启动 8 小时，缓慢爬坡，55% 最低稳定负荷；弃电仍支付热功率燃料费。", "color":"c1d3b1"},
	"pumped_storage":{"name":"抽水蓄能电站", "price":64000.0, "capacity":24.0, "energy":180.0, "demand":0.0, "era":2, "description":"只能建于东部山地（x≥26、y≥24）。长时储能，充放电效率各 86%；建设贵，不会产生免费电力。", "color":"7eafbf"},
	"condenser":{"name":"同步调相机", "price":24000.0, "capacity":0.0, "demand":0.8, "era":2, "description":"简化稳定裕度模型：同岛 HVDC 可用输送上限 +15%，不改变线路热容量。自身耗电并有维护费。", "color":"c6b2d3"},
	"hvdc":{"name":"高压直流换流站", "price":82000.0, "capacity":52.0, "demand":1.2, "era":3, "description":"52 MW 大容量市场联络接口，同岛调相机提高 15% 稳定接入上限。换流器有用电与维护费，仍需本地线路承载。", "color":"79a5c8"},
	"ccgt":{"name":"燃气联合循环", "price":72000.0, "capacity":44.0, "demand":0.0, "era":3, "description":"比普通燃气高效，启动需 1 小时、有 20% 最低负荷；不能取代快速调峰机组。", "color":"98bfa8"},
	"flow_battery":{"name":"液流储能站", "price":58000.0, "capacity":12.0, "energy":120.0, "demand":0.35, "era":4, "description":"长时低功率储能，充放电效率各 88%；大能量罐无法解决瞬时功率瓶颈。", "color":"b39abf"},
	"community_battery":{"name":"社区分布式储能", "price":14500.0, "capacity":5.0, "energy":15.0, "demand":0.0, "era":4, "description":"小容量、靠近负荷部署。削峰策略需可信通信与软件；失联退回本地保底，不会远程协同。", "color":"add4a8"},
	"hydrogen":{"name":"电氢长时储能", "price":92000.0, "capacity":18.0, "energy":360.0, "demand":0.8, "era":4, "description":"巨大的跨日容量，充放电效率各 65%；电解—储氢—发电损耗明显，只适合低价弃电。", "color":"b7d3d7"},
	"thermal_storage":{"name":"热储能发电站", "price":48000.0, "capacity":12.0, "energy":96.0, "demand":0.3, "era":5, "description":"以廉价大储罐换较低电回收率，充放效率各 72%；适合富余电力，无法凭空提高收益。", "color":"dcb392"},
	"fusion":{"name":"聚变示范堆", "price":420000.0, "capacity":160.0, "demand":0.0, "era":5, "description":"假想未来技术。需两套同岛冷却与 10 个岗位，启动 12 小时、65% 最低负荷、昂贵固定运维。", "color":"9cdad2"}
}

const TECHNOLOGIES := {
	"dc_basics":{"name":"本地直流供电", "era":0, "branch":"发电", "cost":0.0, "hours":0.0, "requires":[], "unlocks":["dc_dynamo"], "description":"初始能力。低门槛、短距离、高运行费；早期城市围绕电站生长。"},
	"ac_systems":{"name":"交流与变压器", "era":0, "branch":"输配电", "cost":8500.0, "hours":1.0, "requires":["dc_basics"], "unlocks":["steam"], "description":"蒸汽机组进入交流网络，摆脱直流发电坊的近距离限制。"},
	"turbines":{"name":"蒸汽汽轮机", "era":1, "branch":"发电", "cost":16000.0, "hours":2.0, "requires":["ac_systems"], "unlocks":["coal","gas"], "description":"更大的规模、更低的边际成本，也需要提前安排预热与最小出力。历史开局同时开放快速燃气备用。"},
	"hydraulics":{"name":"水轮机与生态水文", "era":1, "branch":"发电", "cost":18000.0, "hours":2.0, "requires":["ac_systems"], "unlocks":["hydro"], "description":"利用山地来水。玩家选择生态下泄比例，枯水期不能依靠额定容量。"},
	"protection":{"name":"继电保护协调", "era":1, "branch":"稳定", "cost":11000.0, "hours":1.5, "requires":["ac_systems"], "unlocks":[], "description":"解锁保护裕度控制：稳健保护更早跳闸，紧急运行容许更多热积累但加速老化。"},
	"regional_planning":{"name":"区域负荷规划", "era":1, "branch":"运营", "cost":12000.0, "hours":1.5, "requires":["ac_systems"], "unlocks":["battery","intertie"], "description":"解锁本地储能保留电量设置；把紧急备用与日常售电分开规划。历史开局开放早期储能与市场联络。"},
	"nuclear_science":{"name":"核科学与运行人才", "era":2, "branch":"人才", "cost":26000.0, "hours":3.0, "requires":["turbines","protection"], "unlocks":["academy"], "description":"培养高级运行岗位。人才是同电气岛的稀缺配额，需要持续工资。"},
	"thermal_cooling":{"name":"大型循环冷却", "era":2, "branch":"配套", "cost":18000.0, "hours":2.0, "requires":["hydraulics","turbines"], "unlocks":["cooling"], "description":"湿冷节电但受夏季水资源约束。每套冷却设施只能支撑有限核热负荷。"},
	"reactor_engineering":{"name":"压水堆工程", "era":2, "branch":"发电", "cost":52000.0, "hours":5.0, "requires":["nuclear_science","thermal_cooling"], "unlocks":["nuclear"], "description":"基荷电源。只有配齐冷却、人员、消纳网络，装机潜力才变成实际供电。"},
	"pumped_hydro":{"name":"抽水蓄能", "era":2, "branch":"储能", "cost":22000.0, "hours":2.5, "requires":["hydraulics","regional_planning"], "unlocks":["pumped_storage"], "description":"利用高差存储能量。低价时充电、高峰时放电，往返损耗与地形限制始终存在。"},
	"reactive_support":{"name":"同步稳定支撑", "era":2, "branch":"稳定", "cost":17000.0, "hours":2.0, "requires":["protection","turbines"], "unlocks":["condenser"], "description":"旋转设备改善同岛 HVDC 换流器稳定接入上限，但需要额外用电与维护；不改变线路热容量。"},
	"scada":{"name":"SCADA 调度接口", "era":3, "branch":"数字", "cost":14000.0, "hours":2.0, "requires":["protection"], "unlocks":["solar","wind","sensor","control","relay","soc"], "description":"建立储能分时控制接口，是协同软件的研究前置。历史开局开放现代风光与数字设施；实际协同还需独立可信通信与遥测研究。"},
	"power_electronics":{"name":"电力电子换流", "era":3, "branch":"输配电", "cost":33000.0, "hours":3.0, "requires":["reactive_support","scada"], "unlocks":["hvdc"], "description":"连接大容量跨区市场；换流站不能代替本地电缆，容量越大越需检查瓶颈。"},
	"combined_cycle":{"name":"燃气联合循环", "era":3, "branch":"发电", "cost":27000.0, "hours":2.5, "requires":["turbines","scada"], "unlocks":["ccgt"], "description":"提高燃气效率，代价是更慢启动与最低负荷；保留快速备用依然有价值。"},
	"dry_cooling":{"name":"空冷与节水运行", "era":3, "branch":"配套", "cost":16000.0, "hours":2.0, "requires":["thermal_cooling"], "unlocks":[], "description":"解锁冷却设施干冷模式。降低缺水风险，增加辅机耗电并降低热机净出力。"},
	"storage_chemistry":{"name":"液流电池与储罐", "era":4, "branch":"储能", "cost":26000.0, "hours":3.0, "requires":["scada","regional_planning"], "unlocks":["flow_battery"], "description":"把能量罐与功率堆分开；长时容量不代表更大瞬时功率。"},
	"distributed_energy":{"name":"分布式储能接入", "era":4, "branch":"配电", "cost":20000.0, "hours":2.0, "requires":["scada","regional_planning"], "unlocks":["community_battery"], "description":"把小储能放在负荷附近；它们各有电量与功率限制，需要分别配置。"},
	"smart_storage":{"name":"储能协同与削峰", "era":4, "branch":"数字", "cost":24000.0, "hours":3.0, "requires":["distributed_energy","storage_chemistry"], "unlocks":[], "description":"解锁削峰窗口。只有可信可达的控制路径才能执行，否则回退本地自动保供。"},
	"electrolysis":{"name":"电解制氢", "era":4, "branch":"储能", "cost":30000.0, "hours":3.0, "requires":["power_electronics","storage_chemistry"], "unlocks":["hydrogen"], "description":"将富余电力跨日存储。低往返效率使频繁套利可能得不偿失。"},
	"flexible_thermal":{"name":"柔性热机控制", "era":4, "branch":"运营", "cost":22000.0, "hours":2.5, "requires":["combined_cycle","scada"], "unlocks":[], "description":"解锁灵活运行档。热机爬坡更快、最低负荷更低，但增加燃料费和固定维护费。"},
	"advanced_materials":{"name":"高温材料与热储能", "era":5, "branch":"储能", "cost":35000.0, "hours":4.0, "requires":["electrolysis","thermal_cooling"], "unlocks":["thermal_storage"], "description":"以低成本储罐换较差的电回收率；长时备用的另一种经济选择。"},
	"advanced_cooling":{"name":"先进热管理", "era":5, "branch":"配套", "cost":38000.0, "hours":4.0, "requires":["dry_cooling","advanced_materials"], "unlocks":[], "description":"解锁强化冷却档。每套设施支撑更大热负荷，但辅机需求与固定运维显著增加。"},
	"plasma_control":{"name":"等离子体控制实验", "era":5, "branch":"数字", "cost":60000.0, "hours":5.0, "requires":["reactor_engineering","smart_storage","power_electronics"], "unlocks":[], "description":"为假想聚变建立控制基础。实验本身不产生电力，必须继续建设完整示范工程。"},
	"fusion_engineering":{"name":"聚变示范工程", "era":5, "branch":"发电", "cost":95000.0, "hours":7.0, "requires":["plasma_control","advanced_cooling"], "unlocks":["fusion"], "description":"未来推演的高潜力电源。巨大前期投资、冷却、人才、慢启停和最低负荷仍是约束。"}
}

const LEGACY_KINDS := ["gas","solar","wind","battery","substation","home","factory","hospital","sensor","control","relay","soc","intertie"]
const HERITAGE_UNLOCKS := {"gas":"turbines", "solar":"scada", "wind":"scada", "battery":"regional_planning", "sensor":"scada", "control":"scada", "relay":"scada", "soc":"scada", "intertie":"regional_planning"}
const STARTUP := {"dc_dynamo":0.0, "steam":1.0, "coal":3.0, "hydro":0.0, "gas":0.0, "ccgt":1.0, "nuclear":8.0, "fusion":12.0}
const RAMP := {"dc_dynamo":100.0, "steam":8.0, "coal":5.0, "hydro":100.0, "gas":1000.0, "ccgt":15.0, "nuclear":5.0, "fusion":6.0}
const MINIMUM := {"dc_dynamo":0.0, "steam":0.35, "coal":0.45, "hydro":0.0, "gas":0.0, "ccgt":0.20, "nuclear":0.55, "fusion":0.65}
const FUEL := {"dc_dynamo":108.0, "steam":85.0, "coal":43.0, "hydro":0.0, "gas":68.0, "ccgt":49.0, "nuclear":17.0, "fusion":22.0}
const CARBON := {"dc_dynamo":0.85, "steam":1.0, "coal":0.88, "hydro":0.0, "gas":0.38, "ccgt":0.25, "nuclear":0.0, "fusion":0.0}
const EFFICIENCY := {"battery":0.94, "pumped_storage":0.86, "flow_battery":0.88, "community_battery":0.95, "hydrogen":0.65, "thermal_storage":0.72}
const UPKEEP := {"dc_dynamo":4.0, "steam":20.0, "coal":65.0, "hydro":38.0, "cooling":32.0, "academy":110.0, "nuclear":240.0, "pumped_storage":35.0, "condenser":55.0, "hvdc":85.0, "ccgt":60.0, "flow_battery":24.0, "community_battery":5.0, "hydrogen":58.0, "thermal_storage":28.0, "fusion":650.0}

var unlocked: Array[String] = ["dc_basics"]
var project := ""
var remaining_hours := 0.0
var heritage := false

func reset() -> void:
	unlocked.assign(["dc_basics"])
	project = ""
	remaining_hours = 0.0
	heritage = false

func has_technology(id: String) -> bool:
	return id in unlocked

func building_era(kind: String) -> int:
	if EXTRA_CATALOG.has(kind):
		return int(EXTRA_CATALOG[kind].era)
	if HERITAGE_UNLOCKS.has(kind):
		return int(TECHNOLOGIES[HERITAGE_UNLOCKS[kind]].era)
	return 0

func research(sim: RefCounted, id: String) -> Dictionary:
	if not TECHNOLOGIES.has(id):
		return _result(false,"未知研究项目。")
	if id in unlocked:
		return _result(false,"这项技术已经掌握。")
	if not project.is_empty():
		return _result(false,"研究团队正在进行「%s」。" % TECHNOLOGIES[project].name)
	var tech: Dictionary = TECHNOLOGIES[id]
	for prerequisite in tech.requires:
		if prerequisite not in unlocked:
			return _result(false,"需要先完成「%s」。" % TECHNOLOGIES[prerequisite].name)
	if float(sim.cash) < float(tech.cost):
		return _result(false,"研究资金不足。")
	sim.cash -= float(tech.cost)
	project = id
	remaining_hours = float(tech.hours)
	return _result(true,"「%s」研究启动，需 %.1f 游戏小时。" % [tech.name,tech.hours])

func can_build(kind: String) -> Dictionary:
	if kind in LEGACY_KINDS:
		if heritage and HERITAGE_UNLOCKS.has(kind) and not has_technology(str(HERITAGE_UNLOCKS[kind])):
			return _result(false,"历史开局需要先研究「%s」。" % TECHNOLOGIES[HERITAGE_UNLOCKS[kind]].name)
		return _result(true,"现有设施技术可用。")
	for id in unlocked:
		if kind in TECHNOLOGIES[id].unlocks:
			return _result(true,"技术已掌握。")
	for id in TECHNOLOGIES:
		if kind in TECHNOLOGIES[id].unlocks:
			return _result(false,"先研究「%s」。" % TECHNOLOGIES[id].name)
	return _result(false,"未知设施。")

func can_place(kind: String, cell: Vector2i) -> Dictionary:
	if kind == "hydro" and (cell.x < 18 or cell.y > 5):
		return _result(false,"径流水电需要东北水系（x≥18、y≤5）。")
	if kind == "pumped_storage" and (cell.x < 26 or cell.y < 24):
		return _result(false,"抽水蓄能需要东部山地（x≥26、y≥24）。")
	return _result(true,"选址可用。")

func initialize_building(b: Dictionary) -> void:
	var defaults := {"enabled":true, "cooling_mode":"wet", "storage_mode":"auto", "reserve_soc":0.0,
		"peak_hour":17.0, "environmental_release":0.25, "flexible_mode":false, "boost_cooling":false,
		"protection_margin":1.0, "ramp_mw":0.0, "startup_remaining":float(STARTUP.get(b.kind,0.0)), "running_hours":0.0}
	for key in defaults:
		if not b.has(key):
			b[key] = defaults[key]

func configure(sim: RefCounted, id: int, settings: Dictionary) -> Dictionary:
	var b: Dictionary = sim.get_building(id)
	if b.is_empty():
		return _result(false,"设施不存在。")
	# Validate the complete draft before applying any of it.
	for key in settings:
		var value: Variant = settings[key]
		match str(key):
			"enabled":
				if not value is bool:
					return _result(false,"运行开关需要布尔值。")
				if not value and b.kind in ["home","factory","hospital"]:
					return _result(false,"用户负荷不能直接停用来消除失供需求；请使用需求响应。")
			"dispatch":
				if not is_generator(str(b.kind)) or not _number(value,0.0,1.0):
					return _result(false,"机组出力上限应为 0—100%。")
			"cooling_mode":
				if b.kind != "cooling" or value not in ["wet","dry"] or (value == "dry" and not has_technology("dry_cooling")):
					return _result(false,"干冷模式需要空冷与节水运行研究。")
			"storage_mode":
				if not is_storage(str(b.kind)) or value not in ["auto","hold","peak"]:
					return _result(false,"无效储能策略。")
				if value == "peak" and not has_technology("smart_storage"):
					return _result(false,"削峰策略需要储能协同与削峰研究。")
			"reserve_soc":
				if not is_storage(str(b.kind)) or not _number(value,0.0,0.9) or (not has_technology("regional_planning") and float(value) != float(b.get("reserve_soc",0.0))):
					return _result(false,"保留电量需要区域负荷规划研究，范围 0—90%。")
			"peak_hour":
				if not is_storage(str(b.kind)) or not _number(value,0.0,23.0) or (not has_technology("smart_storage") and float(value) != float(b.get("peak_hour",17.0))):
					return _result(false,"削峰起点需要协同研究，范围 0—23 时。")
			"environmental_release":
				if b.kind != "hydro" or not _number(value,0.1,0.6):
					return _result(false,"生态下泄比例范围 10—60%。")
			"flexible_mode":
				if not value is bool or b.kind not in ["steam","coal","ccgt"] or (value and not has_technology("flexible_thermal")):
					return _result(false,"此机组尚无柔性热机控制能力。")
			"boost_cooling":
				if not value is bool or b.kind != "cooling" or (value and not has_technology("advanced_cooling")):
					return _result(false,"强化冷却需要先进热管理研究。")
			"protection_margin":
				if b.kind != "substation" or not _number(value,0.8,1.2) or (float(value) != 1.0 and not has_technology("protection")):
					return _result(false,"保护裕度需要保护协调研究，范围 80—120%。")
			_:
				return _result(false,"不支持的设施控制项。")
	for key in settings:
		b[key] = settings[key]
	return _result(true,"设施策略已应用；启停与爬坡将在时间推进后完成。")

func advance(sim: RefCounted, dt: float) -> void:
	if dt <= 0.0:
		return
	if not project.is_empty():
		remaining_hours = maxf(0.0,remaining_hours-dt)
		if remaining_hours <= 0.000001:
			unlocked.append(project)
			sim._log("科技突破「%s」：新设备或运行控制已解锁。" % TECHNOLOGIES[project].name,"success")
			project = ""
			remaining_hours = 0.0
	for b in sim.buildings:
		initialize_building(b)
		if not is_generator(str(b.kind)) or b.kind == "gas":
			continue
		var ids := _component(sim,int(b.id))
		var viable := bool(b.online) and bool(b.enabled) and float(b.dispatch) > 0.000001 and _support_problem(sim,b,ids).is_empty()
		if viable and b.kind in ["nuclear","fusion"] and float(b.startup_remaining) > 0.0:
			viable = _startup_auxiliary_powered(sim,ids)
		var target := float(b.capacity) * float(b.dispatch) if viable else 0.0
		if viable and float(b.startup_remaining) > 0.0:
			var startup_time := minf(dt,float(b.startup_remaining))
			b.startup_remaining = maxf(0.0,float(b.startup_remaining)-dt)
			if b.startup_remaining > 0.000001:
				continue
			_ramp(b,target,dt-startup_time)
		else:
			_ramp(b,target,dt)
		if float(b.ramp_mw) > 0.000001:
			b.running_hours = float(b.running_hours) + dt
		elif not viable:
			b.startup_remaining = float(STARTUP[b.kind])

func _ramp(b: Dictionary, target: float, dt: float) -> void:
	var rate := float(RAMP[b.kind]) * (1.6 if bool(b.flexible_mode) else 1.0)
	b.ramp_mw = move_toward(float(b.ramp_mw),target,maxf(0.0,dt)*rate)

func is_generator(kind: String) -> bool:
	return STARTUP.has(kind)

func is_storage(kind: String) -> bool:
	return EFFICIENCY.has(kind)

func is_terminal(kind: String) -> bool:
	return kind in ["intertie","hvdc"]

func storage_efficiency(b: Dictionary) -> float:
	return float(EFFICIENCY.get(b.kind,0.94))

func storage_power_factor(_sim: RefCounted, b: Dictionary) -> float:
	return 1.0 if bool(b.get("enabled",true)) and bool(b.online) else 0.0

func storage_can_discharge(sim: RefCounted, b: Dictionary) -> bool:
	if not bool(b.get("enabled",true)) or b.get("storage_mode","auto") == "hold":
		return false
	if b.get("storage_mode","auto") == "peak" and has_technology("smart_storage") and int(sim.research_level) >= 1 and sim.digital.control_reachable(sim,int(b.id)):
		return fposmod(float(sim.time_hours)-float(b.peak_hour),24.0) < 4.0
	# An unreachable controller falls back to local emergency operation.
	return true

func storage_can_charge(sim: RefCounted, b: Dictionary) -> bool:
	if not bool(b.get("enabled",true)) or b.get("storage_mode","auto") == "hold":
		return false
	if b.get("storage_mode","auto") == "peak" and has_technology("smart_storage") and int(sim.research_level) >= 1 and sim.digital.control_reachable(sim,int(b.id)):
		return fposmod(float(sim.time_hours)-float(b.peak_hour),24.0) >= 4.0
	return true

func generator_available(sim: RefCounted, b: Dictionary, ids: Array[int]) -> float:
	if not bool(b.online) or not _support_problem(sim,b,ids).is_empty():
		return 0.0
	var capacity := float(b.capacity)
	var factor := 0.7 + float(b.health)*0.003
	if b.kind == "gas":
		return capacity*float(b.dispatch)*factor if bool(b.get("enabled",true)) else 0.0
	if b.kind == "dc_dynamo":
		var longest := 0.0
		for id in ids:
			var consumer: Dictionary = sim.get_building(id)
			if float(consumer.base_demand) > 0.0:
				longest = maxf(longest,Vector2(b.cell).distance_to(Vector2(consumer.cell)))
		factor *= 1.0 / maxf(1.0,longest/3.0)
	if b.kind == "hydro":
		factor *= (0.55+0.25*sin(float(sim.day)*0.45))*(1.0-float(b.get("environmental_release",0.25)))
	if b.kind in ["nuclear","fusion"]:
		factor *= _cooling_factor(sim,ids)
	return maxf(0.0,minf(capacity,float(b.get("ramp_mw",0.0)))*factor)

func generator_minimum(b: Dictionary) -> float:
	var ratio := float(MINIMUM.get(b.kind,0.0))
	if bool(b.get("flexible_mode",false)):
		ratio *= 0.7
	return minf(float(b.get("available",0.0)),float(b.get("ramp_mw",0.0))*ratio)

func demand_for(_sim: RefCounted, b: Dictionary) -> float:
	if not bool(b.get("enabled",true)):
		return 0.0
	var demand := float(b.base_demand)
	if b.kind == "cooling":
		demand *= 2.5 if b.get("cooling_mode","wet") == "dry" else 1.0
		if bool(b.get("boost_cooling",false)):
			demand *= 2.0
	return demand

func terminal_capacity(sim: RefCounted, b: Dictionary) -> float:
	if not bool(b.get("enabled",true)):
		return 0.0
	var capacity := float(b.capacity)*(0.7+float(b.health)*0.003)
	if b.kind == "hvdc":
		for id in _component(sim,int(b.id)):
			var support: Dictionary = sim.get_building(id)
			if support.kind == "condenser" and bool(support.online) and bool(support.get("enabled",true)):
				capacity *= 1.15
				break
		return capacity*(0.85 if sim.storm_active else 1.0)
	return capacity*(0.55 if sim.storm_active else 1.0)

func operating_cost(sim: RefCounted) -> float:
	var total := 0.0
	for b in sim.buildings:
		# Fixed staffing/asset cost persists while stopped: shutdown is not free.
		total += float(UPKEEP.get(b.kind,0.0))*float(b.level)
		if bool(b.get("flexible_mode",false)):
			total += 25.0
		if bool(b.get("boost_cooling",false)):
			total += 40.0
		if b.kind == "hydro" and bool(b.get("enabled",true)):
			total += maxf(0.0,0.25-float(b.get("environmental_release",0.25)))*2400.0
	return total

func fuel_cost(b: Dictionary) -> float:
	var power := maxf(0.0,float(b.get("output",0.0)))
	if b.kind in ["steam","coal","ccgt","nuclear","fusion"]:
		power = maxf(power,generator_minimum(b))
	return power*float(FUEL.get(b.kind,0.0))*(1.15 if bool(b.get("flexible_mode",false)) else 1.0)

func carbon_rate(b: Dictionary) -> float:
	var power := maxf(float(b.get("output",0.0)),generator_minimum(b))
	return power*float(CARBON.get(b.kind,0.0))

func line_trip_threshold(sim: RefCounted, line: Dictionary) -> float:
	var multiplier := 1.0
	for id in [int(line.a),int(line.b)]:
		var b: Dictionary = sim.get_building(id)
		if b.is_empty() or not bool(b.online) or not bool(b.get("enabled",true)):
			continue
		if b.kind == "substation":
			multiplier = float(b.get("protection_margin",1.0))
			break
	return multiplier

func facility_status(sim: RefCounted, b: Dictionary) -> String:
	if not bool(b.get("enabled",true)):
		return "正在降载停机" if float(b.get("ramp_mw",0.0)) > 0.001 else "已停运；固定维护费仍在发生"
	if is_generator(str(b.kind)):
		if b.kind == "gas":
			return "可调功率 %.1f MW · 出力上限 %.0f%% · 每小时燃料 ¥%.0f" % [float(b.get("available",0.0)),float(b.dispatch)*100.0,fuel_cost(b)]
		var problem := _support_problem(sim,b,_component(sim,int(b.id)))
		if not problem.is_empty():
			return problem
		if float(b.get("startup_remaining",0.0)) > 0.000001:
			if b.kind in ["nuclear","fusion"] and not _startup_auxiliary_powered(sim,_component(sim,int(b.id))):
				return "启动等待厂用电：请用燃气、储能或外网为冷却设施与学院供电"
			return "启动准备：剩余 %.1f 小时" % float(b.startup_remaining)
		return "热功率 %.1f MW · 最低负荷 %.1f MW · 每小时燃料 ¥%.0f" % [float(b.get("ramp_mw",b.get("available",0.0))),generator_minimum(b),fuel_cost(b)]
	if is_storage(str(b.kind)):
		var coordinated: bool = b.get("storage_mode","auto") == "peak" and has_technology("smart_storage") and int(sim.research_level) >= 1 and sim.digital.control_reachable(sim,int(b.id))
		var mode_text := "可信控制执行削峰" if coordinated else ("保留电量；双向待机" if b.get("storage_mode","auto") == "hold" else ("削峰控制不可用，退回本地自动保供" if b.get("storage_mode","auto") == "peak" else "本地自动保供"))
		return "充放效率各 %.0f%% · 保留 %.0f%% · %s" % [storage_efficiency(b)*100.0,float(b.get("reserve_soc",0.0))*100.0,mode_text]
	if b.kind == "academy":
		return "同岛提供 %d 个高级运行岗位；核能占 6，聚变占 10" % (8*int(b.level))
	if b.kind == "cooling":
		return "%s · 支撑 %.0f 份热机需求 · 辅机 %.1f MW" % ["干冷" if b.get("cooling_mode","wet") == "dry" else "湿冷",2.0 if bool(b.get("boost_cooling",false)) else 1.0,demand_for(sim,b)]
	if b.kind == "condenser":
		return "同岛 HVDC 可用输送上限 +15%（稳定近似）；线路热容量不变；辅机 0.8 MW，维护 ¥55/h"
	return "设施需要真实电网接入；技术解锁不会自动连接或供电。"

func _support_problem(sim: RefCounted, b: Dictionary, ids: Array[int]) -> String:
	if b.kind not in ["nuclear","fusion"]:
		return ""
	var cooling := 0.0
	var staff := 0
	for id in ids:
		var support: Dictionary = sim.get_building(id)
		if not bool(support.online) or not bool(support.get("enabled",true)) or float(support.health) < 30.0:
			continue
		if support.kind == "cooling":
			cooling += 2.0 if bool(support.get("boost_cooling",false)) else 1.0
		if support.kind == "academy":
			staff += int(support.level)*8
	# Stable ID ordering allocates finite specialists/cooling without duplication.
	var advanced_ids: Array[int] = []
	for id in ids:
		var candidate: Dictionary = sim.get_building(id)
		if candidate.kind in ["nuclear","fusion"] and bool(candidate.online) and (bool(candidate.get("enabled",true)) or float(candidate.get("ramp_mw",0.0)) > 0.001):
			advanced_ids.append(id)
	advanced_ids.sort()
	for id in advanced_ids:
		var candidate: Dictionary = sim.get_building(id)
		var staff_need := 10 if candidate.kind == "fusion" else 6
		var cooling_need := 2.0 if candidate.kind == "fusion" else 1.0
		if id == int(b.id):
			if cooling < cooling_need:
				return "缺少同电气岛冷却容量（需要 %.0f 份）" % cooling_need
			if staff < staff_need:
				return "同电气岛高级运行岗位不足（需要 %d 个）" % staff_need
			return ""
		if cooling >= cooling_need and staff >= staff_need:
			cooling -= cooling_need
			staff -= staff_need
	return ""

func _cooling_factor(sim: RefCounted, ids: Array[int]) -> float:
	var dry := false
	for id in ids:
		var b: Dictionary = sim.get_building(id)
		if b.kind == "cooling" and bool(b.online) and bool(b.get("enabled",true)) and b.get("cooling_mode","wet") == "dry":
			dry = true
	if dry:
		return 0.88
	# A deterministic warm season/water stress encourages diverse cooling.
	return 0.72 if sin(float(sim.day)*0.22) > 0.65 and float(sim.time_hours) >= 12.0 and float(sim.time_hours) < 18.0 else 1.0

func _startup_auxiliary_powered(sim: RefCounted, ids: Array[int]) -> bool:
	var cooling_powered := false
	var academy_powered := false
	for id in ids:
		var b: Dictionary = sim.get_building(id)
		if not bool(b.online) or not bool(b.get("enabled",true)) or not bool(b.get("powered",false)):
			continue
		cooling_powered = cooling_powered or b.kind == "cooling"
		academy_powered = academy_powered or b.kind == "academy"
	return cooling_powered and academy_powered

func _component(sim: RefCounted, id: int) -> Array[int]:
	var ids: Array[int] = [id]
	var index := 0
	while index < ids.size():
		var current := ids[index]
		index += 1
		for line in sim.lines:
			if not bool(line.closed) or bool(line.fault) or float(line.repair_remaining) > 0.0:
				continue
			var neighbor := int(line.b) if int(line.a) == current else (int(line.a) if int(line.b) == current else -1)
			if neighbor > 0 and neighbor not in ids:
				ids.append(neighbor)
	return ids

func snapshot() -> Dictionary:
	return {"unlocked":unlocked.duplicate(), "project":project, "remaining_hours":remaining_hours, "heritage":heritage}

func load_snapshot(data: Variant) -> bool:
	if not valid_snapshot(data):
		return false
	unlocked.assign(data.unlocked)
	project = str(data.project)
	remaining_hours = float(data.remaining_hours)
	heritage = bool(data.get("heritage",false))
	return true

static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("unlocked") is Array or not data.get("project") is String or not _number(data.get("remaining_hours"),0.0,7.0):
		return false
	if data.has("heritage") and not data.heritage is bool:
		return false
	if data.unlocked.size() > TECHNOLOGIES.size() or "dc_basics" not in data.unlocked:
		return false
	var seen := {}
	for id in data.unlocked:
		if not id is String or not TECHNOLOGIES.has(id) or seen.has(id):
			return false
		seen[id] = true
	for id in data.unlocked:
		for prerequisite in TECHNOLOGIES[id].requires:
			if prerequisite not in data.unlocked:
				return false
	if not str(data.project).is_empty():
		if not TECHNOLOGIES.has(data.project) or data.project in data.unlocked or float(data.remaining_hours) <= 0.0 or float(data.remaining_hours) > float(TECHNOLOGIES[data.project].hours):
			return false
		for prerequisite in TECHNOLOGIES[data.project].requires:
			if prerequisite not in data.unlocked:
				return false
	elif float(data.remaining_hours) != 0.0:
		return false
	return true

static func validate_building(b: Dictionary) -> bool:
	for key in ["enabled","flexible_mode","boost_cooling"]:
		if b.has(key) and not b[key] is bool:
			return false
	for spec in [["reserve_soc",0.0,0.9],["peak_hour",0.0,23.0],["environmental_release",0.1,0.6],["protection_margin",0.8,1.2],["ramp_mw",0.0,1000000.0],["startup_remaining",0.0,12.0],["running_hours",0.0,1e15]]:
		if b.has(spec[0]) and not _number(b[spec[0]],float(spec[1]),float(spec[2])):
			return false
	if b.has("cooling_mode") and b.cooling_mode not in ["wet","dry"]:
		return false
	if b.has("storage_mode") and b.storage_mode not in ["auto","hold","peak"]:
		return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message,"id":-1}
