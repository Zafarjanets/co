extends Node
## Global game state: money, owned-car setup, settings, save/load, input map.
##
## The save is a small JSON file in user://. Loading is defensive: unknown or
## broken values fall back to defaults, a corrupt file is kept as .bak and the
## game starts fresh instead of crashing.

signal money_changed(value: int)
signal settings_changed
signal car_config_changed(kind: String)

const SAVE_PATH := "user://rayon_save.json"
const SAVE_VERSION := 1
const START_MONEY := 400

## Repaint palette for civilian cars.
const PAINTS := [
	["Белый", Color("f4f2ec")], ["Горчичный", Color("d9a531")], ["Красный", Color("c8352e")],
	["Бирюзовый", Color("2a9d93")], ["Синий", Color("2f5fa8")], ["Чёрный", Color("26272b")],
	["Серебро", Color("b9bec6")], ["Оливковый", Color("6f7d3a")],
]
const RIMS := [["sport", "Спортивные (5 спиц)"], ["steel", "Стальные"]]
const PRICE_PAINT := 150
const PRICE_RIMS := 200
const PRICE_ENGINE := [600, 1200, 2000]
const PRICE_GRIP := [500, 1000, 1700]
const CIVIL_CARS := ["sado", "chabuk", "m5", "cls"]
## Cars sold in the garage (the first two are owned from the start).
const CAR_INFO := {
	"sado": {"title": "SADO", "desc": "седан, задний привод", "price": 0},
	"chabuk": {"title": "CHABUK", "desc": "хэтчбек, передний привод", "price": 0},
	"m5": {"title": "M5", "desc": "мощный седан, задний привод", "price": 4000},
	"cls": {"title": "CLS", "desc": "бизнес-седан, задний привод", "price": 3000},
}

var data := {}
var save_error := ""      # human-readable note if the last load had to repair something


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_game()


# --- defaults & validation -----------------------------------------------------

func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"money": START_MONEY,
		"car": "sado",
		"cars": {
			"sado": {"paint": 0, "rims": "sport", "engine": 0, "grip": 0},
			"chabuk": {"paint": 1, "rims": "steel", "engine": 0, "grip": 0},
			"m5": {"paint": -1, "rims": "sport", "engine": 0, "grip": 0},
			"cls": {"paint": -1, "rims": "sport", "engine": 0, "grip": 0},
		},
		"owned": ["sado", "chabuk"],
		"settings": {"volume": 0.8, "quality": 2, "sensitivity": 1.0, "invert_y": false},
		"stats": {"missions": {}, "best_ring": 0.0},
	}


func _validated(raw: Variant) -> Dictionary:
	var d := default_data()
	if typeof(raw) != TYPE_DICTIONARY:
		save_error = "Сохранение повреждено — начата новая игра."
		return d
	var r: Dictionary = raw
	d["money"] = clampi(int(_num(r.get("money"), START_MONEY)), 0, 99_999_999)
	var car = r.get("car")
	if typeof(car) == TYPE_STRING and car in CIVIL_CARS:
		d["car"] = car
	var cars = r.get("cars")
	if typeof(cars) == TYPE_DICTIONARY:
		for k in CIVIL_CARS:
			var c = cars.get(k)
			if typeof(c) != TYPE_DICTIONARY:
				continue
			d["cars"][k]["paint"] = clampi(int(_num(c.get("paint"), d["cars"][k]["paint"])), -1, PAINTS.size() - 1)
			var rims = c.get("rims")
			if typeof(rims) == TYPE_STRING and (rims == "sport" or rims == "steel"):
				d["cars"][k]["rims"] = rims
			d["cars"][k]["engine"] = clampi(int(_num(c.get("engine"), 0)), 0, PRICE_ENGINE.size())
			d["cars"][k]["grip"] = clampi(int(_num(c.get("grip"), 0)), 0, PRICE_GRIP.size())
	var owned = r.get("owned")
	if typeof(owned) == TYPE_ARRAY:
		for k in owned:
			if typeof(k) == TYPE_STRING and k in CIVIL_CARS and not k in d["owned"]:
				d["owned"].append(k)
	if not d["car"] in d["owned"]:
		d["car"] = "sado"
	var st = r.get("settings")
	if typeof(st) == TYPE_DICTIONARY:
		d["settings"]["volume"] = clampf(_num(st.get("volume"), 0.8), 0.0, 1.0)
		d["settings"]["quality"] = clampi(int(_num(st.get("quality"), 2)), 0, 2)
		d["settings"]["sensitivity"] = clampf(_num(st.get("sensitivity"), 1.0), 0.2, 3.0)
		d["settings"]["invert_y"] = st.get("invert_y") == true
	var stats = r.get("stats")
	if typeof(stats) == TYPE_DICTIONARY:
		var ms = stats.get("missions")
		if typeof(ms) == TYPE_DICTIONARY:
			for k in ms:
				if typeof(k) == TYPE_STRING:
					d["stats"]["missions"][k] = clampi(int(_num(ms[k], 0)), 0, 100000)
		d["stats"]["best_ring"] = clampf(_num(stats.get("best_ring"), 0.0), 0.0, 10000.0)
	return d


