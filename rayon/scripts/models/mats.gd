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


static func outline(thickness: float) -> ShaderMaterial:
	var key := "outline_%.3f" % thickness
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("thickness", thickness)
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


static func paint(color: Color, outline_thickness := 0.022) -> StandardMaterial3D:
	var m := _base(outline_thickness)
	m.albedo_color = color
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


## Standard surface → material map for a model.
static func for_model(outline_thickness := 0.025, paint_color := Color.WHITE) -> Dictionary:
	return {
		"base": base(outline_thickness),
		"detail": detail(),
		"paint": paint(paint_color, outline_thickness),
		"glass": glass(),
		"lamp": lamp(),
	}
