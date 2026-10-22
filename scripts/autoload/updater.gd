extends Node
## Atualizador: ao abrir o jogo exportado, pergunta ao GitHub qual é a release mais nova e
## compara o código de build do zip anexado (nome "Furor-<build>.zip") com Net.BUILD. Se
## houver uma mais nova, o menu mostra o aviso; o jogador clica em Atualizar, o zip baixa
## para user://, o Furor.exe novo é extraído ao lado do atual (Furor.new.exe), o atual é
## renomeado para Furor.old.exe (o Windows deixa renomear um .exe aberto, não apagar), o
## novo assume o nome e abre; este fecha. Na abertura seguinte o .old é apagado.
## Os saves ficam em user:// (AppData), fora da pasta do jogo: não são tocados.
## Qualquer falha deixa o .exe atual no lugar e o menu oferece a página da release.
##
## No editor não verifica nada (não é o .exe); "-- --update-check" força a verificação e
## "-- --autoupdate" ainda atualiza sem clique e "-- --update-api=<url>" troca o endereço da
## API (testes).

signal changed   # o estado mudou: o menu redesenha o aviso

enum State { IDLE, CHECKING, AVAILABLE, DOWNLOADING, INSTALLING, FAILED }

const API := "https://api.github.com/repos/PedroRomeu/furor-prototipo/releases/latest"
const PAGE := "https://github.com/PedroRomeu/furor-prototipo/releases/latest"
const ASSET := "^Furor-(\\d+(?:\\.\\d+)*)\\.zip$"
const ZIP_PATH := "user://atualizacao.zip"
const CHECK_TIMEOUT := 10.0

var state := State.IDLE
var latest := ""        # código de build da release mais nova
var error := ""         # o que deu errado, em inglês (msgid): o menu mostra tr(error)
var _url := ""          # link do zip
var _size := 0          # tamanho do zip em bytes (barra de progresso)
var _http: HTTPRequest
var _thread: Thread


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	var args := OS.get_cmdline_user_args()
	var exported := OS.has_feature("template")
	if exported:
		_remove_old()
	if "--autotest" in args:
		return
	if exported or "--update-check" in args or "--autoupdate" in args:
		_check()


func _process(_delta: float) -> void:
	# Só liga durante o download, para a barra andar.
	if state == State.DOWNLOADING:
		changed.emit()


## Fração baixada (0 a 1).
func progress() -> float:
	if _http == null or _size <= 0:
		return 0.0
	return clampf(float(_http.get_downloaded_bytes()) / _size, 0.0, 1.0)


func open_page() -> void:
	OS.shell_open(PAGE)


func start() -> void:
	if state != State.AVAILABLE and state != State.FAILED:
		return
	if _url == "":
		open_page()
		return
	if not OS.has_feature("template"):
		_fail("Only Furor.exe can update itself.")   # i18n
		return
	_set_state(State.DOWNLOADING)
	_request(_url, _on_downloaded, 0.0, ZIP_PATH)
	set_process(true)


# ---------------------------------------------------------------- verificação

func _check() -> void:
	_set_state(State.CHECKING)
	var api := API
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-api="):   # teste com servidor falso
			api = a.trim_prefix("--update-api=")
	_request(api, _on_checked, CHECK_TIMEOUT)


func _on_checked(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_state(State.IDLE)   # sem internet ou GitHub fora: não mostra nada
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		_set_state(State.IDLE)
		return
	var re := RegEx.create_from_string(ASSET)
	for asset in data.get("assets", []):
		var m := re.search(str(asset.get("name", "")))
		if m and newer(m.get_string(1), Net.BUILD):
			latest = m.get_string(1)
			_url = str(asset.get("browser_download_url", ""))
			_size = int(asset.get("size", 0))
	if latest == "":
		_set_state(State.IDLE)
		return
	_set_state(State.AVAILABLE)
	if "--autoupdate" in OS.get_cmdline_user_args():
		start()


## a é mais nova que b? Compara número a número ("0.9.0.10" > "0.9.0.9").
static func newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


# ---------------------------------------------------------------- download e troca

func _on_downloaded(result: int, code: int, _body: PackedByteArray) -> void:
	set_process(false)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("The download failed.")   # i18n
		return
	_set_state(State.INSTALLING)
	# Extrair 110 MB trava a tela por alguns segundos: vai numa thread.
	_thread = Thread.new()
	_thread.start(_extract)
	set_physics_process(true)


## Roda na thread: tira o Furor.exe (e o LEIA-ME) do zip para a pasta do jogo.
## Devolve "" se deu certo, ou o erro.
func _extract() -> String:
	var dir := OS.get_executable_path().get_base_dir()
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(ZIP_PATH)) != OK:
		return "The downloaded file is corrupted."   # i18n
	var found := false
	for file in zip.get_files():
		var name := file.get_file()
		if name != "Furor.exe" and name != "LEIA-ME.txt":
			continue
		var bytes := zip.read_file(file)
		if bytes.is_empty():
			continue
		var target := dir.path_join("Furor.new.exe" if name == "Furor.exe" else name)
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			zip.close()
			return "No permission to write to the game folder."   # i18n
		f.store_buffer(bytes)
		f.close()
		found = found or name == "Furor.exe"
	zip.close()
	if not found:
		return "Furor.exe is not in the zip."   # i18n
	return ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _thread and _thread.is_started():
		_thread.wait_to_finish()


func _physics_process(_delta: float) -> void:
	# A thread terminou: troca os .exe aqui, na thread principal.
	if _thread and _thread.is_started() and not _thread.is_alive():
		var err: String = _thread.wait_to_finish()
		_thread = null
		set_physics_process(false)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ZIP_PATH))
		if err != "":
			_fail(err)
			return
		_swap()


func _swap() -> void:
	var exe := OS.get_executable_path()
	var dir := exe.get_base_dir()
	var fresh := dir.path_join("Furor.new.exe")
	var old := dir.path_join("Furor.old.exe")
	DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(exe, old) != OK:
		DirAccess.remove_absolute(fresh)
		_fail("Couldn't replace Furor.exe.")   # i18n
		return
	if DirAccess.rename_absolute(fresh, exe) != OK:
		DirAccess.rename_absolute(old, exe)   # devolve o atual
		_fail("Couldn't replace Furor.exe.")   # i18n
		return
	OS.create_process(exe, OS.get_cmdline_args())
	get_tree().quit()


func _remove_old() -> void:
	var old := OS.get_executable_path().get_base_dir().path_join("Furor.old.exe")
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)


# ---------------------------------------------------------------- comum

func _request(url: String, done: Callable, timeout: float, file := "") -> void:
	if _http:
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.timeout = timeout
	_http.download_file = file
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(func(result, code, _headers, body): done.call(result, code, body))
	var headers := ["User-Agent: Furor/" + Net.BUILD]
	if file == "":
		headers.append("Accept: application/vnd.github+json")
	if _http.request(url, PackedStringArray(headers)) != OK:
		done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())


func _fail(why: String) -> void:
	error = why
	_set_state(State.FAILED)


func _set_state(s: State) -> void:
	state = s
	changed.emit()
