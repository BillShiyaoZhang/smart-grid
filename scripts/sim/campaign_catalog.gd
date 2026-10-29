extends RefCounted
## Historical settings are documented facts; budgets and objectives are game adaptations.

static func chapters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in range(1, 16): result.append(get_chapter(id))
	return result

static func get_chapter(id: int) -> Dictionary:
	if id < 1 or id > 15: return {}
	var data: Array = [
		["第一条亮起的街", "美国 · 纽约珍珠街", "1882", "街区居民正在等待第一批电灯。你是供电公司的值班工程师：先把电送到已有客户，再扩建一处街区。小型直流电站必须靠近用户。", "附近街区亮了起来。集中供电开始进入城市生活，但早期直流供电的距离仍限制着它的规模。", "美国人口普查局 · 珍珠街", "https://www.census.gov/about/history/stories/monthly/2026/september-2026.html"],
		["把电送到远方", "德国 · 劳芬—法兰克福", "1891", "远方展览会正在等待来自劳芬的电力。你负责论证交流方案，并把预置水力机房与展场连起来；水文管理将在后面的关卡学习。", "远处展场的灯光说明了供电尺度的变化。历史工程使用三相交流和变压器；本关以简化网络表达这一转变。", "VDE · 劳芬—法兰克福输电", "https://www.vde.com/de/geschichte/karte/baden-wuerttemberg/drehstromuebertragung-lauffen-frankfurt"],
		["工厂的清晨", "中国 · 上海杨树浦", "1913", "江边电站面对持续增加的工业需求。你负责安排煤电启动、现场设置和供电；机组不能像开灯一样瞬间达到额定出力。", "工业用电推动了更大电站的建设。预热、爬坡、燃料和最低稳定负荷，也让运行计划成为一项新的责任。", "杨浦地方志 · 杨树浦发电厂", "https://szb.shyp.gov.cn/dqw/zzlt/20131119/56865.html"],
		["小电网连成网", "英国 · 区域互联", "1930年代", "相邻地区正在接入更大的电网。你需要现场查明薄弱线路，增容并安排备用路线，让检修不再意味着整个街区停电。", "互联让地区能够共享电源，也让潮流、保护和备用路径成为共同的问题。扩大网络需要同时照顾每一条薄弱支路。", "National Grid · 电网历史", "https://www.nationalgrid.com/about-us/what-we-do/our-history"],
		["山谷里的新生活", "美国 · 田纳西河谷", "1936", "诺里斯工程背后，是河谷居民对电力与发展的期待。你负责连接水电和城镇，兼顾实际来水、生态下泄及可负担的供电。", "电力改变了河谷的生活和产业。这里呈现的是区域电气化情景，水电与生态参数属于游戏抽象，并非诺里斯水库调度复现。", "TVA · Norris", "https://www.tva.com/energy/our-power-system/hydroelectric/norris"],
		["直流重返舞台", "瑞典 · 哥特兰岛", "1954", "大陆电力即将跨海来到岛上。你负责建成换流接口并打通岛内瓶颈：接口有余量，并不代表下游线路能够承载。", "高压直流开辟了另一条远距离供电路线。大陆系统在本关位于地图之外，以固定购电接口表示，不模拟双端海缆电气过程。", "Hitachi Energy · HVDC 历史", "https://www.hitachienergy.com/products-and-solutions/hvdc/hvdc-heritage"],
		["原子时代的配套", "美国 · 宾夕法尼亚希平港", "1957", "新核电站等待投运。你负责补齐冷却和运行人才，保障厂用电，再等候启动与爬坡。没有配套，巨大的装机也无法成为可交付电力。", "希平港进入核能发电时代。游戏以学院岗位和冷却配额表达配套责任，这些数值不代表真实核电站的人员与设备要求。", "美国能源部 · Shippingport", "https://www.energy.gov/management/december-23-1957-shippingport"],
		["把深夜留给白昼", "英国 · 苏格兰克鲁阿坎", "1965", "夜间基荷有富余，白天工厂却需要更多电力。你负责在山地建设抽蓄，让它真正经历充电和放电，而不是把储能当作发电机。", "抽蓄把用电时间变成可安排的资源。功率决定此刻能做多少，能量决定坚持多久，充放电损耗始终需要付出代价。", "Drax · 克鲁阿坎历史", "https://www.drax.com/press_release/iconic-hollow-mountain-power-station-celebrates-60-years-of-keeping-scotlands-lights-on/"],
		["电力也有价格", "英国 · 英格兰与威尔士", "1990", "批发电力交易正在改变经营方式。你负责实际采购、调整零售电价、签订一份锁价合约，并从账本核对付款与交付。", "供电公司开始面对新的价格与承诺。这里采用统一的游戏市场，十二小时合约及需求弹性并非英国 Electricity Pool 制度的完整复刻。", "Ofgem · 批发市场历史", "https://www.ofgem.gov.uk/sites/default/files/docs/2002/10/1112-factsheet1402_14oct_0.pdf"],
		["风不听调度", "丹麦 · 日德兰西岸", "2002", "海岸附近接入了新的风电。你负责把风机连入电网，在风力变化时安排备用和购电，不能只按铭牌容量作出承诺。", "Horns Rev 1 于二〇〇二年启用。风电扩大了清洁供电，也让备用、互联和实际可用出力变得更重要。", "Vattenfall · Horns Rev 1", "https://powerplants.vattenfall.com/en/horns-rev/"],
		["看见电网", "美国 · 太平洋西北示范项目", "2010—2012", "电已经送到了，调度室却还看不到可靠读数。你负责建立独立通信、投运调度根并完成一级遥测，让测量真正到达。", "示范项目把通信、控制和电力设施连接起来。通信可达、来源可信和记录新鲜，是三个需要分别确认的条件。", "PNNL · 太平洋西北智能电网示范", "https://www.pnnl.gov/projects/transactive-systems-program/pacific-northwest-smart-grid-demonstration"],
		["发出的指令", "美国 · 太平洋西北示范项目", "2012—2014", "可靠测量已经建立。你负责提交远程开关与设施设置，核对回执，再启动需求响应；指令排队不等于已经执行。", "远程控制缩短了处置时间，但仍依赖供电、可信通信和到达时的复验。失联之后，现场队仍然是必要的保障。", "PNNL · 通信与响应资产示范", "https://www.pnnl.gov/projects/transactive-systems-program/pacific-northwest-smart-grid-demonstration"],
		["风雪之后", "美国 · 查塔努加", "2014", "湿雪天气即将考验自动化电网。确认备用和通信后开始考核，观察 UPS 与自愈转供，再抢修主馈线。自动化不能修好一根断线。", "查塔努加的自动化电网在二〇一四年雪灾中帮助恢复或避免了大量停电，现场抢修仍承担着不可替代的工作。", "EPB · 公司历史", "https://epb.com/about/history/"],
		["失去信任的屏幕", "乌克兰 · 配电区域", "2015", "供电与控制系统面临持久入侵。你负责隔离受影响网关、派员核实、实施恢复补丁，再重新接入可信通信。等待不会清除这次入侵。", "二〇一五年乌克兰配电企业遭遇网络攻击并停电。本关使用离线抽象事件，强调信任、现场处置和恢复流程。", "美国能源部 · 电网网络事件案例", "https://www.energy.gov/articles/report-strengthening-cybersecurity-federal-networks-and-critical-infrastructure?nrg_redirect=442003"],
		["让清洁电力持续可靠", "澳大利亚 · 南澳", "2017—2023", "风光、储能和跨区联络已成为同一张电网的组成部分。你负责接入光伏、安排社区削峰，再独立保持清洁、可靠且可持续的运营。", "你走过了从街区电站到协同电网的旅程。此关借南澳能源转型背景进行综合运营，不模拟频率辅助服务或复刻某一座真实电池工程。", "ARENA · Hornsdale 储能报告", "https://arena.gov.au/knowledge-bank/neoen-hornsdale-power-reserve-upgrade-hprx-market-report/"]
	]
	var row: Array = data[id - 1]
	return {"id": id, "title": row[0], "place": row[1], "years": row[2], "briefing": row[3], "debrief": row[4], "objective": _objectives()[id - 1], "sources": [{"title": row[5], "url": row[6]}], "fixed_import_price": 90.0, "minutes": "8–12" if id <= 3 else ("12–18" if id <= 10 else "18–25")}

