extends CanvasLayer

# ── Faction Pit Stop — Shop Screen ────────────────────────────────────────────
# Layout: left 63 % = 3 shop slots  |  right 37 % = Your Rig (repair/splice)
# Bone-dry: plain Labels + Buttons.  Rive styling handled separately.

const TIER_NAMES:  Array[String] = ["", "COMMON", "RARE", "LEGENDARY"]
const TIER_COLORS: Array[Color]  = [
	Color.WHITE,
	Color(0.65, 0.65, 0.65, 1.0),
	Color(0.30, 0.55, 1.00, 1.0),
	Color(1.00, 0.78, 0.08, 1.0),
]

const REPAIR_PRICE_MULTIPLIER: int = 15   # scrap per missing durability point
const SPLICE_DISCOUNT:       float = 0.50  # splice costs 50 % of normal price

const C_BG:     Color = Color(0.04,  0.08,  0.04,  0.97)
const C_PANEL:  Color = Color(0.07,  0.13,  0.07,  0.92)
const C_HEADER: Color = Color(0.06,  0.12,  0.06,  1.00)
const C_SEAM:   Color = Color(0.059, 0.30,  0.08,  0.70)
const C_TEXT:   Color = Color(0.88,  0.84,  0.72,  0.95)
const C_FAINT:  Color = Color(0.62,  0.60,  0.50,  0.80)
const C_GOLD:   Color = Color(0.95,  0.85,  0.20,  1.00)
const C_GREEN:  Color = Color(0.18,  0.82,  0.32,  1.00)
const C_RED:    Color = Color(0.85,  0.18,  0.18,  1.00)
const C_BLUE:   Color = Color(0.18,  0.48,  0.92,  1.00)

var _inventory:      Array  = []    # Array[LimbData|null], 3 entries
var _faction_id:     String = ""
var _scrap_lbl:      Label  = null
var _rig_root:       Control = null  # right panel — rebuilt on any purchase


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	get_tree().paused = true
	_faction_id = FactionManager.current_match_faction_id
	_inventory  = ShopManager.generate_inventory(_faction_id)
	# Pad to always have 3 entries.
	while _inventory.size() < 3:
		_inventory.append(null)
	_build_ui()


# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var vp: Vector2 = get_tree().root.get_visible_rect().size

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_header(root, vp)

	var HEADER_H: float = 64.0
	var FOOTER_H: float = 48.0
	var content_y: float = HEADER_H + 4.0
	var content_h: float = vp.y - HEADER_H - FOOTER_H - 8.0
	var split_x:   float = vp.x * 0.63

	_build_shop_section(root, Vector2(8.0, content_y), Vector2(split_x - 12.0, content_h))
	_rig_root = _build_rig_panel(root, Vector2(split_x + 4.0, content_y),
		Vector2(vp.x - split_x - 12.0, content_h))

	_build_footer(root, vp, FOOTER_H)


func _build_header(root: Control, vp: Vector2) -> void:
	var hdr := ColorRect.new()
	hdr.color = C_HEADER
	hdr.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hdr.offset_bottom = 64.0
	hdr.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(hdr)

	var seam := ColorRect.new()
	seam.color = C_SEAM
	seam.set_anchors_preset(Control.PRESET_TOP_WIDE)
	seam.offset_top    = 62.0
	seam.offset_bottom = 65.0
	seam.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(seam)

	var title := Label.new()
	title.text     = "FACTION PIT STOP"
	title.position = Vector2(18.0, 8.0)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", C_GREEN)
	root.add_child(title)

	var sub := Label.new()
	sub.text     = "wins %d / %d  ·  %s" % [
		RunManager.current_wins, RunManager.WINS_TO_COMPLETE,
		_faction_id.replace("_", " ").to_upper(),
	]
	sub.position = Vector2(20.0, 42.0)
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", C_FAINT)
	root.add_child(sub)

	_scrap_lbl = Label.new()
	_scrap_lbl.name = "Scrap_Total"
	_scrap_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_scrap_lbl.offset_left   = -210.0
	_scrap_lbl.offset_bottom =  64.0
	_scrap_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scrap_lbl.add_theme_font_size_override("font_size", 31)
	_scrap_lbl.add_theme_color_override("font_color", C_GOLD)
	_refresh_scrap_label()
	root.add_child(_scrap_lbl)


# ── Shop inventory (left section) ────────────────────────────────────────────
func _build_shop_section(root: Control, pos: Vector2, size: Vector2) -> void:
	var slot_w: float = (size.x - 8.0) / 3.0
	for i in 3:
		_build_shop_slot(root, i,
			Vector2(pos.x + i * (slot_w + 4.0), pos.y),
			Vector2(slot_w, size.y))


