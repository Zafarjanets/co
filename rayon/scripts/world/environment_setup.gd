class_name EnvironmentSetup
extends RefCounted
## Sunny day: blue sky, warm sun with soft shadows, light haze for depth.

static func create(parent: Node) -> DirectionalLight3D:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("3f8fd8")
	sm.sky_horizon_color = Color("b5dcf2")
	sm.ground_horizon_color = Color("b5dcf2")
	sm.ground_bottom_color = Color("8fae7c")
	sm.sun_angle_max = 20.0
	sm.sky_curve = 0.12
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aab4c4")
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.tonemap_white = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color("b9d8ee")
	env.fog_density = 0.00016
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -38, 0)
	sun.light_color = Color("fff3df")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_fade_start = 0.85
	parent.add_child(sun)
	return sun
