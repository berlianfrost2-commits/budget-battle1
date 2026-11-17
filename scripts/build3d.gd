extends SubViewportContainer
## Area pembangunan 3D: grid 12x8, model 3D tiap objek, kamera orbit (putar/zoom),
## pasang, pilih, geser, hapus, ganti warna, dengan animasi pemasangan.

signal placed(cell: Vector2i)
signal selected_changed(index: int)

const COLS := 12
const ROWS := 8

var build: Array = []
var items_by_id: Dictionary = {}
var ground_color := Color("#1f2a44")
var kind_color := Color("#3B82F6")
var editable := true
var selected := -1
var stagger := false              # animasi muncul bergantian (halaman hasil)
var auto_spin := false            # kamera berputar pelan (halaman hasil)

var vp: SubViewport
var cam: Camera3D
var root3d: Node3D
var items_root: Node3D
var ring: MeshInstance3D
var yaw := 0.6
var pitch := 0.95
var dist := 16.5
var target := Vector3(COLS / 2.0, 0, ROWS / 2.0)
var _down := false
var _moved := false
var _from := Vector2.ZERO
var _mats: Dictionary = {}

func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.handle_input_locally = false
	add_child(vp)
	root3d = Node3D.new()
	vp.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0b1020")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#b8c4e8")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	root3d.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 45
	root3d.add_child(cam)
	items_root = Node3D.new()
	root3d.add_child(items_root)
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.52
	ring.mesh = tm
	ring.material_override = _mat(Color("#FACC15"), true)
	ring.visible = false
	root3d.add_child(ring)

func _ready() -> void:
	_build_ground()
	_update_cam()

func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var key := c.to_html() + str(unshaded)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m

func _build_ground() -> void:
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(COLS + 0.6, 0.4, ROWS + 0.6)
	base.mesh = bm
	base.position = Vector3(COLS / 2.0, -0.2, ROWS / 2.0)
	base.material_override = _mat(ground_color.darkened(0.35))
	root3d.add_child(base)
	var a := ground_color
	var b := ground_color.lightened(0.08)
	for x in COLS:
		for y in ROWS:
			var t := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(0.96, 0.96)
			t.mesh = pm
			t.position = Vector3(x + 0.5, 0.005, y + 0.5)
			t.material_override = _mat(a if (x + y) % 2 == 0 else b)
			root3d.add_child(t)
	# bingkai warna kategori
	for s in [[Vector3(COLS / 2.0, 0.05, -0.15), Vector3(COLS + 0.6, 0.1, 0.1)],
			[Vector3(COLS / 2.0, 0.05, ROWS + 0.15), Vector3(COLS + 0.6, 0.1, 0.1)],
			[Vector3(-0.15, 0.05, ROWS / 2.0), Vector3(0.1, 0.1, ROWS + 0.6)],
			[Vector3(COLS + 0.15, 0.05, ROWS / 2.0), Vector3(0.1, 0.1, ROWS + 0.6)]]:
		var f := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = s[1]
		f.mesh = fm
		f.position = s[0]
		f.material_override = _mat(kind_color)
		root3d.add_child(f)

func _update_cam() -> void:
	pitch = clampf(pitch, 0.35, 1.45)
	dist = clampf(dist, 6.0, 30.0)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)

func _process(delta: float) -> void:
	if auto_spin and not _down:
		yaw += delta * 0.25
		_update_cam()
	if selected >= 0 and selected < items_root.get_child_count():
		ring.visible = true
		var n := items_root.get_child(selected) as Node3D
		ring.position = Vector3(n.position.x, 0.06, n.position.z)
		ring.rotate_y(delta * 2.0)
	else:
		ring.visible = false

