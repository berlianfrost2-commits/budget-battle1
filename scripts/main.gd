extends Control
## BUDGET BATTLE — semua layar game. Layar dibuat lewat kode agar mudah dikembangkan.

const BuildCanvas := preload("res://scripts/build_canvas.gd")

const BG := Color("#0b1020")
const CARD := Color("#16203a")
const CARD2 := Color("#1e2b4d")
const GOLD := Color("#f5b301")
const BLUE := Color("#2563eb")
const GREEN := Color("#16a34a")
const RED := Color("#dc2626")
const MUTED := Color("#94a3b8")
const AVATAR_COLORS := ["#ef4444", "#f97316", "#f59e0b", "#84cc16", "#22c55e", "#14b8a6",
	"#06b6d4", "#3b82f6", "#6366f1", "#a855f7", "#ec4899", "#64748b"]
const BUDGETS := [500000, 1000000, 10000000, 100000000]
const BUDGET_DESC := ["Hemat: perbaikan kecil & dekor murah", "Standar: perabot dasar & renovasi ringan",
	"Modern: material berkualitas & desain lengkap", "Mewah: material premium & desain eksklusif"]
const PALETTE := ["#F43F5E", "#F97316", "#FACC15", "#22C55E", "#14B8A6", "#3B82F6", "#6366F1",
	"#A855F7", "#EC4899", "#FFFFFF", "#9CA3AF", "#111827", "#92400E"]
const BOT_LEVELS := [["easy", "EASY", "Desain sederhana, strategi dasar", "#22c55e"],
	["normal", "NORMAL", "Desain cukup baik, budget teratur", "#3b82f6"],
	["hard", "HARD", "Strategi kompleks, pilihan tepat", "#f97316"],
	["expert", "EXPERT", "Strategi paling optimal", "#dc2626"]]

var screen: Control
var screen_id := 0
var sel := {}            # pilihan pertandingan
var toast_label: Label

# state pertandingan
var match_id := ""
var mdata: Dictionary = {}
var items: Array = []
var items_by_id: Dictionary = {}
var canvas  # BuildCanvas
var pending_item := ""
var undo_stack: Array = []
var dirty := false
var time_offset := 0.0
var finishing := false
var ui := {}

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG)
	theme = _make_theme()
	_go(_splash)

# ================= UTIL UI =================
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_color("font_color", "Label", Color.WHITE)
	var le := _box(CARD2, 16)
	le.content_margin_left = 20
	le.content_margin_right = 20
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _box(CARD2.lightened(0.1), 16))
	t.set_font_size("font_size", "LineEdit", 28)
	return t

