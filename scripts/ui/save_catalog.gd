extends RefCounted
## Menu inspection validates in an isolated model; it never replaces the live session.
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Catalog = preload("res://scripts/sim/campaign_catalog.gd")

static func inspect(paths: Array, filter: String="") -> Dictionary:
	var candidates: Array[Dictionary] = []
	var invalid: Array[String] = []
	for path_value in paths:
		var path: String = str(path_value)
		if not FileAccess.file_exists(path): continue
		var preview: RefCounted = Sim.new()
		var result: Dictionary = preview.load_game(path)
		if not result.get("ok",false):
			invalid.append(path)
			continue
		var mode: String = "campaign" if preview.campaign.active else ("management" if preview.management.state.active else "sandbox")
		if not filter.is_empty() and mode != filter: continue
		var title: String = {"campaign":"教学战役","management":"经营路线","sandbox":"自由沙盘"}[mode]
		var detail: String = "第 %d 天 %02d:%02d" % [int(preview.day),int(preview.time_hours),int(fmod(preview.time_hours,1.0)*60)]
		if mode == "campaign":
			title += " · 第 %02d 章" % int(preview.campaign.chapter_id)
			detail = str(Catalog.get_chapter(int(preview.campaign.chapter_id)).get("title","")) + " · " + detail
		var modified: int = FileAccess.get_modified_time(path)
		var local_stamp: int = modified + int(Time.get_time_zone_from_system().get("bias",0))*60
		var stamp: String = Time.get_datetime_string_from_unix_time(local_stamp).replace("T"," ")
		candidates.append({"path":path,"mode":mode,"title":title,"detail":detail,"modified":modified,"saved_at":stamp,"rank":candidates.size(),"automatic":"auto" in path.get_file(),"chapter":int(preview.campaign.chapter_id) if mode=="campaign" else 0})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary):
		if int(a.modified)==int(b.modified):
			if a.automatic!=b.automatic: return not a.automatic
			return int(a.rank)<int(b.rank)
		return int(a.modified)>int(b.modified)
	)
	return {"candidates":candidates,"invalid":invalid,"latest":candidates[0] if not candidates.is_empty() else {}}
