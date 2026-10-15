class_name PersonBuilder
extends RefCounted
## Builds low-poly people: the hero and the townsfolk of the district.
##
## Rig (all Node3D, origin at the feet, facing -Z):
##   Person
##     Hips (y = 0.92)          – bobs and leans
##       Torso (MeshInstance3D)
##       Head (Node3D) / HeadMesh
##       ArmL, ArmR (shoulder pivots) / mesh / Hand (prop socket)
##       LegL, LegR (hip pivots) / mesh

const SKINS := [Color("e8b48f"), Color("d29a74"), Color("b97e57"), Color("f0c6a0")]

const PRESETS := {
	"hero": {"skin": Color("d9a07a"), "shirt": Color("f4f4f0"), "jacket": Color("1d6f69"), "pants": Color("2c4772"),
		"shoes": Color("f2f2f2"), "hair": Color("1c1714"), "hair_style": "short", "extras": ["backpack"]},
	"man_phone": {"skin": Color("e8b48f"), "shirt": Color("c9473f"), "pants": Color("3b3f47"),
		"shoes": Color("2a2a2a"), "hair": Color("2b1d14"), "hair_style": "short", "extras": ["phone"]},
	"man_backpack": {"skin": Color("d29a74"), "shirt": Color("f2f2ee"), "pants": Color("26406b"),
		"shoes": Color("222222"), "hair": Color("15110e"), "hair_style": "short", "extras": ["backpack"]},
	"man_cap": {"skin": Color("b97e57"), "shirt": Color("3f7d4c"), "pants": Color("5b5348"),
		"shoes": Color("e9e9e9"), "hair": Color("15110e"), "hair_style": "cap", "cap": Color("23324f"), "extras": []},
	"woman_dress": {"skin": Color("f0c6a0"), "shirt": Color("8f3f7a"), "pants": Color("8f3f7a"),
		"shoes": Color("3a2a22"), "hair": Color("3a2416"), "hair_style": "long", "extras": ["dress", "bag"]},
	"woman_scarf": {"skin": Color("e8b48f"), "shirt": Color("2f6f9f"), "pants": Color("2f6f9f"),
		"shoes": Color("2b2b2b"), "hair": Color("e8d8b0"), "hair_style": "scarf", "extras": ["dress"]},
	"elder": {"skin": Color("c98f68"), "shirt": Color("2d3b4f"), "pants": Color("2a2a2a"),
		"shoes": Color("1d1d1d"), "hair": Color("dedede"), "hair_style": "skullcap", "cap": Color("181818"),
		"extras": ["chapan", "beard"]},
	"sweeper": {"skin": Color("b97e57"), "shirt": Color("f08a1c"), "pants": Color("33475e"),
		"shoes": Color("2b2b2b"), "hair": Color("1d1d1d"), "hair_style": "cap", "cap": Color("f08a1c"), "extras": ["broom", "vest"]},
	"student": {"skin": Color("f0c6a0"), "shirt": Color("e7c64a"), "pants": Color("4a5a7a"),
		"shoes": Color("e33b3b"), "hair": Color("2b1d14"), "hair_style": "short", "extras": ["backpack", "phone"]},
}