static func _objectives() -> Array[String]:
	return ["接线、扩建街区并稳定供电", "研究交流并点亮远方展场", "安排热机与工业供电", "现场巡检、增容与备用转供", "连接水电与城镇，持续提供服务", "投运跨海接口并疏通本地瓶颈", "配齐核能设施并实际送电", "让抽蓄实际充电和放电", "实际购电、履约并核对账本", "接入风电并保持清洁可靠供电", "建立独立通信和可信遥测", "执行远程操作及需求响应", "自愈转供后修复物理线路", "隔离、修补并恢复可信供电", "完成一天清洁可靠且不亏损的运营"]

static func steps(id: int) -> Array[Dictionary]:
	var all: Array = [
		[_step("连上第一批客户", "选择接线工具，连接配电站与小工坊。", "电源和用户必须在同一电气岛。", "cable", "first_connection"), _step("扩建一处街区", "建设一座住宅并接入电网；可在原电站附近增加电源。", "先比较新增需求和可用容量，再决定如何扩建。", "build", "new_customer"), _step("守住每一盏灯", "保持指定客户至少 98% 供电，连续两小时。", "暂停可以帮助规划，运行后才能产生电量和收入。", "statistics", "reliable", 2.0)],
		[_step("论证交流方案", "在科技中心研究「交流与变压器」。", "研究需要资金和真实时间，展场采用预置水力机房供电。", "planning", "ac_research"), _step("连接远方展场", "把水力机房接到远方展场的配电站。", "本关通过预置交流电源表达输送尺度变化，不计算真实电压。", "cable", "first_connection"), _step("让展场持续亮灯", "保持展场至少 98% 供电，连续两小时。", "连接之后还要验证持续运行。", "statistics", "reliable", 2.0)],
		[_step("派出设置队", "选中煤电机组，以现场方式将出力设为 100%。", "现场设置需要费用、队伍和约二十一游戏分钟。", "inspect", "facility_action"), _step("等待真实出力", "推进时间，让机组完成预热和爬坡。", "可以使用倍速；机组的净出力必须真正送到工厂。", "statistics", "thermal_running"), _step("覆盖工业高峰", "保持工业用户至少 98% 供电，连续两小时。", "最低稳定负荷仍会约束夜间运行，弃电并不免费。", "statistics", "reliable", 2.0)],
		[_step("现场核实薄弱支路", "选中连接工厂的主馈线，派巡检队并等待完成。", "没有可信遥测时，需要真实的现场记录。", "inspect", "inspection"), _step("为主馈线增容", "完成至少一次线路增容。", "保护裕度不能替代线路的物理容量。", "inspect", "line_upgrade"), _step("建立备用路径", "连接备用变电站与工厂，形成另一条供电路径。", "环网会重新分配潮流；增容后仍应检查各条线路。", "cable", "redundancy"), _step("让检修不再停电", "派现场开关队断开主馈线，让备用路径实际承担供电。", "备用路线必须能在主路退出时真正工作。", "inspect", "field_transfer"), _step("稳定互联运行", "连续两小时达到 98% 供电。", "现场开关可用于检修转供，合理安排两支队伍。", "statistics", "reliable", 2.0)],
		[_step("把水电送进城镇", "把水电站接到城镇配电站。", "水电只能放在河流区域，额定容量不等于可用功率。", "cable", "first_connection"), _step("保留河流的水", "以现场设置提交至少 25% 的生态下泄。", "减少下泄会改变出力，也会产生生态补偿成本。", "inspect", "ecology"), _step("观察城镇生活", "连续十二小时保持指定客户至少 98% 供电。", "在区域页观察服务、繁荣和人口趋势，不必等待巨大的人口增幅。", "planning", "reliable", 12.0)],
		[_step("建设换流接口", "建设高压直流换流站并接到岛上配电站。", "大陆位于地图外，本关按固定价格购电，尚无现货交易。", "build", "hvdc_connected"), _step("疏通岛内瓶颈", "巡检主馈线，完成一次增容。", "换流容量不能提升本地支路的热容量。", "inspect", "line_upgrade"), _step("核对实际交付", "让固定购电实际交付，并连续两小时稳定供电。", "只有真实可达的线路才能把外部电力送到用户。", "statistics", "import_reliable", 2.0)],
		[_step("建设运行配套", "建设冷却设施与电力工程学院，并连接到核电所在电气岛。", "学院岗位和冷却容量不能重复分配，配套还需要真实供电。", "build", "nuclear_support"), _step("启动新机组", "以现场设置把核电机组出力设为 100%，推进时间。", "先用预置外网保障启动厂用电；核电有八小时预热和缓慢爬坡。", "inspect", "nuclear_running"), _step("让配套与用户都得到电", "核电实际送电，且连续两小时保持至少 98% 供电。", "启动后仍应保障冷却与人才设施，主干线已为本关预先增容。", "statistics", "nuclear_reliable", 2.0)],
		[_step("在山地建设抽蓄", "在标出的山地区域建设抽水蓄能并接网。", "夜间基荷最低出力高于需求，富余电力才有机会存入抽蓄。", "build", "pumped_connected"), _step("把富余电存起来", "推进夜间运行，实际充入至少 8 MWh。", "充电会损耗能量；不能只依靠开局预置电量。", "statistics", "storage_charged"), _step("在需求上升时放电", "继续运行到白天，实际放出至少 2 MWh。", "MWh 大不代表瞬间 MW 大，功率和线路都可能成为瓶颈。", "statistics", "storage_discharged"), _step("稳定完成峰谷循环", "完成充放电后，连续两小时达到 98% 供电。", "储能转移了电量出现的时间，没有创造电力。", "statistics", "reliable", 2.0)],
		[_step("提交交易与电价方案", "在市场中心应用购售电策略及零售电价方案。", "编辑字段是草案，应用才生效，推进时间才结算。", "market", "market_actions"), _step("签订锁价合约", "签订一份十二小时的固定供电合约。", "合约持续付费，即使用不完或线路中断。", "market", "contract_signed"), _step("核对实际履约", "让十二小时合约履行完毕，核对进口电量和合约费用。", "账本记录的是实际结算，报价刷新不会重复买电。", "market", "contract_settled"), _step("照顾客户与现金流", "满意度不低于 60，并连续两小时达到 98% 供电。", "提高零售价可能减少需求，不能只盯住单价。", "market", "market_reliable", 2.0)],
		[_step("让风电接入", "建设至少一座风机并连接电网。", "风力变化会改变出力，观察实际清洁供电而非铭牌。", "build", "wind_connected"), _step("安排可调备用", "以现场设置提交燃气备用出力。", "备用有成本，但能在风弱时补缺。", "inspect", "facility_action"), _step("清洁且可靠地运行", "连续四小时达到 98% 供电，实际可再生供电比例至少 35%。", "可使用已学过的联络站与市场策略补充备用。", "statistics", "wind_reliable", 4.0)],
		[_step("投运调度根", "在数字中心将智能终端投运为调度根。", "供电线路不会自动成为通信线路。", "digital", "commissioned"), _step("铺设独立通信", "把调度根与配电站、工厂分别用光纤连接。", "通信拓扑与电力拓扑独立；设备也需要供电。", "digital", "communication_built"), _step("上线一级遥测", "完成一级研究，推进时间获取主馈线新鲜可信遥测。", "研究只解锁能力，不会替代有效通信路径。", "digital", "telemetry"), _step("保持可信观测", "保持供电和主馈线可信遥测，连续两小时。", "断线、失电或记录过时都会改变可见信息。", "digital", "telemetry_reliable", 2.0)],
		[_step("提交远程开关", "对备用联络线提交远程合闸，等待执行成功回执。", "在途指令到达时会再次验证通信与电气安全。", "digital", "remote_executed"), _step("升级设施控制", "完成二级研究，以远程方式提交燃气机组出力设置。", "设施远控比线路开关需要更高权限；本关尚未开放自愈。", "planning", "remote_facility"), _step("让需求作出回应", "启动一次需求响应并推进时间。", "只有可信可控的普通负荷会响应，医院仍保持关键需求。", "digital", "response_executed"), _step("稳定协同运行", "连续两小时达到 98% 供电。", "远程与现场都是工具，可靠运行才是目的。", "statistics", "reliable", 2.0)],
		[_step("准备风雪考核", "确认备用联络线、独立通信和 UPS，点击开始考核。", "开始后主馈线将损坏，关键负荷连续失供两小时会失败。", "prepare", "assessment_started", 0.0, "begin_assessment"), _step("让自愈完成转供", "推进时间，观察健全备用线的远程合闸与供电恢复。", "自愈需要可信通信，UPS 只能短时支持失电网关。", "digital", "auto_restored"), _step("修复真正的断线", "通过遥测或巡检确认故障，派队修复主馈线。", "自动转供不会恢复设备健康，维修队仍然必不可少。", "inspect", "physical_repaired"), _step("风雪后的稳定供电", "连续两小时达到 98% 供电。", "保留备用并恢复完整网络，才算完成恢复。", "statistics", "reliable", 2.0)],
		[_step("开始恢复考核", "查看分段通信与现场队，点击开始考核。", "持久入侵不会自行消失，先保障关键负荷。", "prepare", "assessment_started", 0.0, "begin_assessment"), _step("隔离并核实", "隔离受影响的工厂网关，并派队巡检主馈线。", "屏幕状态不可信时，需要隔离和独立现场证据。", "digital", "isolated_inspected"), _step("修补并重新接入", "对受影响设备执行恢复，完成后解除隔离。", "解除隔离不等于清除入侵；先完成补丁，再恢复信任。", "digital", "trust_restored"), _step("恢复可信供电", "通信可信且连续两小时达到 98% 供电。", "必要时用现场开关恢复被异常断开的电力线路。", "digital", "secure_reliable", 2.0)],
		[_step("补上白天的太阳", "建设光伏并接网，实际向用户供电。", "白天的富余可以储存，夜间仍需其他资源。", "build", "solar_delivered"), _step("安排社区削峰", "建设社区储能、接入电力和可信通信，以远程设置提交削峰窗口与备用电量。", "软件不会增加额定功率，失联后退回本地保供。", "planning", "coordinated_storage"), _step("开始独立运营考核", "确认电源、储能与交易方案，点击开始考核。", "接下来用真实结算检验整整一天的供电、清洁比例与盈亏。", "prepare", "assessment_started", 0.0, "begin_assessment"), _step("守住清洁而可靠的一天", "连续二十四小时供电率至少 98%、实际可再生供电至少 50%，且窗口运营净收益非负。", "建设支出与运营账本分开；清洁比例计算储能的真实充电来源。", "statistics", "final_assessment", 24.0)]
	]
	var result: Array[Dictionary] = []
	if id < 1 or id > 15: return result
	for item in all[id - 1]: result.append(item.duplicate(true))
	return result

static func _step(title: String, instruction: String, why: String, ui: String, predicate: String, hold: float = 0.0, action: String = "") -> Dictionary:
	return {"title": title, "instruction": instruction, "why": why, "ui_target": ui, "predicate": predicate, "hold_hours": hold, "action": action, "hints": [why, instruction, "暂停后查看任务涉及的设施或线路，检查费用、连接和实际执行回执；推进时间才能完成等待与运营目标。"]}