func _num(v: Variant, fallback: float) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		if is_nan(float(v)) or is_inf(float(v)):
			return fallback
		return float(v)
	return fallback


# --- save / load -------------------------------------------------------------------

func load_game() -> void:
	save_error = ""
	if not FileAccess.file_exists(SAVE_PATH):
		data = default_data()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		data = default_data()
		save_error = "Не удалось открыть сохранение — начата новая игра."
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".bak"))
		data = default_data()
		save_error = "Сохранение повреждено (копия в rayon_save.json.bak) — начата новая игра."
		return
	data = _validated(json.data)


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		push_warning("RAYON: cannot write save")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# Replace atomically so a crash mid-write never leaves a half file.
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH))


func reset_progress() -> void:
	var keep: Dictionary = data.get("settings", {}).duplicate()
	data = default_data()
	data["settings"] = _validated({"settings": keep})["settings"]
	save_game()
	money_changed.emit(money())
	for k in CIVIL_CARS:
		car_config_changed.emit(k)


# --- money & cars --------------------------------------------------------------------

func money() -> int:
	return int(data.get("money", 0))


func add_money(amount: int) -> void:
	data["money"] = clampi(money() + amount, 0, 99_999_999)
	save_game()
	money_changed.emit(money())


func spend(amount: int) -> bool:
	if money() < amount:
		return false
	data["money"] = money() - amount
	save_game()
	money_changed.emit(money())
	return true


## Applies a fine; returns the amount actually taken.
func fine(amount: int) -> int:
	var taken := mini(amount, money())
	data["money"] = money() - taken
	save_game()
	money_changed.emit(money())
	return taken


func selected_car() -> String:
	return data.get("car", "sado")


func select_car(kind: String) -> void:
	if kind in CIVIL_CARS:
		data["car"] = kind
		save_game()
		car_config_changed.emit(kind)


func car_setup(kind: String) -> Dictionary:
	return data["cars"].get(kind, default_data()["cars"]["sado"])


## Config dictionary understood by Car.apply_config().
func car_config(kind: String) -> Dictionary:
	var s := car_setup(kind)
	var cfg := {"rims": s["rims"], "engine": s["engine"], "grip": s["grip"]}
	if int(s["paint"]) >= 0:
		cfg["paint"] = PAINTS[s["paint"]][1]
	return cfg


func owns(kind: String) -> bool:
	return kind in data.get("owned", [])


## Buys a car in the garage. Returns false when there isn't enough money.
func buy_car(kind: String) -> bool:
	if owns(kind):
		return true
	if not spend(int(CAR_INFO[kind]["price"])):
		return false
	data["owned"].append(kind)
	save_game()
	return true


func set_car_value(kind: String, key: String, value) -> void:
	data["cars"][kind][key] = value
	save_game()
	car_config_changed.emit(kind)


func mission_done(id: String) -> void:
	var ms: Dictionary = data["stats"]["missions"]
	ms[id] = int(ms.get(id, 0)) + 1
	save_game()


# --- settings --------------------------------------------------------------------------

func setting(key: String):
	return data["settings"].get(key)


func set_setting(key: String, value) -> void:
	data["settings"][key] = value
	save_game()
	settings_changed.emit()


# --- input --------------------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN],
		"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT], "handbrake": [KEY_SPACE], "interact": [KEY_E],
		"recover": [KEY_R], "pause": [KEY_ESCAPE], "retry": [KEY_ENTER, KEY_KP_ENTER],
		"map_zoom": [KEY_M], "horn": [KEY_H],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
