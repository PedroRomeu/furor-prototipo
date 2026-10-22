extends Node
## Ferramenta de tradução (2026-10-22; ver Lang). Roda sem janela:
##   Godot --headless --path . res://scenes/dev/i18n.tscn
## 1. Junta todo texto traduzível: tr("..."), tr_n("...", "..."), Lang.t("...") nos .gd,
##    os textos das linhas marcadas com "# i18n" (todas as aspas da linha) e os que as
##    tabelas devolvem em i18n_strings() -> Array de [texto, contexto, origem]: função
##    estática em qualquer script, ou de autoload listado em SOURCES (CardDB). Escreve
##    locale/furor.pot.
## 2. Em cada locale/*.po: põe os textos novos (vazios, para traduzir) e manda os que
##    saíram para o fim, como obsoletos ("#~"), sem perder a tradução.
## 3. Diz quantos faltam traduzir em cada idioma ("-- --faltando" lista quais).

const POT_PATH := "res://locale/furor.pot"
const LOCALE_DIR := "res://locale/"
const SCAN_DIRS := ["res://scripts/"]
const SKIP := ["res://scripts/dev/"]
## Autoloads com i18n_strings() não estática.
const SOURCES := ["CardDB", "GameState"]

var _entries := {}   # chave -> {id, ctx, plural, refs}
var _order: Array = []


