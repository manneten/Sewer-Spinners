extends Node2D

@onready var _ko_label: Label    = $HUD/KOLabel
@onready var _camera:   Camera2D = $Camera2D

const ARENA_CENTER:         Vector2 = Vector2(576.0, 324.0)
const CENTER_ZONE_RADIUS:   float   = 60.0
const CENTER_AFK_TIME:      float   = 2.0
const CENTER_FLING_IMPULSE: float   = 400.0

const ABYSS_CHECK_INTERVAL: float = 0.15  # seconds between floor-pixel KO checks
const MATCH_TIME_LIMIT:     float = 45.0  # real seconds before walls shatter
const COUNTDOWN_WARN_AT:    float = 15.0  # seconds remaining when the countdown appears

var _shake_intensity: float      = 0.0
var _shake_timer:     float      = 0.0
var _center_timers:   Dictionary = {}
var _match_over:      bool       = false
var _zoom_tween:      Tween      = null          # tracked so force_camera_reset can kill it immediately
var _zoom_watchdog:   float      = 0.0          # real-time accumulator; triggers failsafe at 0.8 s
var _base_zoom:       Vector2    = Vector2.ONE  # set from camera in _ready(); the true "zoomed-out" value

var _floor_image:       Image   = null        # pixel map of 03_arena_floor.png for abyss detection
var _abyss_check_t:     float   = 0.0         # countdown between pixel checks
var _floor_world_origin: Vector2 = Vector2.ZERO  # top-left of floor sprite in world space
var _floor_world_scale:  Vector2 = Vector2.ONE   # world units per floor image pixel

var _wins_label:    Label = null
var _strikes_label: Label = null
var _faction_label: Label = null

var _match_elapsed:    float        = -1.0  # real-time seconds since fight started; -1 = inactive
var _last_countdown:   int          = -1    # last integer shown; prevents redundant pulses
var _countdown_canvas: CanvasLayer  = null
var _countdown_label:  Label        = null

# ── Enemy faction ─────────────────────────────────────────────────────────────
enum Faction { FAT_RATS, WIGGLY_WORM, CROCO_LOCO }

const FACTION_NAMES: Dictionary = {
	Faction.FAT_RATS:    "FAT RATS",
	Faction.WIGGLY_WORM: "WIGGLY WORM",
	Faction.CROCO_LOCO:  "CROCO LOCO",
}
const FACTION_IDS: Dictionary = {
	Faction.FAT_RATS:    "fat_rats",
	Faction.WIGGLY_WORM: "wiggly_worm",
	Faction.CROCO_LOCO:  "croco_loco",
}

var _enemy_faction:    int         = Faction.FAT_RATS
var _enemy_faction_id: String      = "fat_rats"
var _enemy_node:       RigidBody2D = null

const RARE_LIMB_CHANCE: float = 0.25
const RARE_LIMB_POOL: Array[String] = [
	"res://resources/parts/limb_sewer_slapper.tres",
	"res://resources/parts/limb_sewer_harpoon.tres",
	"res://resources/parts/limb_sludge_sponge.tres",
]

const _POST_MATCH_LOOT  = preload("res://scripts/ui/PostMatchLoot.gd")
const _BANKRUPT_SCREEN  = preload("res://scripts/ui/BankruptScreen.gd")
const _SHOP_SCREEN      = preload("res://scripts/ui/ShopScreen.gd")
const _PROGRESS_SCREEN  = preload("res://scripts/ui/ProgressScreen.gd")
const _BEY_AI           = preload("res://scripts/physics/BeyAI.gd")
const _SEWER_SPLASH     = preload("res://scenes/effects/SewerSplash.tscn")

var _entry_drop_pending: bool = false

