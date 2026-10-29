class_name GridMarket
extends RefCounted
## Deterministic game-scale wholesale and retail market. Currency/MWh is
## deliberately fictional. Only settle() advances bills and customer sentiment.

const DEFAULT_STATE := {
	"tariff_mode": "flat", "valley_rate": 85.0, "flat_rate": 145.0, "peak_rate": 220.0,
	"market_mode": "balanced", "buy_limit": 120.0, "sell_floor": 90.0,
	"storage_mode": "reserve", "charge_price": 60.0, "discharge_price": 150.0, "reserve_soc": 0.2,
	"satisfaction": 100.0, "spot_price": 100.0, "export_price": 72.0, "retail_price": 145.0,
	"contract_mw": 0.0, "contract_price": 0.0, "contract_remaining": 0.0, "contract_quote": 110.0
}
const LEDGER_FIELDS := ["retail_revenue", "export_revenue", "import_cost", "fuel_cost", "maintenance_cost", "outage_cost", "contract_cost", "net", "import_mwh", "export_mwh", "served_mwh"]
var state: Dictionary = DEFAULT_STATE.duplicate(true)
var ledger: Array[Dictionary] = []

func reset() -> void:
	state = DEFAULT_STATE.duplicate(true)
	ledger.clear()

func retail_at(hour: float) -> float:
	if state.tariff_mode == "flat":
		return float(state.flat_rate)
	var h := fposmod(hour, 24.0)
	if h < 7.0 or h >= 23.0:
		return float(state.valley_rate)
	if h >= 17.0 and h < 21.0:
		return float(state.peak_rate)
	return float(state.flat_rate)

func spot_at(day: int, hour: float, weather: String = "晴朗") -> float:
	var h := fposmod(hour, 24.0)
	var base := 103.0
	if h < 7.0 or h >= 23.0:
		base = 45.0
	elif h >= 17.0 and h < 21.0:
		base = 198.0
	elif h >= 11.0 and h < 15.0:
		base = 64.0
	elif h >= 21.0:
		base = 112.0
	var day_variation := sin(float(day) * 0.73) * 4.0
	var weather_premium := 65.0 if weather == "风暴" else (9.0 if weather == "多云" else (-3.0 if weather == "有风" else 0.0))
	return snappedf(maxf(20.0, base + day_variation + weather_premium), 0.01)

func forecast(day: int, hour: float, weather: String = "晴朗") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := floorf(hour)
	for offset in 24:
		var absolute := start + float(offset)
		var target_day := day + int(floorf(absolute / 24.0))
		var target_hour := fposmod(absolute, 24.0)
		# A current storm is a short event, not a prediction of 24 hours of storms.
		var expected_weather := weather if offset < 3 or weather != "风暴" else "多云"
		result.append({"day": target_day, "hour": target_hour,
			"spot": spot_at(target_day, target_hour, expected_weather), "retail": retail_at(target_hour)})
	return result

func update_prices(day: int, hour: float, weather: String) -> void:
	state.spot_price = spot_at(day, hour, weather)
	# The spread prevents immediate buy/sell arbitrage.
	state.export_price = snappedf(float(state.spot_price) * 0.72, 0.01)
	state.retail_price = retail_at(hour)
	state.contract_quote = quote_for(day, hour, weather, 12.0)

func quote_for(day: int, hour: float, weather: String, hours: float) -> float:
	if not _number_in(hours, 1.0, 48.0):
		return 0.0
	var remaining := hours
	var offset := 0.0
	var weighted := 0.0
	for _index in 50:
		if remaining <= 0.000001:
			break
		var absolute := hour + offset
		var interval := minf(remaining, floorf(absolute + 0.0000001) + 1.0 - absolute)
		var sample := absolute + interval * 0.5
		var target_day := day + int(floorf(sample / 24.0))
		var target_hour := fposmod(sample, 24.0)
		var expected_weather := weather if offset < 3.0 or weather != "风暴" else "多云"
		weighted += spot_at(target_day, target_hour, expected_weather) * interval
		remaining -= interval
		offset += interval
	return snappedf(weighted / hours * 0.96 + 4.0, 0.01)

