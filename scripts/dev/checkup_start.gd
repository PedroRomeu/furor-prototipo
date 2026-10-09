extends Node
## Cena de entrada do check-up: põe o medidor (checkup.gd) direto na raiz, para ele
## sobreviver à troca de cena para a partida.

func _ready() -> void:
	var driver := Node.new()
	driver.set_script(load("res://scripts/dev/checkup.gd"))
	get_tree().root.add_child.call_deferred(driver)