func _process(delta: float) -> void:
	# Entry drops: fires on the first unpaused frame after loadouts are applied.
	if _entry_drop_pending and not _match_over:
		_entry_drop_pending = false
		_do_entry_drop()

	# Zoom watchdog: if camera stays zoomed for > 1.5 real seconds, force-reset.
	# real_delta compensates for slow-mo (Engine.time_scale < 1) so the 1.5 s
	# threshold is always wall-clock seconds, not dilated game-time.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	if _camera.zoom.x > _base_zoom.x + 0.01:
		_zoom_watchdog += real_delta
		if _zoom_watchdog >= 0.8:
			_zoom_watchdog = 0.0
			Events.reset_time()  # invalidates stale slow-mo sessions; emits global_camera_reset
	else:
		_zoom_watchdog = 0.0

	# Match time limit: shatter all walls if nobody is KO'd within MATCH_TIME_LIMIT seconds.
	if _match_elapsed >= 0.0 and not _match_over:
		_match_elapsed += real_delta
		var remaining := MATCH_TIME_LIMIT - _match_elapsed
		if remaining <= 0.0:
			_match_elapsed = -1.0
			_trigger_wall_break()
		elif remaining <= COUNTDOWN_WARN_AT:
			if _countdown_label == null:
				_create_countdown_label()
			var sec := ceili(remaining)
			if sec != _last_countdown:
				_last_countdown = sec
				if is_instance_valid(_countdown_label):
					_countdown_label.text = str(sec)
					_pulse_countdown()

	# Camera shake.
	if _shake_timer > 0.0:
		_shake_timer -= delta
		if _shake_timer > 0.0:
			_camera.offset = Vector2(
				randf_range(-_shake_intensity, _shake_intensity),
				randf_range(-_shake_intensity, _shake_intensity)
			)
		else:
			_camera.offset = Vector2.ZERO

	# Floor-pixel abyss detection: KO any bey standing on a transparent pixel.
	if _floor_image:
		_abyss_check_t -= real_delta
		if _abyss_check_t <= 0.0:
			_abyss_check_t = ABYSS_CHECK_INTERVAL
			_check_floor_abyss()

	# Anti-AFK center repulsion: beys loitering in the center get kicked out.
	for bey_name: String in ["Player_Red", "Player_Blue"]:
		var bey := get_node_or_null(bey_name)
		if not bey or not bey.has_method("force_ko"):
			continue
		var dist: float = (bey.global_position - ARENA_CENTER).length()
		# Outer void: bey flew through a broken wall gap — instant KO.
		# Skip beys mid-entry-drop — they're intentionally outside the arena.
		if dist > 536.0 and not _match_over and bey.has_method("force_ko") \
				and not bey.has_meta("entering"):
			bey.force_ko()
			continue

		if dist < CENTER_ZONE_RADIUS:
			_center_timers[bey] = _center_timers.get(bey, 0.0) + delta
			if _center_timers[bey] >= CENTER_AFK_TIME:
				_center_timers[bey] = 0.0
				bey.apply_central_impulse(Vector2.RIGHT.rotated(randf() * TAU) * CENTER_FLING_IMPULSE)
				_spawn_water_splash(bey.global_position)
		else:
			_center_timers[bey] = 0.0