func set_tariff(mode: String, valley: float, flat: float, peak: float) -> Dictionary:
	if mode not in ["flat", "tou", "custom"]:
		return fail("未知电价方案。")
	for value in [valley, flat, peak]:
		if not _number_in(value, 20.0, 500.0):
			return fail("零售电价须在 20–500 元/MWh 之间。")
	state.tariff_mode = mode
	state.valley_rate = valley
	state.flat_rate = flat
	state.peak_rate = peak
	return ok("零售电价方案已更新。")

func set_policy(mode: String, buy_limit: float, sell_floor: float) -> Dictionary:
	if mode not in ["off", "balanced", "trade"]:
		return fail("未知市场策略。")
	if not _number_in(buy_limit, 0.0, 500.0) or not _number_in(sell_floor, 0.0, 500.0):
		return fail("购售电阈值须在 0–500 元/MWh 之间。")
	state.market_mode = mode
	state.buy_limit = buy_limit
	state.sell_floor = sell_floor
	return ok("市场交易策略已更新。")

func set_storage(mode: String, charge: float, discharge: float, reserve: float) -> Dictionary:
	if mode not in ["reserve", "arbitrage"]:
		return fail("未知储能策略。")
	if not _number_in(charge, 0.0, 500.0) or not _number_in(discharge, 0.0, 500.0) or charge >= discharge:
		return fail("充放电阈值须在 0–500 元/MWh 之间，且充电价低于放电价。")
	if not _number_in(reserve, 0.0, 0.95):
		return fail("备用荷电状态须在 0%–95% 之间。")
	state.storage_mode = mode
	state.charge_price = charge
	state.discharge_price = discharge
	state.reserve_soc = reserve
	return ok("储能策略已更新。")

func sign_contract(mw: float, hours: float, capacity: float, duration_quote: float = -1.0) -> Dictionary:
	if float(state.contract_remaining) > 0.000001:
		return fail("已有履行中的供电合约，不能取消或重复签约。")
	if not _number_in(mw, 0.01, maxf(0.01, capacity)) or mw > capacity + 0.000001:
		return fail("合约功率必须大于零，且不得超过已建联络站的可用容量。")
	if not _number_in(hours, 1.0, 48.0):
		return fail("合约期限须在 1–48 游戏小时之间。")
	state.contract_mw = mw
	state.contract_price = duration_quote if duration_quote > 0.0 else float(state.contract_quote)
	state.contract_remaining = hours
	return ok("固定供电合约已签订：即使未用电或联络中断，也将按约定功率付费。")

func demand_multiplier(kind: String) -> float:
	if kind not in ["home", "factory"]:
		return 1.0
	var elasticity := 0.22 if kind == "home" else 0.30
	var price_response := clampf(1.0 - (float(state.retail_price) / 145.0 - 1.0) * elasticity, 0.55, 1.15)
	# Bill dissatisfaction takes time to become migration/lost industrial load.
	var retention := 1.0 if float(state.satisfaction) >= 60.0 else 0.25 + float(state.satisfaction) / 60.0 * 0.75
	return price_response * retention

