extends Control
## Area pembangunan: grid 12x8 dengan tampilan semi-3D (isometrik ringan).
## Mendukung pasang, pilih, geser, hapus, ganti warna, zoom, rotasi & geser kamera.

signal placed(cell: Vector2i)
signal selected_changed(index: int)

const COLS := 12
const ROWS := 8

var build: Array = []            # [{item, x, y, color}]
var items_by_id: Dictionary = {}  # id -> data item
var ground_color := Color("#1f2a44")
var kind_color := Color("#3B82F6")
var editable := true
var selected := -1
var zoom := 1.0
var pan := Vector2.ZERO
var tilt := 0.55                 # rotasi/kemiringan kamera
var anim: Dictionary = {}        # index -> progres animasi 0..1
var _drag_from := Vector2.ZERO
var _dragging := false
var _moved := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_build(b: Array) -> void:
	build = b
	anim.clear()
	for i in build.size():
		anim[i] = 1.0
	queue_redraw()

func pop_in(index: int) -> void:
	anim[index] = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	var busy := false
	for k in anim.keys():
		if anim[k] < 1.0:
			anim[k] = min(1.0, anim[k] + delta * 3.0)
			busy = true
	if busy:
		queue_redraw()

func _cell_size() -> float:
	return min(size.x / (COLS + 1.0), size.y / (ROWS * tilt + 3.0)) * zoom

func _origin() -> Vector2:
	var cs := _cell_size()
	return Vector2((size.x - cs * COLS) / 2.0, (size.y - cs * ROWS * tilt) / 2.0 + cs * 0.6) + pan

func cell_to_pos(c: Vector2i) -> Vector2:
	var cs := _cell_size()
	return _origin() + Vector2(c.x * cs + cs / 2.0, c.y * cs * tilt + cs * tilt / 2.0)

func pos_to_cell(p: Vector2) -> Vector2i:
	var cs := _cell_size()
	var l := p - _origin()
	return Vector2i(int(floor(l.x / cs)), int(floor(l.y / (cs * tilt))))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(0.9)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_moved = false
				_drag_from = mb.position
			else:
				_dragging = false
				if not _moved:
					_tap(mb.position)
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		if mm.position.distance_to(_drag_from) > 12.0:
			_moved = true
		if _moved:
			if editable and selected >= 0:
				var c := pos_to_cell(mm.position)
				if c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS:
					build[selected]["x"] = c.x
					build[selected]["y"] = c.y
			else:
				pan += mm.relative
			queue_redraw()
	elif e is InputEventMagnifyGesture:
		zoom_by((e as InputEventMagnifyGesture).factor)
	elif e is InputEventPanGesture:
		pan -= (e as InputEventPanGesture).delta * 8.0
		queue_redraw()

func _tap(p: Vector2) -> void:
	var c := pos_to_cell(p)
	if c.x < 0 or c.x >= COLS or c.y < 0 or c.y >= ROWS:
		return
	# pilih objek teratas di sel ini
	for i in range(build.size() - 1, -1, -1):
		if int(build[i]["x"]) == c.x and int(build[i]["y"]) == c.y:
			selected = i if selected != i else -1
			selected_changed.emit(selected)
			queue_redraw()
			return
	if selected >= 0:
		selected = -1
		selected_changed.emit(-1)
		queue_redraw()
		return
	if editable:
		placed.emit(c)

func zoom_by(f: float) -> void:
	zoom = clamp(zoom * f, 0.6, 2.5)
	queue_redraw()

func rotate_cam() -> void:
	tilt = 0.55 if tilt > 0.9 else (1.0 if tilt > 0.7 else 0.8)
	queue_redraw()

func reset_cam() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	var cs := _cell_size()
	var o := _origin()
	# lantai/tanah dengan ketebalan (efek 3D)
	var w := cs * COLS
	var h := cs * ROWS * tilt
	draw_rect(Rect2(o + Vector2(0, h), Vector2(w, cs * 0.35)), ground_color.darkened(0.45))
	draw_rect(Rect2(o, Vector2(w, h)), ground_color)
	for x in COLS + 1:
		draw_line(o + Vector2(x * cs, 0), o + Vector2(x * cs, h), Color(1, 1, 1, 0.07), 1.0)
	for y in ROWS + 1:
		draw_line(o + Vector2(0, y * cs * tilt), o + Vector2(w, y * cs * tilt), Color(1, 1, 1, 0.07), 1.0)
	draw_rect(Rect2(o, Vector2(w, h)), kind_color.lightened(0.2), false, 2.0)
	# urutkan dari belakang ke depan supaya tumpukan terlihat benar
	var order: Array = range(build.size())
	order.sort_custom(func(a, b): return int(build[a]["y"]) < int(build[b]["y"]))
	for i in order:
		_draw_item(i, cs)

func _draw_item(i: int, cs: float) -> void:
	var e: Dictionary = build[i]
	var it = items_by_id.get(str(e.get("item", "")), null)
	var shape := "rect"
	var label := "?"
	var q := 50
	if it != null:
		shape = str(it.get("shape", "rect"))
		label = str(it.get("name", "?")).substr(0, 2).to_upper()
		q = int(it.get("quality", 50))
	var col := Color(str(e.get("color", "#cccccc")))
	var t: float = anim.get(i, 1.0)
	var s := ease(t, -2.0) * (0.75 + q / 400.0)
	var base := cell_to_pos(Vector2i(int(e["x"]), int(e["y"])))
	var height := cs * (0.35 + q / 250.0) * s
	var half := cs * 0.42 * s
	# bayangan
	draw_circle(base + Vector2(0, cs * tilt * 0.25), half * 0.9, Color(0, 0, 0, 0.25))
	match shape:
		"circle":
			draw_rect(Rect2(base - Vector2(half * 0.7, height * 0.6), Vector2(half * 1.4, height * 0.6)), col.darkened(0.3))
			draw_circle(base - Vector2(0, height * 0.6), half * 0.75, col)
			draw_circle(base - Vector2(half * 0.2, height * 0.6 + half * 0.2), half * 0.2, Color(1, 1, 1, 0.35))
		"tri":
			var pts := PackedVector2Array([base + Vector2(-half, 0), base + Vector2(half, 0), base + Vector2(0, -height * 1.4)])
			draw_colored_polygon(pts, col)
			draw_colored_polygon(PackedVector2Array([base + Vector2(0, 0), base + Vector2(half, 0), base + Vector2(0, -height * 1.4)]), col.darkened(0.25))
		_:
			# kotak 3D: sisi depan + atap
			var front := Rect2(base + Vector2(-half, -height), Vector2(half * 2, height))
			draw_rect(front, col.darkened(0.2))
			var top := PackedVector2Array([
				base + Vector2(-half, -height), base + Vector2(half, -height),
				base + Vector2(half * 0.8, -height - half * tilt), base + Vector2(-half * 0.8 - 0, -height - half * tilt)])
			draw_colored_polygon(top, col.lightened(0.15))
	var font := ThemeDB.fallback_font
	if cs * s > 26:
		var lc := Color.BLACK if col.get_luminance() > 0.55 else Color.WHITE
		draw_string(font, base + Vector2(-half, -height * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, half * 2, int(cs * 0.26), lc)
	if i == selected:
		draw_arc(base - Vector2(0, height * 0.5), cs * 0.6, 0, TAU, 32, Color("#FACC15"), 3.0)
