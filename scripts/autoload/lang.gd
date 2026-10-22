extends Node
## Idioma do jogo (2026-10-22, pedido do usuário: jogo em inglês por padrão, pt-BR nas
## Configurações, pronto para mais línguas).
##
## Como funciona (gettext, o sistema de tradução do próprio Godot):
## - Todo texto que o jogador vê é escrito EM INGLÊS no código, dentro de tr("...") (ou
##   Lang.t("...") em função estática). O inglês é o idioma-fonte: não tem arquivo próprio.
## - Cada outro idioma é um arquivo locale/<código>.po (msgid em inglês, msgstr traduzido),
##   registrado em project.godot (Localização). Texto sem tradução aparece em inglês.
## - Texto com números: tr("%d kills") % n, nunca tr("%d kills" % n).
## - Texto que vai pela rede vai em inglês (ou como id) e cada máquina traduz ao mostrar.
## - Ferramenta: scenes/dev/i18n.tscn gera locale/furor.pot com todos os textos e põe nos
##   .po os que faltam (vazios); diz quantos faltam traduzir em cada idioma.
##
## Língua nova: traduzir uma cópia de locale/furor.pot (Poedit ou à mão) como
## locale/<código>.po, registrar em project.godot e pôr uma linha em LANGUAGES.

## [código, nome na própria língua]. O primeiro é o padrão.
const LANGUAGES := [["en", "English"], ["pt_BR", "Português (Brasil)"]]
const SETTINGS_PATH := "user://settings.cfg"

signal changed

var current: String = LANGUAGES[0][0]


func _ready() -> void:
	# Os textos já chegam traduzidos pelo tr(): sem isso o Godot tentaria traduzir de novo
	# todo Label e Button, inclusive nomes de jogadores.
	get_tree().root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var saved := String(cfg.get_value("geral", "idioma", current))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--idioma="):
			saved = arg.get_slice("=", 1)
	_apply(saved if codes().has(saved) else current)


func codes() -> Array:
	return LANGUAGES.map(func(l): return l[0])


func names() -> Array:
	return LANGUAGES.map(func(l): return l[1])


## Troca e salva. Quem mostra texto refaz a tela (o menu principal se recarrega).
func set_language(code: String) -> void:
	if code == current or not codes().has(code):
		return
	_apply(code)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("geral", "idioma", code)
	cfg.save(SETTINGS_PATH)
	changed.emit()


func _apply(code: String) -> void:
	current = code
	TranslationServer.set_locale(code)


## tr() para funções estáticas (que não têm o tr() do Node).
static func t(text: String, context := "") -> String:
	return String(TranslationServer.translate(text, context))


## Número com a vírgula ou o ponto do idioma: num(1.5) = "1.5" ou "1,5".
func num(value: float, decimals := 1) -> String:
	var text := String.num(value, decimals)
	return text.replace(".", ",") if current.begins_with("pt") else text