func settle(dt: float, day: int, totals: Dictionary) -> void:
	if dt <= 0.0:
		return
	var row: Dictionary = {}
	for entry in ledger:
		if int(entry.day) == day:
			row = entry
			break
	if row.is_empty():
		row = {"day": day}
		for key in LEDGER_FIELDS:
			row[key] = 0.0
		ledger.append(row)
		if ledger.size() > 30:
			ledger.pop_front()
	var rates := {
		"retail_revenue": float(totals.retail_income), "export_revenue": float(totals.export_income),
		"import_cost": float(totals.import_cost), "fuel_cost": float(totals.fuel_cost),
		"maintenance_cost": float(totals.maintenance_cost), "outage_cost": float(totals.outage_cost),
		"contract_cost": float(totals.contract_cost), "net": float(totals.income) - float(totals.expenses),
		"import_mwh": float(totals.import_mw), "export_mwh": float(totals.export_mw), "served_mwh": float(totals.served)
	}
	for key in LEDGER_FIELDS:
		row[key] = float(row[key]) + float(rates[key]) * dt
	var expensive := maxf(0.0, float(state.retail_price) / 145.0 - 1.0)
	var recovery := 0.45 if expensive <= 0.00001 and float(totals.reliability) >= 0.98 else 0.0
	state.satisfaction = clampf(float(state.satisfaction) + dt * (recovery - expensive * 1.8 - (1.0 - float(totals.reliability)) * 8.0), 0.0, 100.0)
	if float(state.contract_remaining) > 0.0:
		state.contract_remaining = maxf(0.0, float(state.contract_remaining) - dt)
		if float(state.contract_remaining) <= 0.000001:
			state.contract_remaining = 0.0
			state.contract_mw = 0.0

func snapshot() -> Dictionary:
	return {"state": state.duplicate(true), "ledger": ledger.duplicate(true)}

func load_snapshot(data: Dictionary) -> bool:
	if not valid_snapshot(data):
		return false
	var restored: Dictionary = data.state.duplicate(true)
	for key in DEFAULT_STATE:
		if not DEFAULT_STATE[key] is String:
			restored[key] = float(restored[key])
	var restored_ledger: Array[Dictionary] = []
	for entry in data.ledger:
		var row: Dictionary = entry.duplicate(true)
		row.day = int(row.day)
		for key in LEDGER_FIELDS:
			row[key] = float(row[key])
		restored_ledger.append(row)
	state = restored
	ledger = restored_ledger
	return true

static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("state") is Dictionary or not data.get("ledger") is Array:
		return false
	var settings: Dictionary = data.state
	for key in DEFAULT_STATE:
		if not settings.has(key):
			return false
		if DEFAULT_STATE[key] is String:
			if not settings[key] is String:
				return false
		elif not _number_in(settings[key], 0.0, 10000.0):
			return false
	if settings.tariff_mode not in ["flat", "tou", "custom"] or settings.market_mode not in ["off", "balanced", "trade"] or settings.storage_mode not in ["reserve", "arbitrage"]:
		return false
	for key in ["valley_rate", "flat_rate", "peak_rate"]:
		if not _number_in(settings[key], 20.0, 500.0):
			return false
	for key in ["buy_limit", "sell_floor", "charge_price", "discharge_price"]:
		if not _number_in(settings[key], 0.0, 500.0):
			return false
	if not _number_in(settings.reserve_soc, 0.0, 0.95) or not _number_in(settings.satisfaction, 0.0, 100.0) or float(settings.charge_price) >= float(settings.discharge_price):
		return false
	if not _number_in(settings.contract_remaining, 0.0, 48.0) or (float(settings.contract_remaining) > 0.0 and (float(settings.contract_mw) <= 0.0 or float(settings.contract_price) <= 0.0)):
		return false
	if data.ledger.size() > 30:
		return false
	var last_day := 0
	for row in data.ledger:
		if not row is Dictionary or not _number_in(row.get("day"), 1.0, 1000000.0) or float(row.day) != floorf(float(row.day)) or int(row.day) <= last_day:
			return false
		last_day = int(row.day)
		for key in LEDGER_FIELDS:
			if not row.has(key) or not _number_in(row[key], -1e15 if key == "net" else 0.0, 1e15):
				return false
	return true

static func _number_in(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func ok(message: String) -> Dictionary:
	return {"ok": true, "message": message, "id": -1}

static func fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "id": -1}