func _build_shop_slot(root: Control, idx: int, pos: Vector2, size: Vector2) -> void:
	var limb: LimbData = _inventory[idx] as LimbData if _inventory[idx] != null else null

	var panel := ColorRect.new()
	panel.name         = "ShopSlot_%d" % idx
	panel.position     = pos
	panel.size         = size
	panel.color        = C_PANEL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	if not limb:
		var el := Label.new()
		el.text     = "— SOLD OUT —"
		el.position = pos + Vector2(10.0, 18.0)
		el.add_theme_font_size_override("font_size", 20)
		el.add_theme_color_override("font_color", C_FAINT)
		root.add_child(el)
		return

	var y: float = pos.y + 10.0

	# Tier.
	var t: int = clampi(limb.tier if limb.tier > 0 else 1, 1, 3)
	var tier_lbl := Label.new()
	tier_lbl.text     = TIER_NAMES[t]
	tier_lbl.position = Vector2(pos.x + 10.0, y)
	tier_lbl.add_theme_font_size_override("font_size", 15)
	tier_lbl.add_theme_color_override("font_color", TIER_COLORS[t])
	root.add_child(tier_lbl)
	y += 16.0

	# Name.
	var name_lbl := Label.new()
	name_lbl.text          = limb.name.to_upper()
	name_lbl.position      = Vector2(pos.x + 10.0, y)
	name_lbl.size          = Vector2(size.x - 20.0, 32.0)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.add_theme_font_size_override("font_size", 25)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	root.add_child(name_lbl)
	y += 36.0

	# Colour swatch.
	var swatch := ColorRect.new()
	swatch.position    = Vector2(pos.x + 10.0, y)
	swatch.size        = Vector2(size.x - 20.0, 8.0)
	swatch.color       = limb.color
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(swatch)
	y += 14.0

	# Stats (single compact line).
	var stats_lbl := Label.new()
	stats_lbl.text     = "%.1fkg  ·  %.1fx reach  ·  w%.1f" % [
		limb.mass, limb.length_multiplier, limb.wobble_intensity
	]
	stats_lbl.position = Vector2(pos.x + 10.0, y)
	stats_lbl.add_theme_font_size_override("font_size", 17)
	stats_lbl.add_theme_color_override("font_color", C_FAINT)
	root.add_child(stats_lbl)
	y += 20.0

	# Price.
	var price_lbl := Label.new()
	price_lbl.text     = "%d  SCRAP" % limb.scrap_price
	price_lbl.position = Vector2(pos.x + 10.0, y)
	price_lbl.add_theme_font_size_override("font_size", 24)
	price_lbl.add_theme_color_override("font_color", C_GOLD)
	root.add_child(price_lbl)
	y += 26.0

	# Seam.
	var seam := ColorRect.new()
	seam.position    = Vector2(pos.x + 6.0, y)
	seam.size        = Vector2(size.x - 12.0, 1.0)
	seam.color       = C_SEAM
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(seam)
	y += 8.0

	# Buy buttons.
	var can_afford: bool = Global.total_scrap >= limb.scrap_price
	for arm_slot in [0, 1]:
		var label: String = ("→ LEFT ARM" if arm_slot == 0 else "→ RIGHT ARM")
		var col:   Color  = (C_RED      if arm_slot == 0 else C_BLUE)
		var btn := _make_btn(label, Vector2(pos.x + 6.0, y), Vector2(size.x - 12.0, 30.0),
			col, can_afford)
		btn.pressed.connect(_on_buy.bind(limb, arm_slot, idx))
		root.add_child(btn)
		y += 34.0

	# Splice buttons — only enabled if the corresponding arm is a Broken Nub.
	var splice_price: int = int(limb.scrap_price * SPLICE_DISCOUNT)
	var splice_header_added := false
	for arm_slot in [0, 1]:
		var cur_limb: LimbData = RunManager.player_limbs[arm_slot] \
			if arm_slot < RunManager.player_limbs.size() else null
		if not cur_limb or cur_limb.name != "Broken Nub":
			continue
		if not splice_header_added:
			var sh := Label.new()
			sh.text     = "⚡ SPLICE  (%d scrap)" % splice_price
			sh.position = Vector2(pos.x + 10.0, y)
			sh.add_theme_font_size_override("font_size", 15)
			sh.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0, 0.90))
			root.add_child(sh)
			y += 16.0
			splice_header_added = true

		var slabel: String = ("↯ LEFT NUB"  if arm_slot == 0 else "↯ RIGHT NUB")
		var scol:   Color  = Color(0.72, 0.35, 1.0, 1.0)
		var can_splice: bool = Global.total_scrap >= splice_price
		var sbtn := _make_btn(slabel, Vector2(pos.x + 6.0, y), Vector2(size.x - 12.0, 28.0),
			scol, can_splice)
		sbtn.pressed.connect(_on_splice.bind(limb, arm_slot, idx))
		root.add_child(sbtn)
		y += 32.0