func shake_screen(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_timer     = duration

# Zooms in and enters slow-mo for the Croco Death Lunge shiver wind-up.
# Does NOT auto-return — call reset_zoom() when the shiver ends.
func zoom_to_point(_world_pos: Vector2, zoom_level: float, _hold_duration: float) -> void:
	Events.set_slow_mo(0.15)
	if is_instance_valid(_zoom_tween):
		_zoom_tween.kill()
	# Compensate for slow-mo so the zoom-in completes in real-time (~0.12s).
	_zoom_tween = create_tween()
	_zoom_tween.set_speed_scale(1.0 / Engine.time_scale)
	_zoom_tween.tween_property(_camera, "zoom", Vector2(zoom_level, zoom_level), 0.12) \
		.set_ease(Tween.EASE_OUT)

# Nuclear camera reset — no guards, no conditions, no smooth tween.
# Godot 4 has no kill_tweens_of() API; we track the single zoom tween in
# _zoom_tween and kill it explicitly. All camera-modifying code stores its
# tween there (or calls arena.set("_zoom_tween", ...) from LimbManager).
# Connected to Events.global_camera_reset; also triggered by the watchdog.
func force_camera_reset() -> void:
	Engine.time_scale = 1.0
	_zoom_watchdog = 0.0
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = null
	_camera.zoom   = _base_zoom
	_camera.offset = Vector2.ZERO

# Legacy alias — kept so older callsites still compile.
func reset_camera_immediately() -> void:
	force_camera_reset()

func get_base_zoom() -> Vector2:
	return _base_zoom

func _ready() -> void:
	_base_zoom = _camera.zoom  # capture whatever the .tscn sets (currently 0.58)
	_setup_art_layers()
	_setup_atmosphere()
	# Nuclear camera reset — connected once; any system can emit without needing
	# a direct SewerArena reference.
	Events.global_camera_reset.connect(force_camera_reset)

	# Pit Stop: if a shop is due, show it and hold — don't start the fight yet.
	if RunManager.pending_shop:
		_show_shop_screen()
		return

	_connect_player("Player_Red")
	_connect_player("Player_Blue")
	var abyss := get_node_or_null("Zones/Abyss")
	if abyss and abyss.has_signal("body_fallen"):
		abyss.body_fallen.connect(_on_player_ko)

	RunManager.run_started.connect(_apply_player_loadout)
	if RunManager.run_active:
		# Returning from a previous fight — no draft screen needed.
		_apply_player_loadout()
		_apply_enemy_loadout()
		_build_run_hud()
		Events.match_started.emit(_enemy_faction_id)
		_entry_drop_pending = true
	else:
		# Fresh run — pause physics and show the draft menu.
		# The fight starts only after the player confirms their loadout.
		RunManager.run_started.connect(_on_run_started_from_draft, CONNECT_ONE_SHOT)
		get_tree().paused = true
		_show_drafting_menu()


# ── Art layers ────────────────────────────────────────────────────────────────
## Loads all hand-drawn PNG layers from res://assets/arenas/default/ and adds
## them as Sprite2D nodes at the correct Z-depths. File names encode their
## layer order as a suffix number. Also loads the floor PNG as raw Image data
## so _check_floor_abyss() can do per-pixel transparency KO detection.
## Hides all procedural polygon visuals that the art now replaces.
func _setup_art_layers() -> void:
	# Bottom → top order; each entry = [path, z_index, blend_mode, opacity].
	# blend_mode: "" = normal, "add" = additive, "mul" = multiply.
	# opacity: 1.0 = fully opaque (matches Paint.NET layer opacity).
	var layers: Array = [
		["res://assets/arenas/default/table1.png",              -100, "",    1.0],
		["res://assets/arenas/default/arena_shadow2.png",        -90, "",    0.35],
		["res://assets/arenas/default/arena_floor3.png",         -80, "",    1.0],
		["res://assets/arenas/default/arena_floor_shadow4.png",  -70, "",    0.4],
		["res://assets/arenas/default/sludge_geyser5.png",       -65, "",    1.0],
		["res://assets/arenas/default/sludge_geyser6.png",       -63, "",    1.0],
		["res://assets/arenas/default/sludge_geyser7.png",       -61, "",    1.0],
		["res://assets/arenas/default/pipe8.png",                -58, "",    1.0],
		["res://assets/arenas/default/sludge_geyser9.png",       -55, "",    1.0],
		["res://assets/arenas/default/walls_shadow10.png",       -40, "",    0.5],
		["res://assets/arenas/default/corner_zones11.png",       -35, "",    1.0],
		["res://assets/arenas/default/corners12.png",            -25, "",    1.0],
	]
	var vp_size: Vector2 = get_viewport_rect().size
	for entry in layers:
		var tex := load(entry[0]) as Texture2D
		if not tex:
			push_warning("SewerArena: could not load art layer: " + entry[0])
			continue
		var sprite            := Sprite2D.new()
		sprite.texture         = tex
		sprite.centered        = true
		sprite.global_position = vp_size / 2.0
		sprite.z_index         = entry[1]
		sprite.z_as_relative   = false
		sprite.modulate        = Color(1.0, 1.0, 1.0, entry[3])
		var tex_size: Vector2  = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			# Divide by camera zoom: Sprite2D is in world space, so a zoom of 0.5
			# shows 2x the world — the sprite must be 2x larger to fill the screen.
			sprite.scale = (vp_size / tex_size) / _base_zoom
		match entry[2]:
			"add":
				var mat       := CanvasItemMaterial.new()
				mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				sprite.material = mat
			"mul":
				var mat       := CanvasItemMaterial.new()
				mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
				sprite.material = mat
		add_child(sprite)

	# Wall health sprites — one per breakable wall, swapped on each splat hit.
	# Node name "WallRight" → folder "wall_right/" → files "wall_right_full_health.png" etc.
	for wall_node_name: String in ["WallRight", "WallBottom", "WallLeft", "WallTop"]:
		var wall := get_node_or_null(wall_node_name)
		if not wall or not wall.has_method("setup_wall_art"):
			continue
		var snake: String = wall_node_name.to_snake_case()
		var art_base: String = "res://assets/arenas/default/" + snake + "/" + snake
		var tex := load(art_base + "_full_health.png") as Texture2D
		if not tex:
			push_warning("SewerArena: missing wall art: " + art_base + "_full_health.png")
			continue
		var spr        := Sprite2D.new()
		spr.texture     = tex
		spr.centered    = true
		spr.global_position = vp_size / 2.0
		spr.z_index     = -30
		spr.z_as_relative = false
		var w_tex_size  := tex.get_size()
		if w_tex_size.x > 0.0 and w_tex_size.y > 0.0:
			spr.scale = (vp_size / w_tex_size) / _base_zoom
		add_child(spr)
		wall.setup_wall_art(spr, art_base)

	# Load floor image for pixel-based abyss detection (bypasses import system).
	# Also compute the world-space transform so _check_floor_abyss() maps correctly
	# even with the camera-zoom-corrected sprite scale.
	var floor_img := Image.new()
	if floor_img.load("res://assets/arenas/default/arena_floor3.png") == OK:
		_floor_image = floor_img
		var f_tex_size := Vector2(floor_img.get_width(), floor_img.get_height())
		_floor_world_scale  = (vp_size / f_tex_size) / _base_zoom   # world units per pixel
		_floor_world_origin = vp_size / 2.0 - f_tex_size * _floor_world_scale / 2.0
	else:
		push_warning("SewerArena: floor image pixel detection unavailable.")

	# ── Film grain overlay (CanvasLayer 128, above all world content) ───────
	var grain_layer           := CanvasLayer.new()
	grain_layer.layer          = 128
	add_child(grain_layer)
	var grain_rect             := ColorRect.new()
	grain_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain_rect.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	var grain_mat              := ShaderMaterial.new()
	grain_mat.shader            = load("res://assets/shaders/film_grain.gdshader")
	grain_rect.material         = grain_mat
	grain_layer.add_child(grain_rect)

	# Spawn drop shadows beneath each bey (fixed-offset, non-rotating ovals).
	const _DROP_SHADOW = preload("res://scenes/effects/BeyDropShadow.tscn")
	for bey_name in ["Player_Red", "Player_Blue"]:
		var bey := get_node_or_null(bey_name)
		if bey:
			bey.add_child(_DROP_SHADOW.instantiate())

	# Hide all procedural polygon visuals — the art layers replace them.
	var procedural_visuals: Array[String] = [
		"WallRight/WallVisual",        "WallBottom/WallVisual",
		"WallLeft/WallVisual",         "WallTop/WallVisual",
		"CornerAtMutation/WallVisual", "CornerAtGunk/WallVisual",
		"CornerAtBounce/WallVisual",   "CornerAtAbyss/WallVisual",
		"Zones/BouncePad/Visual",      "Zones/Abyss/Visual",
		"Zones/GunkDrain/Visual",      "Zones/MutationStation/Visual",
	]
	for node_path in procedural_visuals:
		var vis := get_node_or_null(node_path)
		if vis:
			vis.visible = false


## Spawns the weather system and rat crowd managers.
func _setup_atmosphere() -> void:
	var weather := Node2D.new()
	weather.set_script(preload("res://scripts/arena/SewerWeather.gd"))
	add_child(weather)

	var crowd := Node2D.new()
	crowd.set_script(preload("res://scripts/arena/CrowdManager.gd"))
	add_child(crowd)


## Checks each bey's center pixel in the floor image.
## Transparent pixel = the bey has fallen into an abyss hole → force KO.
func _check_floor_abyss() -> void:
	if _match_over or not _floor_image:
		return
	var w: int = _floor_image.get_width()
	var h: int = _floor_image.get_height()
	for bey_name in ["Player_Red", "Player_Blue"]:
		var bey := get_node_or_null(bey_name)
		if not bey or not bey.has_method("force_ko"):
			continue
		if bey.has_meta("entering"):
			continue
		# Convert world position → image pixel, accounting for the
		# camera-zoom-corrected sprite scale stored in _setup_art_layers().
		var px: int = int((bey.global_position.x - _floor_world_origin.x) / _floor_world_scale.x)
		var py: int = int((bey.global_position.y - _floor_world_origin.y) / _floor_world_scale.y)
		# Skip if outside image bounds — the dist > 536 outer check handles that.
		if px < 0 or py < 0 or px >= w or py >= h:
			continue
		if _floor_image.get_pixel(px, py).a < 0.1:
			bey.force_ko()


# ── Enemy faction loadout ─────────────────────────────────────────────────────
func _apply_enemy_loadout() -> void:
	var enemy_name: String = "Player_Blue" if RunManager.player_side == "red" else "Player_Red"
	var enemy := get_node_or_null(enemy_name) as RigidBody2D
	if not enemy:
		return
	_enemy_node        = enemy
	# Use the faction pre-selected by GambleScreen (shown on VersusScreen); fallback to random.
	if RunManager.vs_enemy_faction_id != "":
		_enemy_faction_id = RunManager.vs_enemy_faction_id
		for key in FACTION_IDS:
			if FACTION_IDS[key] == _enemy_faction_id:
				_enemy_faction = key
				break
	else:
		_enemy_faction    = randi() % 3
		_enemy_faction_id = FACTION_IDS.get(_enemy_faction, "fat_rats")
	RunManager.is_boss_fight = false

	var chassis := ChassisData.new()
	var limb_l  := LimbData.new()
	var limb_r  := LimbData.new()

	match _enemy_faction:
		Faction.FAT_RATS:
			# Heavy, slow-spinning bruiser. Wins by sheer mass.
			chassis.name = "Fat Rat Shell";  chassis.mass = 14.0
			chassis.base_torque = 8500.0;    chassis.base_friction = 0.80
			chassis.drag = 0.05;             chassis.color = Color(0.38, 0.28, 0.22, 1.0)
			limb_l.name = "Rat Haunch";      limb_l.mass = 5.2
			limb_l.length_multiplier = 1.4;  limb_l.wobble_intensity = 0.8
			limb_l.drag = 0.18;              limb_l.color = Color(0.42, 0.30, 0.22, 1.0)
			limb_r.name = "Rat Haunch";      limb_r.mass = 5.2
			limb_r.length_multiplier = 1.4;  limb_r.wobble_intensity = 0.8
			limb_r.drag = 0.18;              limb_r.color = Color(0.42, 0.30, 0.22, 1.0)

		Faction.WIGGLY_WORM:
			# Featherlight, spins extremely fast, chaotic wobble.
			chassis.name = "Worm Coil";      chassis.mass = 2.8
			chassis.base_torque = 19000.0;   chassis.base_friction = 0.12
			chassis.drag = 0.02;             chassis.color = Color(0.62, 0.88, 0.38, 1.0)
			limb_l.name = "Worm Tail";       limb_l.mass = 0.55
			limb_l.length_multiplier = 0.9;  limb_l.wobble_intensity = 6.5
			limb_l.drag = 0.55;              limb_l.color = Color(0.55, 0.88, 0.42, 1.0)
			limb_r.name = "Worm Tail";       limb_r.mass = 0.55
			limb_r.length_multiplier = 0.9;  limb_r.wobble_intensity = 6.5
			limb_r.drag = 0.55;              limb_r.color = Color(0.55, 0.88, 0.42, 1.0)

		Faction.CROCO_LOCO:
			# Medium mass, peak torque. BeyAI handles center charges + Death Lunge.
			chassis.name = "Croco Jaw";      chassis.mass = 9.0
			chassis.base_torque = 24000.0;   chassis.base_friction = 0.45
			chassis.drag = 0.03;             chassis.color = Color(0.18, 0.42, 0.14, 1.0)
			limb_l.name = "Croco Fang";      limb_l.mass = 3.2
			limb_l.length_multiplier = 1.1;  limb_l.wobble_intensity = 2.2
			limb_l.drag = 0.20;              limb_l.color = Color(0.22, 0.52, 0.18, 1.0)
			limb_r.name = "Croco Fang";      limb_r.mass = 3.2
			limb_r.length_multiplier = 1.1;  limb_r.wobble_intensity = 2.2
			limb_r.drag = 0.20;              limb_r.color = Color(0.22, 0.52, 0.18, 1.0)

	# 25% chance per limb slot to swap in a random rare ability limb.
	if randf() < RARE_LIMB_CHANCE:
		var rare: LimbData = load(RARE_LIMB_POOL[randi() % RARE_LIMB_POOL.size()])
		if rare:
			limb_l = rare
	if randf() < RARE_LIMB_CHANCE:
		var rare: LimbData = load(RARE_LIMB_POOL[randi() % RARE_LIMB_POOL.size()])
		if rare:
			limb_r = rare

	# Boss fight: final fight + sufficient faction rep → swap in the boss chassis.
	if RunManager.current_wins >= RunManager.WINS_TO_COMPLETE - 1:
		if FactionManager.is_boss_eligible(_enemy_faction_id):
			RunManager.is_boss_fight = true
			var faction_data: FactionData = FactionManager.get_faction(_enemy_faction_id)
			if faction_data and faction_data.boss_chassis:
				chassis = faction_data.boss_chassis as ChassisData

	var ghoul := enemy.get_node_or_null("Ghoul_Base")
	if ghoul and ghoul.has_method("apply_loadout"):
		ghoul.apply_loadout(chassis, limb_l, limb_r)

	# Attach faction AI to the enemy bey.
	var player_name: String    = "Player_Red" if RunManager.player_side == "red" else "Player_Blue"
	var player_body: RigidBody2D = get_node_or_null(player_name) as RigidBody2D
	var bey_ai := Node.new()
	bey_ai.set_script(_BEY_AI)
	enemy.add_child(bey_ai)
	bey_ai.call("initialize", _enemy_faction_id, player_body, self)


func _apply_player_loadout() -> void:
	if not RunManager.run_active:
		return
	# Player's bey node is determined by the side they chose during drafting.
	var node_name: String = "Player_Red" if RunManager.player_side == "red" else "Player_Blue"
	var player := get_node_or_null(node_name)
	if not player:
		return
	var ghoul := player.get_node_or_null("Ghoul_Base")
	if ghoul and ghoul.has_method("apply_loadout") \
			and RunManager.player_chassis \
			and RunManager.player_limbs.size() >= 2:
		ghoul.apply_loadout(
			RunManager.player_chassis,
			RunManager.player_limbs[0],
			RunManager.player_limbs[1]
		)


# ── Run HUD (wins / strikes) ──────────────────────────────────────────────────
func _build_run_hud() -> void:
	var hud := get_node_or_null("HUD")
	if not hud:
		return
	var jitter_mat := ShaderMaterial.new()
	var shader_path := "res://assets/shaders/label_jitter.gdshader"
	if ResourceLoader.exists(shader_path):
		jitter_mat.shader = load(shader_path)
		jitter_mat.set_shader_parameter("strength", 0.8)
		jitter_mat.set_shader_parameter("speed",    7.0)

	_wins_label           = Label.new()
	_wins_label.position  = Vector2(18, 16)
	_wins_label.add_theme_font_size_override("font_size", 28)
	_wins_label.add_theme_color_override("font_color", Color(0.059, 0.50, 0.12, 0.92))
	_wins_label.material  = jitter_mat
	hud.add_child(_wins_label)

	_strikes_label          = Label.new()
	_strikes_label.position = Vector2(18, 44)
	_strikes_label.add_theme_font_size_override("font_size", 28)
	_strikes_label.add_theme_color_override("font_color", Color(0.72, 0.10, 0.08, 0.92))
	_strikes_label.material = jitter_mat
	hud.add_child(_strikes_label)

	_faction_label          = Label.new()
	_faction_label.position = Vector2(18, 72)
	_faction_label.add_theme_font_size_override("font_size", 20)
	_faction_label.add_theme_color_override("font_color", Color(0.65, 0.58, 0.35, 0.80))
	_faction_label.material = jitter_mat
	hud.add_child(_faction_label)

	_update_run_hud()


func _update_run_hud() -> void:
	if _wins_label:
		_wins_label.text    = "WINS    %d / %d" % [RunManager.current_wins,   RunManager.WINS_TO_COMPLETE]
	if _strikes_label:
		_strikes_label.text = "STRIKES %d / %d" % [RunManager.current_losses, RunManager.LOSSES_TO_FAIL]
	if _faction_label:
		var fname: String = FACTION_NAMES.get(_enemy_faction, "???") as String
		_faction_label.text = ("BOSS:  " if RunManager.is_boss_fight else "VS  ") + fname

func _connect_player(player_name: String) -> void:
	var player := get_node_or_null(player_name)
	if player and player.has_signal("knocked_out"):
		player.knocked_out.connect(_on_player_ko)

func _on_player_ko(loser: RigidBody2D) -> void:
	# _match_over is the single gate. Abyss calls force_ko() then also emits body_fallen,
	# so this function may be invoked twice in one frame — only the first call does work.
	if _match_over:
		return
	_match_over = true
	_match_elapsed = -1.0
	if is_instance_valid(_countdown_canvas):
		_countdown_canvas.queue_free()
		_countdown_canvas = null
		_countdown_label  = null
	_ko_label.visible = true
	# Hard-reset camera immediately — match may have ended mid-special-effect
	# (Croco lunge shiver, Super Spark slow-mo, etc.). No condition — always runs.
	force_camera_reset()

	# Identify winner — it's whichever bey isn't the loser.
	var winner: RigidBody2D = null
	for bname in ["Player_Red", "Player_Blue"]:
		var b := get_node_or_null(bname) as RigidBody2D
		if is_instance_valid(b) and b != loser:
			winner = b
			break

	# Resolve winner to a side string so the Event Bus carries a clean value.
	var winner_side: String = "none"
	if is_instance_valid(winner):
		winner_side = "red" if winner.name.to_lower().contains("red") else "blue"

	# Single event emit. RunManager._on_match_ended handles durability deduction,
	# win/loss counting, and scrap reward — all synchronously before this returns.
	Events.match_ended.emit(winner_side)

	var player_won: bool = (winner_side == RunManager.player_side)
	# Always wipe the cached faction so every fight rolls a fresh random enemy.
	RunManager.vs_enemy_faction_id = ""
	_update_run_hud()

	if is_instance_valid(winner) and winner.has_method("start_victory_lap"):
		winner.start_victory_lap()

	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if player_won:
			_show_progress_screen()   # ProgressScreen routes to Shop or PostMatchLoot
		elif RunManager.current_losses >= RunManager.LOSSES_TO_FAIL:
			_show_bankrupt_screen()
		else:
			_start_next_fight()
	)