func _ready() -> void:
	var re_call := RegEx.create_from_string(
		"(?:\\btr|\\bLang\\.t)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"(?:\\s*,\\s*\"((?:[^\"\\\\]|\\\\.)*)\")?")
	var re_plural := RegEx.create_from_string(
		"\\btr_n\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*,\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var re_literal := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	for path in _scripts():
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			var code := _strip_comment(line)
			var ref := "%s:%d" % [path.trim_prefix("res://"), i + 1]
			for m in re_call.search_all(code):
				_add(_unescape(m.get_string(1)), _unescape(m.get_string(2)), "", ref)
			for m in re_plural.search_all(code):
				_add(_unescape(m.get_string(1)), "", _unescape(m.get_string(2)), ref)
			if line.contains("# i18n"):
				for m in re_literal.search_all(code):
					if not code.substr(m.get_end()).strip_edges().begins_with(":"):   # chave de dicionário
						_add(_unescape(m.get_string(1)), "", "", ref)
		if text.contains("\nstatic func i18n_strings("):
			for e in load(path).i18n_strings():
				_add(e[0], e[1], "", e[2])
	for source in SOURCES:
		var node := get_node_or_null("/root/" + source)
		if node and node.has_method("i18n_strings"):
			for e in node.i18n_strings():
				_add(e[0], e[1], "", e[2])
	_write_pot()
	var missing_list := "--faltando" in OS.get_cmdline_user_args()
	for file in DirAccess.get_files_at(LOCALE_DIR):
		if file.get_extension() == "po":
			_update_po(LOCALE_DIR + file, missing_list)
	print("Textos: %d (%s)" % [_order.size(), POT_PATH])
	get_tree().quit()


func _scripts() -> Array:
	var out := []
	var dirs: Array = SCAN_DIRS.duplicate()
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		if SKIP.has(dir):
			continue
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir + sub + "/")
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() == "gd":
				out.append(dir + f)
	out.sort()
	return out


## Tira o comentário do fim da linha (sem cortar um # dentro de aspas).
func _strip_comment(line: String) -> String:
	var quoted := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "\\" and quoted:
			i += 2
			continue
		if c == "\"":
			quoted = not quoted
		elif c == "#" and not quoted:
			return line.substr(0, i)
		i += 1
	return line


func _unescape(s: String) -> String:
	return s.c_unescape()


func _add(id: String, ctx: String, plural: String, ref: String) -> void:
	if id.strip_edges() == "" or not RegEx.create_from_string("[A-Za-z]").search(id):
		return
	var key := ctx + "\u0004" + id
	if not _entries.has(key):
		_entries[key] = {"id": id, "ctx": ctx, "plural": plural, "refs": []}
		_order.append(key)
	if _entries[key]["refs"].size() < 4:
		_entries[key]["refs"].append(ref)


static func _quote(s: String) -> String:
	return "\"" + s.c_escape().replace("\\'", "'") + "\""


func _write_pot() -> void:
	var out := PackedStringArray([
		"# Furor: textos do jogo. Gerado por scenes/dev/i18n.tscn; não editar à mão.",
		"msgid \"\"", "msgstr \"\"",
		"\"Content-Type: text/plain; charset=UTF-8\\n\"", ""])
	for key in _order:
		out.append_array(_block(_entries[key], {}))
	var f := FileAccess.open(POT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(out))


## Linhas de uma entrada. tr: {"str": msgstr} ou {"plural": [msgstr[0], msgstr[1]]}.
func _block(e: Dictionary, tr: Dictionary, obsolete := false) -> PackedStringArray:
	var out := PackedStringArray()
	var pre := "#~ " if obsolete else ""
	if not obsolete:
		for r in e.get("refs", []):
			out.append("#: " + r)
	if e["ctx"] != "":
		out.append(pre + "msgctxt " + _quote(e["ctx"]))
	out.append(pre + "msgid " + _quote(e["id"]))
	if e.get("plural", "") != "":
		out.append(pre + "msgid_plural " + _quote(e["plural"]))
		var forms: Array = tr.get("plural", ["", ""])
		for k in forms.size():
			out.append(pre + "msgstr[%d] %s" % [k, _quote(forms[k])])
	else:
		out.append(pre + "msgstr " + _quote(tr.get("str", "")))
	out.append("")
	return out


## Lê um .po: chave -> {"str"} ou {"plural"}; também o cabeçalho (msgid "").
func _read_po(path: String) -> Dictionary:
	var result := {}
	var header := ""
	var cur := {}
	var field := ""
	var text := FileAccess.get_file_as_string(path)
	for raw in (text + "\n\n").split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#~ "):
			line = line.substr(3)
		if line == "" or line.begins_with("#"):
			if cur.has("id"):
				var key: String = cur.get("ctx", "") + "\u0004" + cur["id"]
				if cur["id"] == "" and cur.get("ctx", "") == "":
					header = cur.get("str", "")
				else:
					result[key] = cur
			cur = {}
			field = ""
			continue
		var value := ""
		var q := line.find("\"")
		if q >= 0:
			value = line.substr(q + 1, line.length() - q - 2).c_unescape()
		if line.begins_with("msgctxt"):
			field = "ctx"
		elif line.begins_with("msgid_plural"):
			field = "plural_id"
		elif line.begins_with("msgid"):
			field = "id"
		elif line.begins_with("msgstr["):
			field = "p" + line.get_slice("[", 1).get_slice("]", 0)
		elif line.begins_with("msgstr"):
			field = "str"
		elif line.begins_with("\""):
			cur[field] = cur.get(field, "") + value
			continue
		cur[field] = value
	for key in result:
		var e: Dictionary = result[key]
		if e.has("p0"):
			e["plural"] = [e.get("p0", ""), e.get("p1", "")]
	return {"entries": result, "header": header}


func _update_po(path: String, list_missing: bool) -> void:
	var po := _read_po(path)
	var old: Dictionary = po["entries"]
	# Pedaços soltos (locale/_parts/<idioma>.<qualquer>.po, ex. de traduções feitas em
	# paralelo): completam o que falta e podem ser apagados depois.
	var lang := path.get_file().get_basename()
	var parts_dir := LOCALE_DIR + "_parts/"
	if DirAccess.dir_exists_absolute(parts_dir):
		for file in DirAccess.get_files_at(parts_dir):
			if file.begins_with(lang + ".") and file.get_extension() == "po":
				var part: Dictionary = _read_po(parts_dir + file)["entries"]
				for key in part:
					if old.get(key, {}).get("str", "") == "" and not old.get(key, {}).has("plural"):
						old[key] = part[key]
	var header: String = po["header"]
	if header == "":
		header = "Content-Type: text/plain; charset=UTF-8\nLanguage: %s\n" % path.get_file().get_basename()
	var out := PackedStringArray(["msgid \"\""])
	out.append("msgstr \"\"")
	for h in header.split("\n", false):
		out.append(_quote(h + "\n"))
	out.append("")
	var missing := []
	for key in _order:
		var tr: Dictionary = old.get(key, {})
		out.append_array(_block(_entries[key], tr))
		var done: bool = tr.get("str", "") != "" or (tr.has("plural") and tr["plural"][0] != "")
		if not done:
			missing.append(_entries[key]["id"])
	var gone := 0
	for key in old:
		if not _entries.has(key) and (old[key].get("str", "") != "" or old[key].has("plural")):
			out.append_array(_block({"id": old[key]["id"], "ctx": old[key].get("ctx", ""),
				"plural": old[key].get("plural_id", "")}, old[key], true))
			gone += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(out))
	print("%s: %d sem tradução, %d obsoletos" % [path.get_file(), missing.size(), gone])
	if list_missing:
		for id in missing:
			print("  - " + id.replace("\n", "\\n"))
