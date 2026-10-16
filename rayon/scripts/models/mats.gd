class_name Mats
extends RefCounted
## Shared materials for the flat, toon-shaded look.
##
## Surface names used by the model builders map to materials here:
##   base   – vertex colour, outlined
##   detail – vertex colour, no outline (windows, small trims, markings)
##   paint  – vertex colour tinted by a per-instance paint colour, outlined
##   glass  – dark glass with a soft highlight
##   lamp   – lights that glow a little (headlights, shop signs)
##   glow   – strong emissive (police light bar), animated at runtime

const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")

static var _cache := {}
static var outline_scale := 1.0      # set by the quality setting


static func outline(thickness: float) -> ShaderMaterial:
	var key := "outline_%.3f" % thickness
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("thickness", thickness)
	m.set_shader_parameter("outline_scale", outline_scale)
	_cache[key] = m
	return m


static func _base(outline_px: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if outline_px > 0.0:
		m.next_pass = outline(outline_px)
	return m


static func base(outline_thickness := 0.025) -> StandardMaterial3D:
	var key := "base_%.3f" % outline_thickness
	if not _cache.has(key):
		_cache[key] = _base(outline_thickness)
	return _cache[key]


static func detail() -> StandardMaterial3D:
	if not _cache.has("detail"):
		_cache["detail"] = _base(0.0)
	return _cache["detail"]


static func paint(color: Color, outline_thickness := 0.022, glossy := true) -> StandardMaterial3D:
	var m := _base(outline_thickness)
	m.albedo_color = color
	if glossy:
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = 0.45
	return m


static func glass() -> StandardMaterial3D:
	if not _cache.has("glass"):
		var m := _base(0.0)
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = 0.25
		_cache["glass"] = m
	return _cache["glass"]


static func lamp() -> StandardMaterial3D:
	if not _cache.has("lamp"):
		var m := _base(0.0)
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 0.25
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_cache["lamp"] = m
	return _cache["lamp"]


static func glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


static func marker(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


## Soft, glossy look for the FR-Legends-style cars (smooth shading, shiny paint).
static func car_paint(color: Color, outline_thickness := 0.012) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.roughness = 0.28
	m.metallic_specular = 0.7
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	if outline_thickness > 0.0:
		m.next_pass = outline(outline_thickness)
	return m


static func for_car(paint_color: Color, outline_thickness := 0.012) -> Dictionary:
	var key := "car_%.3f" % outline_thickness
	if not _cache.has(key):
		var base_m := StandardMaterial3D.new()
		base_m.vertex_color_use_as_albedo = true
		base_m.vertex_color_is_srgb = true
		base_m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		base_m.roughness = 0.6
		if outline_thickness > 0.0:
			base_m.next_pass = outline(outline_thickness)
		var detail_m := base_m.duplicate()
		detail_m.next_pass = null
		var glass_m := StandardMaterial3D.new()
		glass_m.vertex_color_use_as_albedo = true
		glass_m.vertex_color_is_srgb = true
		glass_m.roughness = 0.12
		glass_m.metallic_specular = 0.9
		glass_m.rim_enabled = true
		glass_m.rim = 0.4
		var lamp_m := detail_m.duplicate()
		lamp_m.emission_enabled = true
		lamp_m.emission = Color(1, 1, 1)
		lamp_m.emission_energy_multiplier = 0.35
		lamp_m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_cache[key] = {"base": base_m, "detail": detail_m, "glass": glass_m, "lamp": lamp_m}
	var d: Dictionary = _cache[key].duplicate()
	d["paint"] = car_paint(paint_color, outline_thickness)
	return d


## Standard surface → material map for a model.
static func for_model(outline_thickness := 0.025, paint_color := Color.WHITE) -> Dictionary:
	return {
		"base": base(outline_thickness),
		"detail": detail(),
		"paint": paint(paint_color, outline_thickness),
		"glass": glass(),
		"lamp": lamp(),
	}
