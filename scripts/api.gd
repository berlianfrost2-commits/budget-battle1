extends Node
## Penghubung ke server Supabase: login, data katalog, dan fungsi pertandingan.

const SESSION_FILE := "user://session.json"

var access_token: String = ""
var refresh_token: String = ""
var user_id: String = ""
var profile: Dictionary = {}
var last_email: String = ""

func _ready() -> void:
	_load_session()

func is_configured() -> bool:
	return Config.SUPABASE_URL.begins_with("http")

func is_logged_in() -> bool:
	return access_token != ""

# ---------- HTTP dasar ----------
func request(method: int, path: String, body = null, use_token: bool = true, retry: bool = true) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "Server belum diatur (SUPABASE_URL kosong)."}
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var token: String = access_token if (use_token and access_token != "") else Config.SUPABASE_ANON_KEY
	var headers := PackedStringArray([
		"apikey: " + Config.SUPABASE_ANON_KEY,
		"Authorization: Bearer " + token,
		"Content-Type: application/json",
	])
	var data := "" if body == null else JSON.stringify(body)
	var err := http.request(Config.SUPABASE_URL + path, headers, method, data)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Tidak bisa menghubungi server."}
	var res: Array = await http.request_completed
	http.queue_free()
	var result_code: int = res[0]
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Koneksi internet bermasalah.", "network": true}
	var parsed = null
	if text != "":
		parsed = JSON.parse_string(text)
	if code >= 200 and code < 300:
		return {"ok": true, "data": parsed}
	if code == 401 and retry and refresh_token != "" and use_token:
		if await refresh():
			return await request(method, path, body, use_token, false)
	var msg := text
	if parsed is Dictionary:
		for k in ["message", "msg", "error_description", "error"]:
			if parsed.has(k) and parsed[k] != null:
				msg = str(parsed[k])
				break
	return {"ok": false, "error": _translate(msg), "code": code}

func _translate(msg: String) -> String:
	if msg.contains("Invalid login credentials"):
		return "Email atau kata sandi salah."
	if msg.contains("already registered"):
		return "Email sudah terdaftar."
	if msg.contains("Password should be"):
		return "Kata sandi minimal 6 karakter."
	if msg.contains("Email not confirmed"):
		return "Email belum dikonfirmasi. Cek kotak masuk email kamu."
	return msg

func rpc_call(fn: String, args: Dictionary = {}) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, args)

func select(table_query: String) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/rest/v1/" + table_query)

func patch(table_query: String, body: Dictionary) -> Dictionary:
	return await request(HTTPClient.METHOD_PATCH, "/rest/v1/" + table_query, body)

# ---------- Akun ----------
func sign_up(email: String, password: String, username: String) -> Dictionary:
	var r := await request(HTTPClient.METHOD_POST, "/auth/v1/signup",
		{"email": email, "password": password, "data": {"username": username}}, false)
	if r.ok and r.data is Dictionary and r.data.has("access_token"):
		_set_session(r.data)
	return r

func sign_in(email: String, password: String) -> Dictionary:
	var r := await request(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password",
		{"email": email, "password": password}, false)
	if r.ok:
		_set_session(r.data)
	return r

func refresh() -> bool:
	var r := await request(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token",
		{"refresh_token": refresh_token}, false, false)
	if r.ok:
		_set_session(r.data)
		return true
	sign_out()
	return false

func sign_out() -> void:
	access_token = ""
	refresh_token = ""
	user_id = ""
	profile = {}
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))

func load_profile() -> Dictionary:
	var r := await select("profiles?id=eq.%s&select=*" % user_id)
	if r.ok and r.data is Array and r.data.size() > 0:
		profile = r.data[0]
	return r

func _set_session(d: Dictionary) -> void:
	access_token = str(d.get("access_token", ""))
	refresh_token = str(d.get("refresh_token", ""))
	var u = d.get("user", {})
	if u is Dictionary:
		user_id = str(u.get("id", ""))
	var f := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"a": access_token, "r": refresh_token, "u": user_id}))

func _load_session() -> void:
	if not FileAccess.file_exists(SESSION_FILE):
		return
	var f := FileAccess.open(SESSION_FILE, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		access_token = str(d.get("a", ""))
		refresh_token = str(d.get("r", ""))
		user_id = str(d.get("u", ""))

# ---------- Format ----------
static func rupiah(v) -> String:
	var n := int(v)
	var s := str(abs(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return ("-Rp" if n < 0 else "Rp") + out

static func rank_name(points: int) -> String:
	if points < 1100: return "Bronze"
	if points < 1250: return "Silver"
	if points < 1400: return "Gold"
	if points < 1600: return "Platinum"
	if points < 1850: return "Diamond"
	return "Master"