# ── Match time limit ──────────────────────────────────────────────────────────

func _create_countdown_label() -> void:
	# Own CanvasLayer so positioning is in pure screen-space, independent of HUD or camera.
	_countdown_canvas       = CanvasLayer.new()
	_countdown_canvas.layer = 60
	add_child(_countdown_canvas)

	_countdown_label = Label.new()
	# Fill the full viewport so alignment properties handle centering — no manual math.
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.offset_top           = 75.0   # push text away from the very top edge
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	_countdown_label.add_theme_font_size_override("font_size", 80)
	_countdown_label.add_theme_color_override("font_color",
		Color(1.0, 0.62, 0.20))
	_countdown_label.add_theme_color_override("font_outline_color",
		Color(1.0, 0.42, 0.04, 0.75))
	_countdown_label.add_theme_constant_override("outline_size", 16)
	_countdown_canvas.add_child(_countdown_label)

func _pulse_countdown() -> void:
	if not is_instance_valid(_countdown_label):
		return
	# Flash bright orange then settle — modulate only, no scale, avoids full-rect clipping.
	_countdown_label.modulate = Color(1.0, 0.85, 0.3, 1.0)
	var tw := _countdown_label.create_tween()
	tw.tween_property(_countdown_label, "modulate", Color.WHITE, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _trigger_wall_break() -> void:
	if is_instance_valid(_countdown_canvas):
		_countdown_canvas.queue_free()
		_countdown_canvas = null
		_countdown_label  = null
	for wall_name: String in ["WallRight", "WallBottom", "WallLeft", "WallTop"]:
		var wall := get_node_or_null(wall_name)
		if wall and wall.has_method("shatter"):
			wall.shatter()


# ── Post-match routing ────────────────────────────────────────────────────────
func _show_progress_screen() -> void:
	var screen := CanvasLayer.new()
	screen.set_script(_PROGRESS_SCREEN)
	add_child(screen)

func _show_post_match_loot() -> void:
	var screen := CanvasLayer.new()
	screen.set_script(_POST_MATCH_LOOT)
	add_child(screen)

func _show_bankrupt_screen() -> void:
	var screen := CanvasLayer.new()
	screen.set_script(_BANKRUPT_SCREEN)
	add_child(screen)

func _show_drafting_menu() -> void:
	var cl := CanvasLayer.new()
	cl.layer        = 20
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)   # add to SewerArena, not root — consistent with _show_shop_screen()
	print("[SewerArena] CanvasLayer in tree: ", cl.is_inside_tree())

	var node := preload("res://scenes/ui/DraftingMenu.tscn").instantiate()
	cl.add_child(node)
	print("[SewerArena] DraftingMenu in tree: ", node.is_inside_tree(), " | Class: ", node.get_class())