# ── Your Rig panel (right section) ───────────────────────────────────────────
func _build_rig_panel(root: Control, pos: Vector2, size: Vector2) -> Control:
	var panel := ColorRect.new()
	panel.position     = pos
	panel.size         = size
	panel.color        = C_PANEL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var y: float = pos.y + 10.0

	var hdr := Label.new()
	hdr.text     = "YOUR RIG"
	hdr.position = Vector2(pos.x + 12.0, y)
	hdr.add_theme_font_size_override("font_size", 22)
	hdr.add_theme_color_override("font_color", C_GREEN)
	root.add_child(hdr)
	y += 24.0

	var seam0 := ColorRect.new()
	seam0.position    = Vector2(pos.x + 6.0, y)
	seam0.size        = Vector2(size.x - 12.0, 1.0)
	seam0.color       = C_SEAM
	seam0.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(seam0)
	y += 8.0

	for arm_slot in [0, 1]:
		y = _build_arm_row(root, arm_slot, pos, size, y)
		if arm_slot == 0:
			var seam1 := ColorRect.new()
			seam1.position    = Vector2(pos.x + 6.0, y + 4.0)
			seam1.size        = Vector2(size.x - 12.0, 1.0)
			seam1.color       = C_SEAM
			seam1.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(seam1)
			y += 14.0

	return panel


func _build_arm_row(root: Control, arm_slot: int, panel_pos: Vector2,
		panel_size: Vector2, y: float) -> float:
	var limb: LimbData = RunManager.player_limbs[arm_slot] \
		if arm_slot < RunManager.player_limbs.size() else null
	var dur: int = RunManager.player_limb_durabilities[arm_slot] \
		if arm_slot < RunManager.player_limb_durabilities.size() else RunManager.LIMB_MAX_DURABILITY
	var x: float = panel_pos.x + 12.0
	var w: float = panel_size.x - 24.0

	# Arm label.
	var arm_lbl := Label.new()
	arm_lbl.text     = ("LEFT ARM" if arm_slot == 0 else "RIGHT ARM")
	arm_lbl.position = Vector2(x, y)
	arm_lbl.add_theme_font_size_override("font_size", 15)
	arm_lbl.add_theme_color_override("font_color", C_RED if arm_slot == 0 else C_BLUE)
	root.add_child(arm_lbl)
	y += 15.0

	# Limb name.
	var limb_name: String = limb.name.to_upper() if limb else "EMPTY"
	var is_nub: bool      = (limb and limb.name == "Broken Nub")
	var name_lbl := Label.new()
	name_lbl.text     = limb_name
	name_lbl.position = Vector2(x, y)
	name_lbl.size     = Vector2(w, 24.0)
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.30, 0.18, 1.0) if is_nub else C_TEXT)
	root.add_child(name_lbl)
	y += 26.0

	# Durability pips.
	var pip_row := Label.new()
	var pip_str: String = ""
	for i in RunManager.LIMB_MAX_DURABILITY:
		pip_str += ("▓" if i < dur else "░")
	var frs_col: Color = RunManager.get_freshness_color(arm_slot)
	pip_row.text     = pip_str + "  " + RunManager.get_limb_freshness(arm_slot)
	pip_row.position = Vector2(x, y)
	pip_row.add_theme_font_size_override("font_size", 18)
	pip_row.add_theme_color_override("font_color", frs_col)
	root.add_child(pip_row)
	y += 20.0

	if not is_nub:
		# Repair cost + button.
		var missing: int  = RunManager.LIMB_MAX_DURABILITY - dur
		var cost:    int  = missing * REPAIR_PRICE_MULTIPLIER
		var can_repair: bool = cost > 0 and Global.total_scrap >= cost

		var cost_lbl := Label.new()
		cost_lbl.text     = ("FULLY REPAIRED" if cost == 0 else "repair cost:  %d scrap" % cost)
		cost_lbl.position = Vector2(x, y)
		cost_lbl.add_theme_font_size_override("font_size", 17)
		cost_lbl.add_theme_color_override("font_color",
			C_GREEN if cost == 0 else (C_GOLD if can_repair else C_FAINT))
		root.add_child(cost_lbl)
		y += 18.0

		if cost > 0:
			var rbtn := _make_btn("⚙ REPAIR  %d SCRAP" % cost,
				Vector2(x, y), Vector2(w, 30.0), C_GOLD, can_repair)
			rbtn.pressed.connect(_on_repair.bind(arm_slot))
			root.add_child(rbtn)
			y += 34.0
	else:
		# Nub notice — splice options are shown inside each shop slot.
		var nub_lbl := Label.new()
		nub_lbl.text     = "SPLICE AVAILABLE IN SHOP"
		nub_lbl.position = Vector2(x, y)
		nub_lbl.add_theme_font_size_override("font_size", 15)
		nub_lbl.add_theme_color_override("font_color", Color(0.72, 0.40, 1.0, 0.88))
		root.add_child(nub_lbl)
		y += 18.0

	return y


