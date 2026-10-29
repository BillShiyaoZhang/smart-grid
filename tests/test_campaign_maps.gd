extends SceneTree

const Maps = preload("res://scripts/sim/scenario_map.gd")
const Island = preload("res://scripts/art/island_factory.gd")
const Region = preload("res://scripts/sim/region_world.gd")
const Overview = preload("res://scripts/ui/region_map.gd")
var checks := 0
var failures := 0

class ScenarioSim extends RefCounted:
	var buildings: Array[Dictionary] = []
	var lines: Array = []
	var time_hours := 8.0
	var extent := 48
	var region: RefCounted
	func map_size() -> int:
		return extent
	func get_building(id: int) -> Dictionary:
		for building in buildings:
			if int(building.id) == id:
				return building
		return {}
	func building_at(cell: Vector2i) -> Dictionary:
		for building in buildings:
			if building.cell == cell:
				return building
		return {}

func _initialize() -> void:
	_test_map_contract()
	_test_landscape_generation()
	_test_scenario_cities()
	_test_city_save_compatibility()
	_test_overview_extent()
	print("CAMPAIGN MAP TESTS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _test_map_contract() -> void:
	var identities := {}
	var themes := {}
	for chapter in range(1, 16):
		var spec: Dictionary = Maps.for_chapter(chapter)
		check(not spec.is_empty() and not identities.has(spec.id), "every historical chapter has a distinct map identity")
		identities[spec.id] = true
		themes[spec.theme] = true
		check(int(spec.size) == (16 if chapter <= 4 else 48), "chapter map extent is explicit")
		check(bool(spec.modern) == (chapter >= 9), "early maps omit modern transport and road markings")
		check(spec.camera_start == Vector2i(8, 7), "camera starts near the actual playable facilities")
		for key in ["river_cells", "hill_cells"]:
			var seen := {}
			var valid: bool = not spec[key].is_empty()
			for cell in spec[key]:
				valid = valid and cell is Vector2i and cell.x >= 0 and cell.y >= 0 and cell.x < spec.size and cell.y < spec.size and not seen.has(cell)
				seen[cell] = true
			check(valid, "terrain cells are unique and stay inside the chapter map")
		if chapter >= 5:
			check(Maps.is_river(spec, Vector2i(18, 3)) and Maps.is_hill(spec, Vector2i(28, 28)), "large maps expose the introductory hydro and pumped-storage siting targets")
	check(themes.size() == 3, "campaign has city, river valley and mountain coast landscape families")
	check(Maps.is_river(Maps.for_chapter(2), Vector2i(3, 3)), "Lauffen has a river at the historical chapter's initial generator")
	check(Maps.for_chapter(0).is_empty() and Maps.for_chapter(16).is_empty(), "unknown chapters do not silently select an unrelated map")
	var first := Maps.for_chapter(5)
	first.river_cells.clear()
	check(not Maps.for_chapter(5).river_cells.is_empty(), "map callers cannot mutate later chapter specifications")

func _test_landscape_generation() -> void:
	for chapter in range(1, 16):
		var spec: Dictionary = Maps.for_chapter(chapter)
		var landscape: Node3D = Island.create_for_map(spec)
		check(landscape.get_meta("map_id") == spec.id and int(landscape.get_meta("playable_size")) == spec.size, "rendered landscape carries the scenario identity and extent")
		check(landscape.has_node("RiverTerrain") and landscape.has_node("HillTerrain"), "siting terrain is visible in the actual landscape")
		check(landscape.has_node("UtilityVan") == bool(spec.modern) and landscape.has_node("ModernRoadMarkings") == bool(spec.modern), "modern decorations follow the historical period")
		landscape.free()
	var legacy: Node3D = Island.create()
	check(legacy.name == "BayIsland" and legacy.has_node("UtilityVan"), "legacy sandbox landscape keeps its default semantics")
	legacy.free()

func _customer(id: int, cell: Vector2i, city_id: int = -1) -> Dictionary:
	var building := {"id":id, "kind":"home", "cell":cell, "base_demand":2.0, "demand":2.0, "served":2.0}
	if city_id >= 0:
		building.city_id = city_id
	return building

func _test_scenario_cities() -> void:
	var sim := ScenarioSim.new()
	sim.region = Region.new()
	sim.buildings.assign([_customer(1, Vector2i(8, 7)), _customer(2, Vector2i(11, 8))])
	var count_before := sim.buildings.size()
	var result: Dictionary = sim.region.seed_from_scenario(sim, Maps.for_chapter(5).settlements)
	check(result.ok and sim.region.cities.size() == 1 and sim.region.cities[0].name == "诺里斯镇", "TVA begins with the named scenario community")
	check(sim.buildings.size() == count_before and sim.lines.is_empty(), "scenario registration creates no free assets or surprise unserved towns")
	check(sim.region.cities[0].building_ids.size() == 2 and is_equal_approx(sim.region.cities[0].service, 1.0), "scenario city feedback reflects its existing electrical customers")
	check(not sim.region.seed_from_scenario(sim, Maps.for_chapter(5).settlements).ok, "scenario city seeding cannot duplicate population")
	sim.region = Region.new()
	sim.buildings.assign([_customer(1, Vector2i(8, 7), 1), _customer(2, Vector2i(7, 12))])
	check(sim.region.seed_from_scenario(sim, Maps.for_chapter(15).settlements).ok and sim.region.cities.size() == 3, "final chapter uses its three named districts")
	check(sim.buildings[0].city_id == 1 and sim.buildings[1].city_id == 2, "explicit city registration wins; unspecified customers use the nearest district")
	var invalid := Region.new()
	check(not invalid.seed_from_scenario(sim, [{"name":"invalid", "anchor":Vector2i(80, 2), "role":"工业", "population":100.0}]).ok and not invalid.active, "invalid chapter seeds leave the region unchanged")
	sim.extent = 16
	var compact := Region.new()
	check(compact.seed_from_scenario(sim, [{"name":"街区", "anchor":Vector2i(13, 13), "role":"居住", "population":100.0}]).ok, "city evolution also supports compact scenario maps")
	var free: Vector2i = compact._free_cell(sim, Vector2i(14, 14))
	check(free.x >= 1 and free.y >= 1 and free.x <= 14 and free.y <= 14, "city expansion uses the scenario boundary")

func _test_city_save_compatibility() -> void:
	for count in range(1, 9):
		var sim := ScenarioSim.new()
		var cities: Array = []
		for index in count:
			cities.append({"name":"情景城市%d" % index, "anchor":Vector2i(2 + index * 3, 6), "role":"居住", "population":1000.0})
		var region := Region.new()
		region.seed_from_scenario(sim, cities)
		var saved: Dictionary = region.snapshot()
		var restored := Region.new()
		check(Region.valid_snapshot(saved) and restored.load_snapshot(saved) and restored.cities.size() == count, "one through eight scenario cities survive persistence")
		if count == 8:
			saved.erase("map_size")
			check(Region.valid_snapshot(saved) and restored.load_snapshot(saved) and restored.map_extent == 48, "legacy eight-city saves default to the original region extent")
	var inactive := Region.new()
	check(Region.valid_snapshot(inactive.snapshot()), "inactive sandbox region snapshots remain valid")
	var malformed: Dictionary = inactive.snapshot()
	malformed.active = true
	check(not Region.valid_snapshot(malformed), "an active empty region is rejected")
	malformed = inactive.snapshot()
	malformed.map_size = 20
	check(not Region.valid_snapshot(malformed), "unsupported scenario extents are rejected")

func _test_overview_extent() -> void:
	var sim := ScenarioSim.new()
	var overview: Control = Overview.new()
	overview.sim = sim
	overview.size = Vector2(400, 300)
	sim.extent = 16
	var compact_edge: Vector2 = overview._position(Vector2i(15, 15))
	sim.extent = 48
	var regional_edge: Vector2 = overview._position(Vector2i(47, 47))
	check(compact_edge.is_equal_approx(regional_edge), "regional overview scales to each map's real extent")
	overview.free()
