class_name GridScenarioMap
extends RefCounted
## Historical locations are schematic playable maps, not surveyed reconstructions.
## Terrain cells also drive siting checks; scenery never changes electrical physics.

const CHAPTERS := [
	["new_york_1882", "city_blocks", "纽约 · 珍珠街", "1882"],
	["lauffen_1891", "river_valley", "劳芬—法兰克福", "1891"],
	["shanghai_1913", "city_blocks", "上海 · 杨树浦", "1913"],
	["britain_1930s", "river_valley", "英国 · 区域互联", "1930年代"],
	["tennessee_1936", "river_valley", "田纳西河谷 · 诺里斯", "1936"],
	["gotland_1954", "mountain_coast", "瑞典 · 哥特兰", "1954"],
	["shippingport_1957", "river_valley", "美国 · 希平港", "1957"],
	["cruachan_1965", "mountain_coast", "苏格兰 · 克鲁阿坎", "1965"],
	["britain_1990", "city_blocks", "英格兰与威尔士", "1990"],
	["denmark_2002", "mountain_coast", "丹麦 · 日德兰西岸", "2002"],
	["northwest_2010", "river_valley", "美国 · 太平洋西北", "2010—2012"],
	["northwest_2012", "river_valley", "美国 · 太平洋西北", "2012—2014"],
	["chattanooga_2014", "river_valley", "美国 · 查塔努加", "2014"],
	["ukraine_2015", "city_blocks", "乌克兰 · 西部配电区", "2015"],
	["south_australia_2017", "mountain_coast", "澳大利亚 · 南澳", "2017—2023"]
]

static func for_chapter(id: int) -> Dictionary:
	if id < 1 or id > CHAPTERS.size():
		return {}
	var entry: Array = CHAPTERS[id - 1]
	var map_size := 16 if id <= 4 else 48
	var river: Array[Vector2i] = []
	var hills: Array[Vector2i] = []
	if map_size == 16:
		if id in [1, 3]:
			_add_rect(river, 14, 1, 15, 14)
		else:
			_add_rect(river, 2, 1, 4, 3)
			for y in range(4, 15):
				river.append(Vector2i(2 + (y / 4) % 2, y))
		_add_rect(hills, 12, 12, 15, 15)
	else:
		# Shared schematic coordinates keep the introductory siting targets legible.
		_add_rect(river, 18, 1, 46, 5)
		if str(entry[1]) == "river_valley":
			for y in range(6, 47):
				var x := 18 + (y / 7 + id) % 3
				_add_rect(river, x, y, x + 1, y)
		_add_rect(hills, 26, 24, 46, 46)
	var settlements: Array = []
	if id == 5:
		settlements = [{"name":"诺里斯镇", "anchor":Vector2i(9, 7), "role":"农业", "population":1800.0}]
	elif id == 15:
		settlements = [
			{"name":"阿德莱德街区", "anchor":Vector2i(8, 7), "role":"居住", "population":3600.0},
			{"name":"工业用电区", "anchor":Vector2i(12, 10), "role":"工业", "population":2400.0},
			{"name":"沿海服务区", "anchor":Vector2i(7, 12), "role":"服务", "population":1600.0}
		]
	return {"id":str(entry[0]), "size":map_size, "theme":str(entry[1]),
		"location":str(entry[2]), "years":str(entry[3]), "chapter":id,
		"river_cells":river, "hill_cells":hills, "settlements":settlements,
		"camera_start":Vector2i(8, 7), "modern":id >= 9}

static func is_river(spec: Dictionary, cell: Vector2i) -> bool:
	return cell in spec.get("river_cells", [])

static func is_hill(spec: Dictionary, cell: Vector2i) -> bool:
	return cell in spec.get("hill_cells", [])

static func _add_rect(cells: Array[Vector2i], left: int, top: int, right: int, bottom: int) -> void:
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			var cell := Vector2i(x, y)
			if cell not in cells:
				cells.append(cell)