# ---------- API sama seperti versi 2D ----------
func set_build(b: Array) -> void:
	build = b
	for c in items_root.get_children():
		c.free()
	for i in build.size():
		var n := _make_node(build[i])
		items_root.add_child(n)
		if stagger:
			n.scale = Vector3.ONE * 0.01
			var tw := n.create_tween()
			tw.tween_interval(0.15 * i)
			tw.tween_property(n, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func pop_in(index: int) -> void:
	if index < 0 or index >= build.size():
		return
	var old: Node = null
	if index < items_root.get_child_count():
		old = items_root.get_child(index)
	var n := _make_node(build[index])
	if old:
		items_root.add_child(n)
		items_root.move_child(n, index)
		old.free()
	else:
		items_root.add_child(n)
	n.scale = Vector3(0.01, 0.01, 0.01)
	var start_y := n.position.y
	n.position.y = start_y + 1.5
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "position:y", start_y, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func zoom_by(f: float) -> void:
	dist /= f
	_update_cam()

func rotate_cam() -> void:
	var tw := create_tween()
	tw.tween_method(_set_yaw, yaw, yaw + PI / 2.0, 0.4).set_trans(Tween.TRANS_SINE)

func _set_yaw(v: float) -> void:
	yaw = v
	_update_cam()

func reset_cam() -> void:
	yaw = 0.6
	pitch = 0.95
	dist = 16.5
	_update_cam()

# ---------- Input ----------
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(0.9)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_down = true
				_moved = false
				_from = mb.position
			else:
				_down = false
				if not _moved:
					_tap(mb.position)
		accept_event()
	elif e is InputEventMouseMotion and _down:
		var mm := e as InputEventMouseMotion
		if mm.position.distance_to(_from) > 14.0:
			_moved = true
		if _moved:
			if editable and selected >= 0:
				var c := _cell_at(mm.position)
				if c.x >= 0:
					build[selected]["x"] = c.x
					build[selected]["y"] = c.y
					var n := items_root.get_child(selected) as Node3D
					n.position.x = c.x + 0.5
					n.position.z = c.y + 0.5
			else:
				yaw -= mm.relative.x * 0.008
				pitch += mm.relative.y * 0.006
				_update_cam()
		accept_event()
	elif e is InputEventMagnifyGesture:
		zoom_by((e as InputEventMagnifyGesture).factor)
	elif e is InputEventPanGesture:
		yaw -= (e as InputEventPanGesture).delta.x * 0.05
		_update_cam()

func _cell_at(p: Vector2) -> Vector2i:
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	if absf(d.y) < 0.0001:
		return Vector2i(-1, -1)
	var t := -o.y / d.y
	if t < 0:
		return Vector2i(-1, -1)
	var hit := o + d * t
	var c := Vector2i(int(floor(hit.x)), int(floor(hit.z)))
	if c.x < 0 or c.x >= COLS or c.y < 0 or c.y >= ROWS:
		return Vector2i(-1, -1)
	return c

func _tap(p: Vector2) -> void:
	var c := _cell_at(p)
	if c.x < 0:
		return
	for i in range(build.size() - 1, -1, -1):
		if int(build[i]["x"]) == c.x and int(build[i]["y"]) == c.y:
			selected = i if selected != i else -1
			selected_changed.emit(selected)
			return
	if selected >= 0:
		selected = -1
		selected_changed.emit(-1)
		return
	if editable:
		placed.emit(c)

# ---------- Model 3D tiap objek ----------
func _make_node(e: Dictionary) -> Node3D:
	var it = items_by_id.get(str(e.get("item", "")), null)
	var nm := ""
	var shape := "rect"
	var q := 50
	if it != null:
		nm = str(it.get("name", "")).to_lower()
		shape = str(it.get("shape", "rect"))
		q = int(it.get("quality", 50))
	var col := Color(str(e.get("color", "#cccccc")))
	var n := Node3D.new()
	n.position = Vector3(int(e["x"]) + 0.5, 0, int(e["y"]) + 0.5)
	var s := 0.85 + q / 500.0   # kualitas tinggi = sedikit lebih besar/megah
	var m := Node3D.new()
	m.scale = Vector3(s, s, s)
	n.add_child(m)
	_model(m, nm, shape, col, q)
	return n

func _box(p: Node3D, size: Vector3, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(c)
	p.add_child(mi)

func _cyl(p: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, seg := 16) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(c)
	p.add_child(mi)

func _sph(p: Node3D, r: float, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c)
	p.add_child(mi)

func _prism(p: Node3D, size: Vector3, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.position = pos
	mi.material_override = _mat(c)
	p.add_child(mi)

func _has(nm: String, words: Array) -> bool:
	for w in words:
		if nm.contains(w):
			return true
	return false

func _model(m: Node3D, nm: String, shape: String, c: Color, q: int) -> void:
	var dark := c.darkened(0.35)
	var wood := Color("#8B5A2B")
	var metal := Color("#9CA3AF")
	var green := Color("#16A34A")
	if _has(nm, ["kolam"]):
		_box(m, Vector3(0.96, 0.08, 0.96), Vector3(0, 0.04, 0), Color("#E5E7EB"))
		_box(m, Vector3(0.8, 0.05, 0.8), Vector3(0, 0.08, 0), c)
	elif _has(nm, ["lantai", "keramik", "karpet", "rumput", "jalan", "deck", "epoxy", "parkir", "lapangan"]):
		_box(m, Vector3(0.96, 0.06, 0.96), Vector3(0, 0.03, 0), c)
	elif _has(nm, ["sofa"]):
		_box(m, Vector3(0.9, 0.25, 0.5), Vector3(0, 0.17, 0), c)
		_box(m, Vector3(0.9, 0.35, 0.12), Vector3(0, 0.35, -0.2), dark)
		_box(m, Vector3(0.12, 0.3, 0.5), Vector3(-0.42, 0.25, 0), dark)
		_box(m, Vector3(0.12, 0.3, 0.5), Vector3(0.42, 0.25, 0), dark)
	elif _has(nm, ["kasur"]):
		_box(m, Vector3(0.8, 0.2, 0.95), Vector3(0, 0.1, 0), wood)
		_box(m, Vector3(0.75, 0.12, 0.9), Vector3(0, 0.26, 0), c)
		_box(m, Vector3(0.6, 0.08, 0.2), Vector3(0, 0.36, -0.3), Color.WHITE)
		_box(m, Vector3(0.8, 0.45, 0.06), Vector3(0, 0.3, -0.47), wood)
	elif _has(nm, ["kursi", "bangku"]):
		_box(m, Vector3(0.45, 0.06, 0.45), Vector3(0, 0.3, 0), c)
		_box(m, Vector3(0.45, 0.4, 0.06), Vector3(0, 0.5, -0.2), c)
		for x in [-0.18, 0.18]:
			for z in [-0.18, 0.18]:
				_box(m, Vector3(0.05, 0.3, 0.05), Vector3(x, 0.15, z), dark)
	elif _has(nm, ["meja", "resepsionis", "kasir"]):
		_box(m, Vector3(0.85, 0.07, 0.6), Vector3(0, 0.45, 0), c)
		for x in [-0.36, 0.36]:
			for z in [-0.24, 0.24]:
				_box(m, Vector3(0.06, 0.45, 0.06), Vector3(x, 0.22, z), dark)
		if _has(nm, ["kasir"]):
			_box(m, Vector3(0.3, 0.2, 0.2), Vector3(0, 0.6, 0), Color("#111827"))
	elif _has(nm, ["lemari", "rak", "etalase", "kulkas", "server"]):
		_box(m, Vector3(0.8, 1.1, 0.4), Vector3(0, 0.55, 0), c)
		for y in [0.3, 0.6, 0.9]:
			_box(m, Vector3(0.82, 0.03, 0.42), Vector3(0, y, 0.01), dark)
	elif _has(nm, ["lampu", "led", "neon", "rgb"]):
		_cyl(m, 0.12, 0.18, 0.06, Vector3(0, 0.03, 0), metal)
		_cyl(m, 0.025, 0.025, 0.9, Vector3(0, 0.48, 0), metal, 8)
		_sph(m, 0.16, Vector3(0, 0.98, 0), c)
		var l := OmniLight3D.new()
		l.light_color = c
		l.light_energy = 0.8
		l.omni_range = 2.0
		l.position = Vector3(0, 1.0, 0)
		m.add_child(l)
	elif _has(nm, ["pohon", "palem", "tanaman", "taman", "bunga", "pot"]):
		if _has(nm, ["pot", "bunga"]):
			_cyl(m, 0.18, 0.13, 0.25, Vector3(0, 0.12, 0), Color("#B45309"))
			_sph(m, 0.22, Vector3(0, 0.38, 0), c)
		else:
			_cyl(m, 0.06, 0.08, 0.6, Vector3(0, 0.3, 0), wood, 8)
			_sph(m, 0.34, Vector3(0, 0.8, 0), green if c.g < 0.4 else c)
			_sph(m, 0.24, Vector3(0.12, 1.05, 0.05), (green if c.g < 0.4 else c).lightened(0.15))
	elif _has(nm, ["mobil"]):
		_box(m, Vector3(0.9, 0.25, 0.48), Vector3(0, 0.2, 0), c)
		_box(m, Vector3(0.5, 0.2, 0.44), Vector3(-0.05, 0.42, 0), Color("#93C5FD"))
		for x in [-0.3, 0.3]:
			for z in [-0.24, 0.24]:
				_cyl(m, 0.1, 0.1, 0.06, Vector3(x, 0.1, z), Color("#111827"))
				(m.get_child(m.get_child_count() - 1) as Node3D).rotation_degrees.x = 90
	elif _has(nm, ["motor"]):
		_box(m, Vector3(0.7, 0.12, 0.12), Vector3(0, 0.3, 0), c)
		_box(m, Vector3(0.25, 0.1, 0.16), Vector3(-0.1, 0.42, 0), Color("#111827"))
		for x in [-0.28, 0.28]:
			_cyl(m, 0.14, 0.14, 0.05, Vector3(x, 0.14, 0), Color("#111827"))
			(m.get_child(m.get_child_count() - 1) as Node3D).rotation_degrees.x = 90
	elif _has(nm, ["payung", "gazebo"]):
		_cyl(m, 0.03, 0.03, 0.9, Vector3(0, 0.45, 0), wood, 8)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.5
		cm.height = 0.3
		cone.mesh = cm
		cone.position = Vector3(0, 1.0, 0)
		cone.material_override = _mat(c)
		m.add_child(cone)
		if _has(nm, ["gazebo"]):
			for x in [-0.4, 0.4]:
				for z in [-0.4, 0.4]:
					_box(m, Vector3(0.06, 0.9, 0.06), Vector3(x, 0.45, z), wood)
			_box(m, Vector3(0.9, 0.05, 0.9), Vector3(0, 0.03, 0), wood)
	elif _has(nm, ["air mancur"]):
		_cyl(m, 0.45, 0.45, 0.15, Vector3(0, 0.08, 0), metal)
		_cyl(m, 0.38, 0.38, 0.05, Vector3(0, 0.15, 0), Color("#38BDF8"))
		_cyl(m, 0.06, 0.08, 0.5, Vector3(0, 0.4, 0), metal, 8)
		_sph(m, 0.12, Vector3(0, 0.7, 0), Color("#7DD3FC"))
	elif _has(nm, ["bangunan", "gedung", "toko", "kamar", "restoran", "ruang kelas", "toilet"]):
		var h := 0.7 + q / 120.0
		_box(m, Vector3(0.9, h, 0.9), Vector3(0, h / 2.0, 0), c)
		_box(m, Vector3(0.22, 0.35, 0.02), Vector3(0, 0.18, 0.46), wood)
		for x in [-0.25, 0.25]:
			_box(m, Vector3(0.18, 0.16, 0.02), Vector3(x, h * 0.7, 0.46), Color("#BFDBFE"))
		_prism(m, Vector3(1.0, 0.35, 1.0), Vector3(0, h + 0.17, 0), Color("#B45309"))
	elif _has(nm, ["atap"]):
		_prism(m, Vector3(0.96, 0.5, 0.96), Vector3(0, 0.25, 0), c)
	elif _has(nm, ["dinding", "gapura", "papan nama", "neon box"]):
		_box(m, Vector3(0.96, 0.9, 0.12), Vector3(0, 0.45, 0), c)
	elif _has(nm, ["pintu"]):
		_box(m, Vector3(0.5, 0.95, 0.08), Vector3(0, 0.48, 0), c)
		_sph(m, 0.03, Vector3(0.17, 0.48, 0.05), Color("#FACC15"))
	elif _has(nm, ["jendela", "cermin"]):
		_box(m, Vector3(0.7, 0.6, 0.06), Vector3(0, 0.5, 0), wood)
		_box(m, Vector3(0.6, 0.5, 0.07), Vector3(0, 0.5, 0), Color("#BFDBFE"))
	elif _has(nm, ["tv", "monitor", "proyektor", "laptop", "pc"]):
		_box(m, Vector3(0.5, 0.06, 0.3), Vector3(0, 0.03, 0), Color("#1F2937"))
		_box(m, Vector3(0.06, 0.3, 0.06), Vector3(0, 0.18, 0), Color("#1F2937"))
		_box(m, Vector3(0.8, 0.48, 0.05), Vector3(0, 0.55, 0), Color("#111827"))
		_box(m, Vector3(0.72, 0.4, 0.01), Vector3(0, 0.55, 0.03), c.lightened(0.3))
	elif _has(nm, ["poster", "lukisan", "patung"]):
		if _has(nm, ["patung"]):
			_box(m, Vector3(0.4, 0.3, 0.4), Vector3(0, 0.15, 0), metal)
			_sph(m, 0.2, Vector3(0, 0.55, 0), c)
		else:
			_box(m, Vector3(0.6, 0.8, 0.05), Vector3(0, 0.6, 0), wood)
			_box(m, Vector3(0.5, 0.7, 0.06), Vector3(0, 0.6, 0), c)
	elif _has(nm, ["ayunan", "perosotan"]):
		_box(m, Vector3(0.06, 0.9, 0.06), Vector3(-0.4, 0.45, 0), c)
		_box(m, Vector3(0.06, 0.9, 0.06), Vector3(0.4, 0.45, 0), c)
		_box(m, Vector3(0.86, 0.06, 0.06), Vector3(0, 0.9, 0), c)
		_box(m, Vector3(0.3, 0.04, 0.18), Vector3(0, 0.35, 0), dark)
	elif _has(nm, ["kompor", "wajan", "panci"]):
		_box(m, Vector3(0.7, 0.12, 0.45), Vector3(0, 0.06, 0), Color("#374151"))
		_cyl(m, 0.12, 0.1, 0.1, Vector3(-0.17, 0.17, 0), c)
		_cyl(m, 0.12, 0.1, 0.1, Vector3(0.17, 0.17, 0), c)
	elif _has(nm, ["piring", "nasi", "lauk", "sayur", "bumbu", "dessert", "kue"]):
		_cyl(m, 0.32, 0.28, 0.04, Vector3(0, 0.02, 0), Color.WHITE)
		_sph(m, 0.16, Vector3(0, 0.12, 0), c)
		if _has(nm, ["kue", "dessert"]):
			_cyl(m, 0.18, 0.2, 0.25, Vector3(0, 0.16, 0), c)
			_sph(m, 0.05, Vector3(0, 0.33, 0), Color("#DC2626"))
	elif _has(nm, ["speaker", "ac", "router", "kotak"]):
		_box(m, Vector3(0.35, 0.6, 0.35), Vector3(0, 0.3, 0), c)
		_cyl(m, 0.1, 0.1, 0.02, Vector3(0, 0.4, 0.18), Color("#111827"))
		(m.get_child(m.get_child_count() - 1) as Node3D).rotation_degrees.x = 90
	elif _has(nm, ["manekin", "kaos", "jaket", "celana", "rok"]):
		_cyl(m, 0.12, 0.15, 0.04, Vector3(0, 0.02, 0), metal)
		_cyl(m, 0.02, 0.02, 0.4, Vector3(0, 0.22, 0), metal, 6)
		_cyl(m, 0.16, 0.2, 0.45, Vector3(0, 0.6, 0), c)
		_sph(m, 0.1, Vector3(0, 0.92, 0), Color("#E5E7EB"))
	elif _has(nm, ["sepatu", "tas", "jam", "perhiasan"]):
		_box(m, Vector3(0.5, 0.35, 0.5), Vector3(0, 0.17, 0), Color("#F3F4F6"))
		_box(m, Vector3(0.3, 0.18, 0.2), Vector3(0, 0.44, 0), c)
	else:
		match shape:
			"circle":
				_cyl(m, 0.35, 0.35, 0.4, Vector3(0, 0.2, 0), c)
			"tri":
				_prism(m, Vector3(0.7, 0.8, 0.7), Vector3(0, 0.4, 0), c)
			_:
				_box(m, Vector3(0.7, 0.6, 0.7), Vector3(0, 0.3, 0), c)