func _box(c: Color, r: int = 22, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if border.a > 0:
		s.set_border_width_all(3)
		s.border_color = border
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 4
	return s

func _go(builder: Callable) -> void:
	screen_id += 1
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.modulate.a = 0.0
	add_child(screen)
	if is_instance_valid(toast_label) and toast_label.get_parent() == self:
		move_child(toast_label, -1)
	builder.call()
	create_tween().tween_property(screen, "modulate:a", 1.0, 0.25)

func _alive(id: int) -> bool:
	return id == screen_id and is_inside_tree()

func _label(text: String, size: int = 26, col: Color = Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _btn(text: String, cb: Callable, col: Color = BLUE, h: int = 92, fs: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_stylebox_override("normal", _box(col))
	b.add_theme_stylebox_override("hover", _box(col.lightened(0.1)))
	b.add_theme_stylebox_override("pressed", _box(col.darkened(0.25)))
	b.add_theme_stylebox_override("disabled", _box(col.darkened(0.55)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := Color("#0b1020") if col.get_luminance() > 0.6 else Color.WHITE
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	b.pressed.connect(func():
		b.pivot_offset = b.size / 2
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.95, 0.95), 0.06)
		tw.tween_property(b, "scale", Vector2.ONE, 0.08)
		cb.call())
	return b

func _card(col: Color = CARD) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(col, 24))
	return p

func _avatar(idx: int, name_text: String, sz: int = 84) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var c := Color("#0f172a") if idx == 99 else Color(AVATAR_COLORS[clampi(idx, 0, 11)])
	p.add_theme_stylebox_override("panel", _box(c, sz / 2, Color.WHITE))
	var l := _label("AI" if idx == 99 else name_text.substr(0, 1).to_upper(), int(sz * 0.42), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

func _page(title: String, back: Callable = Callable(), scroll := true) -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 28)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 28)
	screen.add_child(m)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	m.add_child(outer)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	outer.add_child(head)
	if back.is_valid():
		var b := _btn("<", back, CARD2, 72, 32)
		b.custom_minimum_size = Vector2(72, 72)
		head.add_child(b)
	var t := _label(title, 36, GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if scroll:
		var s := ScrollContainer.new()
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		outer.add_child(s)
		s.add_child(v)
	else:
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(v)
	return v

func toast(msg: String, col: Color = RED) -> void:
	if is_instance_valid(toast_label):
		toast_label.queue_free()
	toast_label = _label(msg, 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.add_theme_stylebox_override("normal", _box(col, 18))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position = Vector2(size.x * 0.08, size.y - 220)
	toast_label.size = Vector2(size.x * 0.84, 0)
	add_child(toast_label)
	var tw := toast_label.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(toast_label.queue_free)

func _loading(v: Control, text := "Memuat...") -> Label:
	var l := _label(text, 26, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(l)
	return l

func _now() -> float:
	return Time.get_unix_time_from_system() + time_offset

# ================= 1. SPLASH =================
func _splash() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 20)
	screen.add_child(v)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.png")
	logo.custom_minimum_size = Vector2(240, 240)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(logo)
	v.add_child(_label("BUDGET BATTLE", 56, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label("YOUR BUDGET, YOUR CREATIVITY,\nYOUR VICTORY.", 24, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var id := screen_id
	await get_tree().create_timer(1.4).timeout
	if not _alive(id): return
	if not Api.is_configured():
		_go(_not_configured)
		return
	if Api.is_logged_in():
		var r := await Api.load_profile()
		if r.ok and not Api.profile.is_empty():
			_go(_menu)
			return
	_go(_login)

func _not_configured() -> void:
	var v := _page("Server belum diatur")
	v.add_child(_label("Aplikasi ini belum terhubung ke server Supabase.\n\nIsi Secrets SUPABASE_URL dan SUPABASE_ANON_KEY di GitHub (Settings > Secrets and variables > Actions), lalu jalankan ulang build.", 26))

# ================= 2-3. LOGIN / REGISTER =================
func _login(register := false) -> void:
	var v := _page("Daftar Akun" if register else "Masuk")
	v.add_child(_label("BUDGET BATTLE", 44, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var user := LineEdit.new()
	user.placeholder_text = "Username (3-20 huruf)"
	user.custom_minimum_size.y = 84
	if register:
		v.add_child(user)
	var email := LineEdit.new()
	email.placeholder_text = "Email"
	email.custom_minimum_size.y = 84
	email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	v.add_child(email)
	var pw := LineEdit.new()
	pw.placeholder_text = "Kata sandi (min. 6)"
	pw.secret = true
	pw.custom_minimum_size.y = 84
	v.add_child(pw)
	var go := _btn("DAFTAR" if register else "MASUK", func(): pass, GOLD)
	v.add_child(go)
	go.pressed.connect(func():
		go.disabled = true
		var r: Dictionary
		if register:
			if user.text.strip_edges().length() < 3:
				toast("Username minimal 3 huruf")
				go.disabled = false
				return
			r = await Api.sign_up(email.text.strip_edges(), pw.text, user.text.strip_edges())
			if r.ok and not Api.is_logged_in():
				toast("Akun dibuat. Cek email untuk konfirmasi, lalu masuk.", GREEN)
				go.disabled = false
				_go(_login.bind(false))
				return
		else:
			r = await Api.sign_in(email.text.strip_edges(), pw.text)
		if not r.ok:
			toast(str(r.error))
			go.disabled = false
			return
		await Api.load_profile()
		_go(_menu))
	v.add_child(_btn("Sudah punya akun? Masuk" if register else "Belum punya akun? Daftar",
		func(): _go(_login.bind(not register)), CARD2, 80, 24))

# ================= 4. MENU UTAMA =================
func _menu() -> void:
	var v := _page("BUDGET BATTLE")
	var p: Dictionary = Api.profile
	var card := _card(CARD2)
	v.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	card.add_child(h)
	h.add_child(_avatar(int(p.get("avatar", 0)), str(p.get("username", "?")), 100))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	info.add_child(_label(str(p.get("username", "")), 32))
	var lvl := int(p.get("level", 1))
	var xp := int(p.get("xp", 0))
	info.add_child(_label("Level %d  |  %s  |  %d koin" % [lvl, Api.rank_name(int(p.get("rank_points", 1000))), int(p.get("coins", 0))], 22, MUTED))
	var bar := ProgressBar.new()
	bar.max_value = 200
	bar.value = xp % 200
	bar.show_percentage = false
	bar.custom_minimum_size.y = 14
	bar.add_theme_stylebox_override("background", _box(BG, 7))
	bar.add_theme_stylebox_override("fill", _box(GOLD, 7))
	info.add_child(bar)

	var id := screen_id
	var resume_slot := VBoxContainer.new()
	v.add_child(resume_slot)
	v.add_child(_btn("PLAYER VS PLAYER", func():
		sel = {"mode": "pvp"}
		_go(_categories), BLUE, 120, 34))
	v.add_child(_btn("PLAYER VS BOT", func():
		sel = {"mode": "bot"}
		_go(_bot_levels), Color("#7c3aed"), 120, 34))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	for e in [["Leaderboard", _leaderboard], ["Riwayat", _history], ["Profil", _profile],
			["Reward", _rewards], ["Pengaturan", _settings]]:
		var b := _btn(e[0], (func(f): _go(f)).bind(e[1]), CARD2, 90)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	if p.get("is_admin", false):
		var b := _btn("Admin", func(): _go(_admin), RED, 90)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	# reconnect: kalau masih ada pertandingan berjalan
	var r := await Api.rpc_call("my_active_match")
	if _alive(id) and r.ok and r.data != null and str(r.data) != "":
		resume_slot.add_child(_btn("LANJUTKAN PERTANDINGAN", func():
			match_id = str(r.data)
			_go(_waiting), GREEN, 100))
	Api.load_profile()

# ================= 9. LEVEL BOT =================
func _bot_levels() -> void:
	var v := _page("Tingkat Kesulitan Bot", func(): _go(_menu))
	v.add_child(_label("Bot dijalankan server, memakai budget & objek yang sama, tanpa info rahasia.", 22, MUTED))
	for b in BOT_LEVELS:
		var bt := _btn("%s\n%s" % [b[1], b[2]], (func(lv):
			sel["bot_level"] = lv
			_go(_categories)).bind(b[0]), Color(b[3]), 130, 26)
		v.add_child(bt)

# ================= 10. KATEGORI =================
func _categories() -> void:
	var back := func(): _go(_bot_levels if sel.get("mode") == "bot" else _menu)
	var v := _page("Pilih Kategori", back)
	var l := _loading(v)
	var id := screen_id
	var r := await Api.select("categories?active=eq.true&order=sort")
	if not _alive(id): return
	l.queue_free()
	if not r.ok:
		v.add_child(_label(str(r.error), 24, RED))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	for c in r.data:
		var b := _btn(str(c.name), (func(cc):
			sel["category"] = str(cc.id)
			sel["category_name"] = str(cc.name)
			_go(_budgets)).bind(c), Color(str(c.color)).darkened(0.15), 120, 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(b)

# ================= 11. BUDGET =================
func _budgets() -> void:
	var v := _page("Pilih Budget", func(): _go(_categories))
	v.add_child(_label("Kategori: " + str(sel.get("category_name", "")), 24, MUTED))
	var cols := [GREEN, BLUE, Color("#7c3aed"), GOLD]
	for i in 4:
		v.add_child(_btn("%s\n%s" % [Api.rupiah(BUDGETS[i]), BUDGET_DESC[i]], (func(bud):
			sel["budget"] = bud
			_go(_durations)).bind(BUDGETS[i]), cols[i], 130, 26))
	v.add_child(_label("Budget adalah uang virtual untuk permainan, bukan uang sungguhan.", 20, MUTED))

# ================= DURASI =================
func _durations() -> void:
	var v := _page("Durasi Pertandingan", func(): _go(_budgets))
	var l := _loading(v)
	var id := screen_id
	var r := await Api.select("settings?key=eq.durations")
	if not _alive(id): return
	l.queue_free()
	var durs: Array = [300, 600, 900, 1200]
	if r.ok and r.data is Array and r.data.size() > 0 and r.data[0].value is Array:
		durs = r.data[0].value
	for d in durs:
		v.add_child(_btn("%d menit" % int(int(d) / 60), (func(dd):
			sel["duration"] = int(dd)
			_go(_start_options if sel.get("mode") == "pvp" else _start_bot)).bind(d), CARD2, 100))

# ================= 7. PvP: CARI / ROOM =================
func _start_options() -> void:
	var v := _page("Player VS Player", func(): _go(_durations))
	v.add_child(_label("%s | %s | %d menit" % [sel.category_name, Api.rupiah(sel.budget), int(sel.duration / 60)], 24, MUTED))
	v.add_child(_btn("CARI LAWAN ACAK (Ranked)", func(): _create_pvp("queue_pvp"), GOLD, 110))
	v.add_child(_btn("BUAT ROOM (undang teman)", func(): _create_pvp("create_room"), BLUE, 100))
	v.add_child(_label("Gabung dengan kode room:", 24))
	var code := LineEdit.new()
	code.placeholder_text = "Contoh: A1B2C3"
	code.custom_minimum_size.y = 84
	v.add_child(code)
	v.add_child(_btn("GABUNG", func():
		var r := await Api.rpc_call("join_room", {"p_code": code.text})
		if not r.ok:
			toast(str(r.error))
			return
		match_id = str(r.data)
		_go(_waiting), GREEN, 90))

func _create_pvp(fn: String) -> void:
	var r := await Api.rpc_call(fn, {"p_cat": sel.category, "p_budget": sel.budget, "p_dur": sel.duration})
	if not r.ok:
		toast(str(r.error))
		return
	match_id = str(r.data)
	_go(_waiting)

func _start_bot() -> void:
	var v := _page("Menyiapkan Bot...")
	v.add_child(_label("Bot %s sedang bersiap..." % str(sel.get("bot_level", "")).to_upper(), 28, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var r := await Api.rpc_call("start_bot", {"p_cat": sel.category, "p_budget": sel.budget, "p_dur": sel.duration, "p_level": sel.bot_level})
	if not r.ok:
		toast(str(r.error))
		_go(_menu)
		return
	match_id = str(r.data)
	_go(_waiting)

# ================= 13-14. MATCHMAKING / ROOM =================
func _waiting() -> void:
	var v := _page("Mencari Lawan", func():
		await Api.rpc_call("cancel_match", {"p_id": match_id})
		_go(_menu))
	var status := _label("Menghubungkan...", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(status)
	var code_lbl := _label("", 48, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(code_lbl)
	var spin := _label("o  o  o", 40, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(spin)
	var id := screen_id
	var tick := 0
	while _alive(id):
		var r := await Api.rpc_call("get_match", {"p_id": match_id})
		if not _alive(id): return
		if r.ok:
			mdata = r.data
			if mdata.status == "playing" or mdata.status == "finished":
				_go(_game)
				return
			if mdata.status == "cancelled":
				toast("Pertandingan dibatalkan")
				_go(_menu)
				return
			if mdata.get("code") != null:
				status.text = "Bagikan kode room ini ke temanmu:"
				code_lbl.text = str(mdata.code)
			else:
				status.text = "Mencari pemain dengan kategori & budget yang sama..."
		tick += 1
		spin.text = ["O  o  o", "o  O  o", "o  o  O"][tick % 3]
		await get_tree().create_timer(1.5).timeout

# ================= 15-18. GAMEPLAY =================
func _game() -> void:
	finishing = false
	undo_stack.clear()
	pending_item = ""
	dirty = false
	ui = {}
	var id := screen_id
	var r := await Api.rpc_call("get_match", {"p_id": match_id})
	if not _alive(id): return
	if not r.ok:
		toast(str(r.error))
		_go(_menu)
		return
	mdata = r.data
	time_offset = float(mdata.server_now) - Time.get_unix_time_from_system()
	var ir := await Api.select("items?category_id=eq.%s&budget=eq.%d&active=eq.true&order=tag,price" % [mdata.category_id, int(mdata.budget)])
	if not _alive(id): return
	items = ir.data if ir.ok else []
	items_by_id.clear()
	for it in items:
		items_by_id[str(it.id)] = it
	if mdata.status == "finished":
		_go(_result)
		return

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	screen.add_child(root)
	# --- bar atas
	var top := _card(CARD)
	root.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	var row1 := HBoxContainer.new()
	tv.add_child(row1)
	var title := _label("%s - %s" % [mdata.category_name, mdata.theme_name], 26, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(title)
	ui.timer = _label("--:--", 34, Color.WHITE)
	ui.timer.autowrap_mode = TextServer.AUTOWRAP_OFF
	row1.add_child(ui.timer)
	ui.opp = _label("", 22, MUTED)
	tv.add_child(ui.opp)
	ui.tags = _label("Wajib ada: " + ", ".join(PackedStringArray(mdata.required_tags)), 20, Color("#a5b4fc"))
	tv.add_child(ui.tags)
	ui.money = _label("", 22, Color.WHITE)
	tv.add_child(ui.money)
	ui.bar = ProgressBar.new()
	ui.bar.show_percentage = false
	ui.bar.custom_minimum_size.y = 12
	ui.bar.max_value = float(mdata.budget)
	ui.bar.add_theme_stylebox_override("background", _box(BG, 6))
	ui.bar.add_theme_stylebox_override("fill", _box(GREEN, 6))
	tv.add_child(ui.bar)
	# --- area bangun
	canvas = BuildCanvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.items_by_id = items_by_id
	canvas.kind_color = Color(_cat_color())
	canvas.ground_color = Color(_cat_color()).darkened(0.7)
	canvas.set_build((mdata.my_build as Array).duplicate(true))
	canvas.placed.connect(_on_place)
	canvas.selected_changed.connect(func(_i): _refresh_money())
	root.add_child(canvas)
	# --- toolbar
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	root.add_child(tools)
	for t in [["+", func(): canvas.zoom_by(1.2)], ["-", func(): canvas.zoom_by(0.83)],
			["Putar", func(): canvas.rotate_cam()], ["Pusat", func(): canvas.reset_cam()],
			["Warna", _recolor], ["Hapus", _delete_sel], ["Batal", _undo], ["Belanja", _show_list]]:
		var b := _btn(t[0], t[1], CARD2, 70, 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools.add_child(b)
	# --- inventory
	var inv_scroll := ScrollContainer.new()
	inv_scroll.custom_minimum_size.y = 200
	inv_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(inv_scroll)
	var inv := HBoxContainer.new()
	inv.add_theme_constant_override("separation", 10)
	inv_scroll.add_child(inv)
	ui.inv = inv
	_build_inventory()
	# overlay countdown/aktivitas
	ui.overlay = _label("", 90, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	ui.overlay.set_anchors_preset(Control.PRESET_CENTER)
	ui.overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.overlay.position = Vector2(0, size.y * 0.4)
	ui.overlay.size = Vector2(size.x, 120)
	screen.add_child(ui.overlay)
	_refresh_money()
	_game_loop(id)
	_poll_loop(id)

func _cat_color() -> String:
	var m := {"makanan": "#F59E0B", "rumah": "#3B82F6", "kolam": "#06B6D4", "bisnis": "#10B981",
		"taman": "#22C55E", "interior": "#A855F7", "otomotif": "#EF4444", "properti": "#F97316",
		"fashion": "#EC4899", "teknologi": "#6366F1", "umum": "#64748B"}
	return m.get(str(mdata.category_id), "#3B82F6")

func _build_inventory() -> void:
	for c in ui.inv.get_children():
		c.queue_free()
	var left := int(mdata.budget) - _spent()
	for it in items:
		var price := int(it.price)
		var stars := "*".repeat(clampi(int(int(it.quality) / 20), 1, 5))
		var b := _btn("%s\n%s\n%s  [%s]" % [it.name, Api.rupiah(price), stars, it.tag],
			(func(iid): _pick(iid)).bind(str(it.id)),
			Color(str(it.color)).darkened(0.55) if pending_item != str(it.id) else GOLD, 180, 19)
		b.custom_minimum_size.x = 210
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = price > left
		ui.inv.add_child(b)

func _pick(iid: String) -> void:
	pending_item = "" if pending_item == iid else iid
	if pending_item != "":
		toast("Ketuk area kosong untuk memasang", BLUE)
	_build_inventory()

func _spent() -> int:
	var s := 0
	for e in canvas.build:
		var it = items_by_id.get(str(e.item))
		if it != null:
			s += int(it.price)
	return s

func _refresh_money() -> void:
	var sp := _spent()
	var b := int(mdata.budget)
	ui.money.text = "Budget %s  |  Terpakai %s  |  Sisa %s" % [Api.rupiah(b), Api.rupiah(sp), Api.rupiah(b - sp)]
	ui.bar.value = sp

func _editable() -> bool:
	return mdata.status == "playing" and _now() >= float(mdata.started_at) and _now() < float(mdata.ends_at) and not finishing

func _push_undo() -> void:
	undo_stack.append(canvas.build.duplicate(true))
	if undo_stack.size() > 30:
		undo_stack.pop_front()

func _on_place(cell: Vector2i) -> void:
	if not _editable():
		toast("Belum bisa membangun sekarang")
		return
	if pending_item == "":
		toast("Pilih objek di bawah dulu", BLUE)
		return
	var it = items_by_id[pending_item]
	if _spent() + int(it.price) > int(mdata.budget):
		toast("Budget tidak cukup!")
		return
	if canvas.build.size() >= 60:
		toast("Maksimal 60 objek")
		return
	_push_undo()
	canvas.build.append({"item": pending_item, "x": cell.x, "y": cell.y, "color": str(it.color)})
	canvas.pop_in(canvas.build.size() - 1)
	dirty = true
	_refresh_money()
	_build_inventory()

func _recolor() -> void:
	if canvas.selected < 0 or not _editable():
		toast("Ketuk objek untuk memilih", BLUE)
		return
	_push_undo()
	var e: Dictionary = canvas.build[canvas.selected]
	var i := PALETTE.find(str(e.color).to_upper())
	e["color"] = PALETTE[(i + 1) % PALETTE.size()]
	canvas.pop_in(canvas.selected)
	dirty = true

func _delete_sel() -> void:
	if canvas.selected < 0 or not _editable():
		toast("Ketuk objek untuk memilih", BLUE)
		return
	_push_undo()
	canvas.build.remove_at(canvas.selected)
	canvas.selected = -1
	canvas.set_build(canvas.build)
	dirty = true
	_refresh_money()
	_build_inventory()

func _undo() -> void:
	if undo_stack.is_empty() or not _editable():
		return
	canvas.selected = -1
	canvas.set_build(undo_stack.pop_back())
	dirty = true
	_refresh_money()
	_build_inventory()

func _show_list() -> void:
	var counts := {}
	for e in canvas.build:
		counts[str(e.item)] = int(counts.get(str(e.item), 0)) + 1
	var lines := PackedStringArray()
	for k in counts:
		var it = items_by_id.get(k)
		if it != null:
			lines.append("%dx %s = %s" % [counts[k], it.name, Api.rupiah(int(it.price) * int(counts[k]))])
	var d := AcceptDialog.new()
	d.title = "Daftar Pembelian"
	d.dialog_text = ("\n".join(lines) if lines.size() > 0 else "Belum ada pembelian.") + "\n\nTotal: " + Api.rupiah(_spent())
	d.ok_button_text = "Tutup"
	screen.add_child(d)
	d.popup_centered()

func _game_loop(id: int) -> void:
	var last_save := 0.0
	while _alive(id):
		var now := _now()
		var start := float(mdata.started_at)
		var end := float(mdata.ends_at)
		if now < start:
			ui.overlay.text = str(int(ceil(start - now)))
			ui.timer.text = "--:--"
		else:
			if ui.overlay.text != "" and now - start < 1.0:
				ui.overlay.text = "MULAI!"
			elif now - start >= 1.0:
				ui.overlay.text = ""
			var left := maxf(0.0, end - now)
			ui.timer.text = "%02d:%02d" % [int(left) / 60, int(left) % 60]
			ui.timer.add_theme_color_override("font_color", RED if left < 30 else Color.WHITE)
			if dirty and now - last_save > 3.0 and left > 0:
				last_save = now
				_save()
			if left <= 0 and not finishing:
				finishing = true
				canvas.editable = false
				ui.overlay.text = "WAKTU HABIS!"
				if dirty:
					await _save()
				_finish(id)
				return
		await get_tree().create_timer(0.25).timeout

func _save() -> void:
	dirty = false
	var r := await Api.rpc_call("save_build", {"p_id": match_id, "p_build": canvas.build})
	if not r.ok:
		if r.get("network", false):
			dirty = true
			toast("Koneksi putus, mencoba lagi...")
		else:
			toast(str(r.error))

func _poll_loop(id: int) -> void:
	var stages := ["memilih objek", "membeli material", "membangun", "mendekorasi", "menyelesaikan proyek"]
	while _alive(id) and not finishing:
		if mdata.mode == "bot":
			var frac := clampf((_now() - float(mdata.started_at)) / float(mdata.duration_sec), 0.0, 0.999)
			var dots := ".".repeat(1 + int(_now()) % 3)
			ui.opp.text = "VS %s  |  Bot sedang %s%s" % [mdata.opp_name, stages[int(frac * stages.size())], dots]
		else:
			var r := await Api.rpc_call("get_match", {"p_id": match_id})
			if not _alive(id): return
			if r.ok:
				mdata.opp_count = r.data.opp_count
				mdata.opp_online = r.data.opp_online
				time_offset = float(r.data.server_now) - Time.get_unix_time_from_system()
			ui.opp.text = "VS %s (%s)  |  sedang membangun: %d objek" % [mdata.opp_name,
				"online" if mdata.opp_online else "offline", int(mdata.opp_count)]
		await get_tree().create_timer(3.0).timeout

func _finish(id: int) -> void:
	await get_tree().create_timer(1.0).timeout
	var tries := 0
	while _alive(id) and tries < 30:
		ui.overlay.text = "MENILAI..."
		var r := await Api.rpc_call("finish_match", {"p_id": match_id})
		if not _alive(id): return
		if r.ok and r.data.status == "finished":
			mdata = r.data
			_go(_result)
			return
		tries += 1
		await get_tree().create_timer(2.0).timeout
	toast("Penilaian tertunda. Buka lagi dari menu.")

# ================= 19. HASIL =================
func _result() -> void:
	var v := _page("Hasil Pertandingan", func(): _go(_menu))
	var w := str(mdata.winner)
	var me := str(mdata.me)
	var txt := "SERI!" if w == "draw" else ("KAMU MENANG!" if w == me else "KAMU KALAH")
	var banner := _label(txt, 54, GOLD if w == me else (MUTED if w == "draw" else RED), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(banner)
	banner.pivot_offset = Vector2(size.x / 2 - 28, 30)
	banner.scale = Vector2(0.3, 0.3)
	create_tween().set_trans(Tween.TRANS_BACK).tween_property(banner, "scale", Vector2.ONE, 0.6)
	if w == me:
		_confetti()
	v.add_child(_label("%s VS %s | %s - %s | Budget %s" % ["PLAYER" , "BOT" if mdata.mode == "bot" else "PLAYER",
		mdata.category_name, mdata.theme_name, Api.rupiah(mdata.budget)], 22, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	v.add_child(cols)
	var details := VBoxContainer.new()
	details.visible = false
	for side in [["me", mdata.me_name, int(mdata.me_avatar), mdata.my_build, mdata.my_score],
			["opp", mdata.opp_name, int(mdata.opp_avatar), mdata.opp_build, mdata.opp_score]]:
		var c := _card(CARD2 if side[0] == "me" else CARD)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(c)
		var cv := VBoxContainer.new()
		c.add_child(cv)
		var hh := HBoxContainer.new()
		hh.add_child(_avatar(side[2], str(side[1]), 56))
		var nm := _label(str(side[1]), 22)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hh.add_child(nm)
		cv.add_child(hh)
		var mini := BuildCanvas.new()
		mini.custom_minimum_size = Vector2(0, 220)
		mini.editable = false
		mini.items_by_id = items_by_id
		mini.kind_color = Color(_cat_color())
		mini.ground_color = Color(_cat_color()).darkened(0.7)
		mini.set_build(side[3])
		for i in (side[3] as Array).size():
			mini.anim[i] = -0.1 * i
		cv.add_child(mini)
		var s: Dictionary = side[4] if side[4] is Dictionary else {}
		cv.add_child(_label("TOTAL %d" % int(s.get("total", 0)), 34, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		for k in [["kreativitas", 30], ["estetika", 25], ["tema", 20], ["efisiensi", 15], ["kelengkapan", 10]]:
			cv.add_child(_label("%s %d/%d" % [str(k[0]).capitalize(), int(s.get(k[0], 0)), k[1]], 19))
			var pb := ProgressBar.new()
			pb.max_value = k[1]
			pb.value = 0
			pb.show_percentage = false
			pb.custom_minimum_size.y = 10
			pb.add_theme_stylebox_override("background", _box(BG, 5))
			pb.add_theme_stylebox_override("fill", _box(GOLD, 5))
			cv.add_child(pb)
			create_tween().tween_property(pb, "value", float(s.get(k[0], 0)), 1.2)
		var spent := int(s.get("spent", 0))
		cv.add_child(_label("Terpakai %s\nSisa %s" % [Api.rupiah(spent), Api.rupiah(int(mdata.budget) - spent)], 18, MUTED))
		var lines := PackedStringArray()
		for e in side[3]:
			var it = items_by_id.get(str(e.item))
			if it != null:
				lines.append("- %s (%s)" % [it.name, Api.rupiah(it.price)])
		details.add_child(_label(str(side[1]) + ":\n" + ("\n".join(lines) if lines.size() else "(kosong)"), 20))
	v.add_child(_btn("Lihat Detail", func(): details.visible = not details.visible, CARD2, 80))
	v.add_child(details)
	v.add_child(_btn("Main Lagi", func():
		if sel.has("category"):
			_go(_start_options if sel.get("mode") == "pvp" else _start_bot)
		else:
			_go(_menu), GOLD, 90))
	v.add_child(_btn("Bagikan Hasil", func():
		var my: Dictionary = mdata.my_score if mdata.my_score is Dictionary else {}
		var op: Dictionary = mdata.opp_score if mdata.opp_score is Dictionary else {}
		DisplayServer.clipboard_set("BUDGET BATTLE - %s %s\n%s (%d) VS %s (%d)\n%s\nYOUR BUDGET, YOUR CREATIVITY, YOUR VICTORY." % [
			mdata.category_name, Api.rupiah(mdata.budget), mdata.me_name, int(my.get("total", 0)),
			mdata.opp_name, int(op.get("total", 0)), txt])
		toast("Hasil disalin. Tempel di WhatsApp/sosmed.", GREEN), BLUE, 80))
	v.add_child(_btn("Kembali ke Menu", func(): _go(_menu), CARD2, 80))
	Api.load_profile()

func _confetti() -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(size.x / 2, 120)
	p.amount = 120
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 2.5
	p.spread = 180
	p.initial_velocity_min = 300
	p.initial_velocity_max = 700
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 6
	p.scale_amount_max = 12
	var g := Gradient.new()
	g.set_color(0, GOLD)
	g.set_color(1, Color("#ec4899"))
	p.color_initial_ramp = g
	screen.add_child(p)
	p.emitting = true

# ================= 20. LEADERBOARD =================
func _leaderboard(kind := "global") -> void:
	var v := _page("Leaderboard", func(): _go(_menu))
	var tabs := HBoxContainer.new()
	v.add_child(tabs)
	for t in [["global", "Ranked"], ["weekly", "Mingguan"], ["monthly", "Bulanan"], ["all", "Kemenangan"]]:
		var b := _btn(t[1], (func(k): _go(_leaderboard.bind(k))).bind(t[0]), GOLD if t[0] == kind else CARD2, 70, 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	v.add_child(_label("Hanya pertandingan PvP sungguhan. Lawan bot tidak dihitung.", 20, MUTED))
	var l := _loading(v)
	var id := screen_id
	var r := await Api.rpc_call("leaderboard", {"p_kind": kind})
	if not _alive(id): return
	l.queue_free()
	if not r.ok or (r.data as Array).is_empty():
		v.add_child(_label("Belum ada data.", 24, MUTED))
		return
	var rank := 1
	for e in r.data:
		var c := _card(CARD2 if rank > 3 else GOLD.darkened(0.5))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		c.add_child(h)
		h.add_child(_label("#%d" % rank, 28, GOLD))
		h.add_child(_avatar(int(e.avatar), str(e.username), 56))
		var n := _label("%s\nLv %d - %s" % [e.username, int(e.level), Api.rank_name(int(e.rank_points))], 22)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(_label(str(int(e.score)) + ("" if kind == "global" else " menang"), 24, GOLD))
		v.add_child(c)
		rank += 1

# ================= 21. RIWAYAT =================
func _history() -> void:
	var v := _page("Riwayat Pertandingan", func(): _go(_menu))
	var l := _loading(v)
	var id := screen_id
	var r := await Api.rpc_call("my_history")
	if not _alive(id): return
	l.queue_free()
	if not r.ok or (r.data as Array).is_empty():
		v.add_child(_label("Belum ada pertandingan.", 24, MUTED))
		return
	for e in r.data:
		var res := str(e.result)
		var c := _card(GREEN.darkened(0.6) if res == "MENANG" else (RED.darkened(0.6) if res == "KALAH" else CARD2))
		c.add_child(_label("%s  %s - %s\n%s | %s | vs %s\nNilai: %s - %s" % [res, e.category, e.theme,
			"PvP" if e.mode == "pvp" else "Bot", Api.rupiah(e.budget), e.opponent, e.my_total, e.opp_total], 22))
		v.add_child(c)

# ================= 5. PROFIL =================
func _profile() -> void:
	var v := _page("Profil Pemain", func(): _go(_menu))
	var p: Dictionary = Api.profile
	var chosen := [int(p.get("avatar", 0))]
	var big := _avatar(chosen[0], str(p.get("username", "?")), 140)
	var center := CenterContainer.new()
	center.add_child(big)
	v.add_child(center)
	var grid := GridContainer.new()
	grid.columns = 6
	v.add_child(grid)
	for i in 12:
		var b := Button.new()
		b.custom_minimum_size = Vector2(90, 90)
		b.add_theme_stylebox_override("normal", _box(Color(AVATAR_COLORS[i]), 45))
		b.add_theme_stylebox_override("pressed", _box(Color(AVATAR_COLORS[i]).darkened(0.3), 45))
		b.pressed.connect((func(ix):
			chosen[0] = ix
			big.add_theme_stylebox_override("panel", _box(Color(AVATAR_COLORS[ix]), 70, Color.WHITE))).bind(i))
		grid.add_child(b)
	var name_edit := LineEdit.new()
	name_edit.text = str(p.get("username", ""))
	name_edit.custom_minimum_size.y = 84
	v.add_child(name_edit)
	v.add_child(_btn("SIMPAN PROFIL", func():
		var r := await Api.rpc_call("update_profile", {"p_username": name_edit.text, "p_avatar": chosen[0]})
		if r.ok:
			await Api.load_profile()
			toast("Profil disimpan", GREEN)
		else:
			toast(str(r.error)), GOLD))
	var pw := int(p.get("pvp_wins", 0)); var pl := int(p.get("pvp_losses", 0))
	var bw := int(p.get("bot_wins", 0)); var bl := int(p.get("bot_losses", 0))
	var total := pw + pl + bw + bl
	var wr := 0.0 if total == 0 else 100.0 * (pw + bw) / total
	var c := _card(CARD2)
	c.add_child(_label(("ID: %s\nLevel %d | XP %d | Koin %d\nPeringkat: %s (%d poin)\n\nTotal pertandingan: %d | Win rate %.0f%%\n" +
		"VS Pemain: %d menang / %d kalah\nVS Bot: %d menang / %d kalah") % [str(p.get("id", "")).substr(0, 8),
		int(p.get("level", 1)), int(p.get("xp", 0)), int(p.get("coins", 0)), Api.rank_name(int(p.get("rank_points", 1000))),
		int(p.get("rank_points", 1000)), total, wr, pw, pl, bw, bl], 22))
	v.add_child(c)

# ================= 22-23. REWARD & ACHIEVEMENT =================
func _rewards() -> void:
	var v := _page("Reward & Achievement", func(): _go(_menu))
	var p: Dictionary = Api.profile
	var pw := int(p.get("pvp_wins", 0)); var bw := int(p.get("bot_wins", 0))
	var games := pw + bw + int(p.get("pvp_losses", 0)) + int(p.get("bot_losses", 0))
	var lvl := int(p.get("level", 1))
	var titles := ["Tukang Pemula", "Desainer Muda", "Arsitek Kreatif", "Master Renovasi", "Legenda Budget"]
	v.add_child(_label("Gelar: " + titles[clampi(int(lvl / 5), 0, 4)], 30, GOLD))
	v.add_child(_label("Reward tiap pertandingan: Menang +60 XP & 30 koin, Kalah +25 XP & 10 koin (lawan bot setengahnya).", 21, MUTED))
	var ach := [["Pertandingan Pertama", games >= 1], ["Menang Pertama", pw + bw >= 1],
		["Menang 10x lawan pemain", pw >= 10], ["Kalahkan Bot 5x", bw >= 5], ["Main 50 pertandingan", games >= 50],
		["Capai Level 5", lvl >= 5], ["Capai Level 10", lvl >= 10], ["Peringkat Gold", int(p.get("rank_points", 0)) >= 1250],
		["Peringkat Diamond", int(p.get("rank_points", 0)) >= 1600]]
	for a in ach:
		var c := _card(GREEN.darkened(0.55) if a[1] else CARD)
		c.add_child(_label(("[OK] " if a[1] else "[  ] ") + str(a[0]), 24, Color.WHITE if a[1] else MUTED))
		v.add_child(c)

# ================= 24. PENGATURAN =================
func _settings() -> void:
	var v := _page("Pengaturan", func(): _go(_menu))
	v.add_child(_label("Versi 1.0.0\nServer: Supabase (online)", 22, MUTED))
	v.add_child(_btn("Keluar (Logout)", func():
		Api.sign_out()
		_go(_login), RED))

# ================= 25. ADMIN =================
func _admin() -> void:
	var v := _page("Panel Administrator", func(): _go(_menu))
	v.add_child(_label("Untuk menambah kategori/tema/objek baru secara lengkap (termasuk gambar), pakai Supabase > Table Editor. Di sini untuk pengaturan cepat.", 20, MUTED))
	v.add_child(_btn("Kategori (aktif / nonaktif)", func(): _go(_admin_categories), CARD2, 84))
	v.add_child(_btn("Objek & Harga", func(): _go(_admin_items_pick), CARD2, 84))
	v.add_child(_btn("Durasi Pertandingan", func(): _go(_admin_durations), CARD2, 84))
	v.add_child(_btn("Pemain & Sanksi", func(): _go(_admin_players), CARD2, 84))

func _admin_categories() -> void:
	var v := _page("Kategori", func(): _go(_admin))
	var id := screen_id
	var r := await Api.select("categories?order=sort")
	if not _alive(id) or not r.ok: return
	for c in r.data:
		var on: bool = c.active
		v.add_child(_btn("%s : %s" % [c.name, "AKTIF" if on else "NONAKTIF"], (func(cc, st):
			await Api.patch("categories?id=eq." + str(cc.id), {"active": not st})
			_go(_admin_categories)).bind(c, on), GREEN if on else RED, 80, 22))

func _admin_items_pick() -> void:
	var v := _page("Pilih Kategori", func(): _go(_admin))
	var id := screen_id
	var r := await Api.select("categories?order=sort")
	if not _alive(id) or not r.ok: return
	for c in r.data:
		v.add_child(_btn(str(c.name), (func(cid): _go(_admin_items.bind(cid))).bind(str(c.id)), CARD2, 76, 22))

func _admin_items(cid: String) -> void:
	var v := _page("Objek: " + cid, func(): _go(_admin_items_pick))
	var id := screen_id
	var r := await Api.select("items?category_id=eq.%s&order=budget,tag,price" % cid)
	if not _alive(id) or not r.ok: return
	for it in r.data:
		var c := _card(CARD2)
		var h := HBoxContainer.new()
		c.add_child(h)
		var n := _label("%s\n%s | Q%d" % [it.name, Api.rupiah(it.budget), int(it.quality)], 19)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var price := LineEdit.new()
		price.text = str(int(it.price))
		price.custom_minimum_size = Vector2(170, 64)
		price.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		h.add_child(price)
		var on: bool = it.active
		var sb := _btn("OK", (func(iid, pe):
			var rr := await Api.patch("items?id=eq." + iid, {"price": int(pe.text)})
			toast("Harga disimpan" if rr.ok else str(rr.error), GREEN if rr.ok else RED)).bind(str(it.id), price), BLUE, 64, 18)
		h.add_child(sb)
		var tb := _btn("ON" if on else "OFF", (func(iid, st):
			await Api.patch("items?id=eq." + iid, {"active": not st})
			_go(_admin_items.bind(cid))).bind(str(it.id), on), GREEN if on else RED, 64, 18)
		h.add_child(tb)
		v.add_child(c)

func _admin_durations() -> void:
	var v := _page("Durasi (detik)", func(): _go(_admin))
	var e := LineEdit.new()
	e.custom_minimum_size.y = 84
	e.placeholder_text = "300,600,900,1200"
	v.add_child(e)
	var id := screen_id
	var r := await Api.select("settings?key=eq.durations")
	if not _alive(id): return
	if r.ok and r.data.size() > 0:
		e.text = ",".join(PackedStringArray(r.data[0].value.map(func(x): return str(int(x)))))
	v.add_child(_btn("SIMPAN", func():
		var arr: Array = []
		for s in e.text.split(","):
			if s.strip_edges().is_valid_int():
				arr.append(int(s.strip_edges()))
		var rr := await Api.patch("settings?key=eq.durations", {"value": arr})
		toast("Disimpan" if rr.ok else str(rr.error), GREEN if rr.ok else RED), GOLD))

func _admin_players() -> void:
	var v := _page("Pemain", func(): _go(_admin))
	var id := screen_id
	var r := await Api.select("profiles?order=created_at.desc&limit=100")
	if not _alive(id) or not r.ok: return
	for p in r.data:
		var banned: bool = p.banned
		v.add_child(_btn("%s | Lv %d | %d-%d PvP | %s" % [p.username, int(p.level), int(p.pvp_wins), int(p.pvp_losses),
			"DIBLOKIR" if banned else "aktif"], (func(uid, b):
			var rr := await Api.rpc_call("admin_ban", {"p_user": uid, "p_ban": not b})
			if rr.ok: _go(_admin_players)
			else: toast(str(rr.error))).bind(str(p.id), banned), RED if banned else CARD2, 76, 20))
