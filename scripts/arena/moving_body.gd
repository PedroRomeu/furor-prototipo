class_name MovingBody
extends AnimatableBody3D
## Peça que se move sozinha: vai e volta entre dois pontos (offset) e/ou gira (spin).
## AnimatableBody3D carrega quem estiver em cima e empurra quem estiver no caminho.

var base := Vector3.ZERO
var offset := Vector3.ZERO
var period := 4.0
var phase := 0.0
var spin := 0.0
var t := 0.0


func _physics_process(delta: float) -> void:
	t += delta
	if spin != 0.0:
		rotate_y(spin * delta)
	if offset != Vector3.ZERO:
		position = base + offset * sin(TAU * t / period + phase)