static func build(preset: String, overrides := {}) -> Node3D:
	var p: Dictionary = PRESETS[preset].duplicate()
	for k in overrides:
		p[k] = overrides[k]
	var extras: Array = p.get("extras", [])
	var root := Node3D.new()
	root.name = "Person_" + preset
	root.set_meta("preset", preset)
	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0, 0.92, 0)
	root.add_child(hips)

	# Torso ---------------------------------------------------------------
	var t := MeshKit.new()
	var shirt: Color = p["shirt"]
	var pants: Color = p["pants"]
	t.box("base", Vector3(0, 0.02, 0), Vector3(0.33, 0.16, 0.20), pants)
	t.taper_box("base", Vector3(0, 0.36, 0), Vector3(0.34, 0.52, 0.21), Vector2(1.22, 1.0), shirt)
	t.cylinder("base", Vector3(0, 0.66, 0), 0.055, 0.1, 8, p["skin"])
	if p.has("jacket"):
		var j: Color = p["jacket"]
		for s: float in [-1.0, 1.0]:
			t.taper_box("base", Vector3(s * 0.13, 0.36, 0.005), Vector3(0.13, 0.54, 0.23), Vector2(1.45, 1.0), j, Vector3(s * 0.03, 0, 0))
		t.taper_box("base", Vector3(0, 0.36, 0.06), Vector3(0.36, 0.54, 0.12), Vector2(1.22, 1.0), j)
		t.box("detail", Vector3(0, 0.63, 0.02), Vector3(0.30, 0.05, 0.22), j.darkened(0.15))
	if extras.has("vest"):
		t.taper_box("base", Vector3(0, 0.36, 0), Vector3(0.36, 0.48, 0.23), Vector2(1.2, 1.0), Color("ffd21c"))
		for y: float in [0.25, 0.42]:
			t.box("detail", Vector3(0, y, -0.118), Vector3(0.34, 0.035, 0.01), Color("e8e8e8"))
	if extras.has("chapan"):
		var c := Color("2e4a7d")
		t.taper_box("base", Vector3(0, 0.22, 0), Vector3(0.44, 0.84, 0.27), Vector2(0.95, 0.95), c, Vector3(0, 0.0, 0))
		for i in 4:
			t.box("detail", Vector3(-0.15 + i * 0.1, 0.22, -0.14), Vector3(0.03, 0.8, 0.01), Color("d6a640"))
		t.box("detail", Vector3(0, 0.3, -0.142), Vector3(0.44, 0.05, 0.01), Color("a8322e"))
	if extras.has("dress"):
		t.taper_box("base", Vector3(0, -0.27, 0), Vector3(0.52, 0.62, 0.36), Vector2(0.62, 0.62), shirt)
	if extras.has("backpack"):
		t.box("base", Vector3(0, 0.36, 0.17), Vector3(0.28, 0.36, 0.13), Color("1f2124"))
		t.box("detail", Vector3(0, 0.28, 0.24), Vector3(0.2, 0.14, 0.02), Color("2c2f34"))
		for s: float in [-1.0, 1.0]:
			t.box("detail", Vector3(s * 0.12, 0.42, -0.108), Vector3(0.04, 0.34, 0.01), Color("1f2124"))
	_mesh(hips, "Torso", t, 0.016)

	# Head ----------------------------------------------------------------
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.70, 0)
	hips.add_child(head)
	var h := MeshKit.new()
	var skin: Color = p["skin"]
	var hair: Color = p["hair"]
	h.taper_box("base", Vector3(0, 0.15, 0), Vector3(0.23, 0.27, 0.25), Vector2(0.95, 0.92), skin)
	h.box("detail", Vector3(0, 0.13, -0.135), Vector3(0.04, 0.06, 0.04), skin.darkened(0.08))
	for s: float in [-1.0, 1.0]:
		h.box("detail", Vector3(s * 0.055, 0.18, -0.126), Vector3(0.035, 0.035, 0.01), Color("1b1b1f"))
		h.box("detail", Vector3(s * 0.055, 0.215, -0.127), Vector3(0.05, 0.012, 0.01), hair.darkened(0.2))
		h.box("base", Vector3(s * 0.12, 0.15, 0.0), Vector3(0.03, 0.07, 0.05), skin)
	h.box("detail", Vector3(0, 0.08, -0.126), Vector3(0.07, 0.014, 0.01), Color("8a4b3e"))
	match p.get("hair_style", "short"):
		"short":
			h.taper_box("base", Vector3(0, 0.29, 0.01), Vector3(0.25, 0.07, 0.27), Vector2(0.85, 0.85), hair)
			h.box("base", Vector3(0, 0.2, 0.11), Vector3(0.24, 0.16, 0.05), hair)
		"long":
			h.taper_box("base", Vector3(0, 0.29, 0.01), Vector3(0.26, 0.08, 0.28), Vector2(0.85, 0.85), hair)
			h.box("base", Vector3(0, 0.08, 0.10), Vector3(0.27, 0.36, 0.08), hair)
		"scarf":
			h.taper_box("base", Vector3(0, 0.17, 0.02), Vector3(0.28, 0.33, 0.29), Vector2(0.75, 0.8), hair)
			h.box("base", Vector3(0, -0.02, 0.06), Vector3(0.3, 0.12, 0.24), hair)
			# keep the face visible
			h.box("detail", Vector3(0, 0.15, -0.131), Vector3(0.17, 0.2, 0.01), skin)
			h.box("detail", Vector3(0, 0.15, -0.127 - 0.008), Vector3(0.04, 0.06, 0.03), skin.darkened(0.08))
			for s: float in [-1.0, 1.0]:
				h.box("detail", Vector3(s * 0.05, 0.18, -0.138), Vector3(0.03, 0.03, 0.01), Color("1b1b1f"))
		"cap":
			var cap: Color = p.get("cap", Color("23324f"))
			h.taper_box("base", Vector3(0, 0.30, 0.01), Vector3(0.26, 0.09, 0.27), Vector2(0.9, 0.9), cap)
			h.box("base", Vector3(0, 0.27, -0.16), Vector3(0.22, 0.025, 0.12), cap)
		"skullcap":
			var cap2: Color = p.get("cap", Color("181818"))
			h.taper_box("base", Vector3(0, 0.30, 0.0), Vector3(0.24, 0.08, 0.26), Vector2(0.85, 0.85), cap2)
			for i in 4:
				var a := TAU * i / 4.0 + 0.78
				h.box("detail", Vector3(sin(a) * 0.12, 0.30, cos(a) * 0.13), Vector3(0.03, 0.03, 0.03), Color("f2f2f2"))
	if extras.has("beard"):
		h.taper_box("base", Vector3(0, 0.03, -0.07), Vector3(0.2, 0.12, 0.13), Vector2(0.8, 1.0), hair)
	_mesh(head, "HeadMesh", h, 0.012)

	# Arms ------------------------------------------------------------------
	var sleeve: Color = p.get("jacket", shirt)
	if extras.has("chapan"):
		sleeve = Color("2e4a7d")
	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		var arm := Node3D.new()
		arm.name = "Arm" + side
		arm.position = Vector3(s * 0.235, 0.6, 0)
		hips.add_child(arm)
		var a := MeshKit.new()
		a.taper_box("base", Vector3(0, -0.16, 0), Vector3(0.11, 0.32, 0.12), Vector2(1.1, 1.1), sleeve)
		a.taper_box("base", Vector3(0, -0.43, 0), Vector3(0.09, 0.24, 0.10), Vector2(1.1, 1.1), sleeve if p.has("jacket") or extras.has("chapan") else skin)
		a.box("base", Vector3(0, -0.6, 0), Vector3(0.085, 0.1, 0.095), skin)
		_mesh(arm, "ArmMesh", a, 0.012)
		var hand := Node3D.new()
		hand.name = "Hand"
		hand.position = Vector3(0, -0.62, 0)
		arm.add_child(hand)
		if side == "R" and extras.has("phone"):
			var ph := MeshKit.new()
			ph.box("base", Vector3(0, 0.0, -0.05), Vector3(0.045, 0.1, 0.012), Color("15161a"))
			ph.box("detail", Vector3(0, 0.0, -0.057), Vector3(0.036, 0.085, 0.004), Color("6fb4ff"))
			_mesh(hand, "Phone", ph, 0.006)
		if side == "R" and extras.has("broom"):
			var b := MeshKit.new()
			b.cylinder("base", Vector3(0, 0.15, 0), 0.018, 1.3, 6, Color("a77b45"))
			b.taper_box("base", Vector3(0, -0.55, 0), Vector3(0.12, 0.28, 0.12), Vector2(0.4, 0.4), Color("c9a65a"))
			_mesh(hand, "Broom", b, 0.008)
		if side == "L" and extras.has("bag"):
			var bg := MeshKit.new()
			bg.box("base", Vector3(0, -0.12, 0), Vector3(0.08, 0.22, 0.28), Color("6b3f2a"))
			bg.box("detail", Vector3(0, 0.03, 0), Vector3(0.02, 0.08, 0.16), Color("4a2c1d"))
			_mesh(hand, "Bag", bg, 0.008)

	# Legs ------------------------------------------------------------------
	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		var leg := Node3D.new()
		leg.name = "Leg" + side
		leg.position = Vector3(s * 0.09, 0.0, 0)
		hips.add_child(leg)
		var l := MeshKit.new()
		var leg_col: Color = skin if extras.has("dress") else pants
		l.taper_box("base", Vector3(0, -0.4, 0), Vector3(0.14, 0.8, 0.16), Vector2(1.25, 1.15), leg_col)
		l.taper_box("base", Vector3(0, -0.855, -0.035), Vector3(0.12, 0.09, 0.26), Vector2(0.95, 0.85), p["shoes"])
		l.box("detail", Vector3(0, -0.893, -0.035), Vector3(0.125, 0.015, 0.265), Color("f0f0f0") if p["shoes"].v < 0.5 else Color("bdbdbd"))
		_mesh(leg, "LegMesh", l, 0.012)

	_own(root, root)
	return root


static func _mesh(parent: Node3D, name: String, kit: MeshKit, outline: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = kit.build(Mats.for_model(outline))
	parent.add_child(mi)
	return mi


static func _own(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_own(c, owner)