func _on_run_started_from_draft() -> void:
	# Called once (CONNECT_ONE_SHOT) when the player confirms on the draft screen.
	# Tree is still paused here; VersusScreen will unpause it on "BRAWL!".
	_apply_enemy_loadout()
	_build_run_hud()
	Events.match_started.emit(_enemy_faction_id)
	_entry_drop_pending = true


func _show_shop_screen() -> void:
	var screen := CanvasLayer.new()
	screen.set_script(_SHOP_SCREEN)
	add_child(screen)

func _start_next_fight() -> void:
	get_tree().reload_current_scene()

# ── Entry drops ───────────────────────────────────────────────────────────────

func _do_entry_drop() -> void:
	_match_elapsed  = 0.0
	_last_countdown = -1
	var player_name := "Player_Red" if RunManager.player_side == "red" else "Player_Blue"
	var enemy_name  := "Player_Blue" if RunManager.player_side == "red" else "Player_Red"
	var player := get_node_or_null(player_name) as RigidBody2D
	var enemy  := get_node_or_null(enemy_name)  as RigidBody2D

	# Player always drops straight from above — medium height, natural fall.
	_drop_bey(player, Vector2(0.0, -380.0), 0.50, false)

	# Enemy entry varies by faction personality.
	match _enemy_faction:
		Faction.FAT_RATS:
			# Slow, heavy plummet — drops from lower height but hits like a sack of garbage.
			_drop_bey(enemy, Vector2(0.0, -260.0), 0.72, true)
		Faction.WIGGLY_WORM:
			# Screams in from way up high, barely seems to notice gravity.
			_drop_bey(enemy, Vector2(0.0, -540.0), 0.33, false)
		Faction.CROCO_LOCO:
			# Charges in from the side like a lunge — low and fast.
			if is_instance_valid(enemy):
				var side := 1.0 if enemy.global_position.x >= ARENA_CENTER.x else -1.0
				_drop_bey(enemy, Vector2(side * 520.0, 40.0), 0.40, true, true)