func _build_footer(root: Control, vp: Vector2, footer_h: float) -> void:
	var close_btn := Button.new()
	close_btn.text = "CLOSE SHOP  →  NEXT FIGHT"
	close_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	close_btn.offset_left   = -310.0
	close_btn.offset_right  =  -12.0
	close_btn.offset_top    = -float(footer_h) + 8.0
	close_btn.offset_bottom =  -8.0
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.add_theme_color_override("font_color", C_GREEN)
	close_btn.pressed.connect(_on_close)
	root.add_child(close_btn)


# ── Button factory ────────────────────────────────────────────────────────────
func _make_btn(label: String, pos: Vector2, sz: Vector2,
		col: Color, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text     = label
	btn.position = pos
	btn.size     = sz
	btn.disabled = not enabled
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", col if enabled else C_FAINT)
	return btn


# ── Transactions ──────────────────────────────────────────────────────────────
func _on_buy(limb: LimbData, arm_slot: int, slot_idx: int) -> void:
	if Global.total_scrap < limb.scrap_price:
		return
	Global.total_scrap -= limb.scrap_price
	Events.scrap_changed.emit(Global.total_scrap)
	RunManager.player_limbs[arm_slot]             = limb
	RunManager.player_limb_durabilities[arm_slot] = RunManager.LIMB_MAX_DURABILITY
	_inventory[slot_idx] = null
	SaveManager.save_game()
	_rebuild()


func _on_splice(shop_limb: LimbData, arm_slot: int, slot_idx: int) -> void:
	var cost: int = int(shop_limb.scrap_price * SPLICE_DISCOUNT)
	if Global.total_scrap < cost:
		return
	var nub: LimbData = RunManager.player_limbs[arm_slot] as LimbData
	if not nub or nub.name != "Broken Nub":
		return

	# Build franken-limb: shop stats + nub's chaotic wobble.
	var franken := LimbData.new()
	franken.name               = "Spliced " + shop_limb.name
	franken.mass               = shop_limb.mass
	franken.drag               = shop_limb.drag
	franken.color              = shop_limb.color.lerp(Color(0.35, 0.90, 0.25, 1.0), 0.28)
	franken.length_multiplier  = shop_limb.length_multiplier
	franken.wobble_intensity   = maxf(nub.wobble_intensity, shop_limb.wobble_intensity * 1.6)
	franken.slow_on_hit        = shop_limb.slow_on_hit
	franken.wall_recoil_penalty = shop_limb.wall_recoil_penalty
	franken.tier               = shop_limb.tier
	franken.scrap_price        = shop_limb.scrap_price

	Global.total_scrap -= cost
	Events.scrap_changed.emit(Global.total_scrap)
	RunManager.player_limbs[arm_slot]             = franken
	RunManager.player_limb_durabilities[arm_slot] = RunManager.LIMB_MAX_DURABILITY
	_inventory[slot_idx] = null
	Events.part_spliced.emit(arm_slot)
	SaveManager.save_game()
	_rebuild()


func _on_repair(arm_slot: int) -> void:
	var dur: int     = RunManager.player_limb_durabilities[arm_slot]
	var missing: int = RunManager.LIMB_MAX_DURABILITY - dur
	var cost: int    = missing * REPAIR_PRICE_MULTIPLIER
	if cost <= 0 or Global.total_scrap < cost:
		return
	Global.total_scrap -= cost
	Events.scrap_changed.emit(Global.total_scrap)
	RunManager.player_limb_durabilities[arm_slot] = RunManager.LIMB_MAX_DURABILITY
	Events.part_repaired.emit(arm_slot)
	SaveManager.save_game()
	_rebuild()


# Rebuild the entire UI in-place after any transaction so all buttons
# and costs reflect the new state without partial-invalidation complexity.
func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build_ui()


func _refresh_scrap_label() -> void:
	if is_instance_valid(_scrap_lbl):
		_scrap_lbl.text = "SCRAP  %d" % Global.total_scrap


func _on_close() -> void:
	RunManager.pending_shop = false
	get_tree().paused = false
	get_tree().reload_current_scene()