func _drop_bey(bey: RigidBody2D, offset: Vector2, duration: float,
		heavy: bool, from_side: bool = false) -> void:
	if not is_instance_valid(bey):
		return
	var land_pos             := bey.global_position
	bey.set_meta("entering", true)
	bey.freeze                = true
	bey.freeze_mode           = RigidBody2D.FREEZE_MODE_KINEMATIC
	bey.global_position       = land_pos + offset
	bey.linear_velocity       = Vector2.ZERO

	var tw := create_tween()
	tw.tween_property(bey, "global_position", land_pos, duration) \
		.set_ease(Tween.EASE_OUT if from_side else Tween.EASE_IN) \
		.set_trans(Tween.TRANS_CUBIC if from_side else Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(bey):
			return
		bey.freeze           = false
		bey.linear_velocity  = Vector2.ZERO
		if bey.has_meta("entering"):
			bey.remove_meta("entering")
		_entry_land_fx(land_pos, heavy)
	)


func _entry_land_fx(pos: Vector2, heavy: bool) -> void:
	# SewerSplash burst at the landing point.
	var splash := _SEWER_SPLASH.instantiate()
	add_child(splash)
	splash.global_position = pos

	shake_screen(20.0 if heavy else 9.0, 0.22 if heavy else 0.14)

	# Heavy landings (Fat Rats, Croco) get an extra outward debris ring.
	if not heavy:
		return
	var p               := CPUParticles2D.new()
	p.z_index            = 100
	p.one_shot           = true
	p.lifetime           = 0.60
	p.amount             = 26
	p.explosiveness      = 1.0
	p.direction          = Vector2.ZERO
	p.spread             = 180.0
	p.gravity            = Vector2(0.0, 60.0)
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min   = 3.0
	p.scale_amount_max   = 9.0
	p.color              = Color(0.18, 0.28, 0.10, 0.88)
	add_child(p)
	p.global_position    = pos
	p.emitting           = true
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(p): p.queue_free()
	)


# Blue-grey upward splash to show the bey caught the sewer water in the center.
func _spawn_water_splash(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 100
	p.one_shot             = true
	p.lifetime             = 0.5
	p.amount               = 14
	p.explosiveness        = 0.9
	p.direction            = Vector2.UP
	p.spread               = 90.0
	p.gravity              = Vector2(0.0, 200.0)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 140.0
	p.color                = Color(0.45, 0.6, 0.75, 1.0)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(p): p.queue_free()
	)
