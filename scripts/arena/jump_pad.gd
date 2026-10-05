class_name JumpPad
extends Area3D
## Plataforma de salto: lança quem pisar nela para cima e para a frente dela (-Z local).

var launch_velocity := Vector3(0, 22.2, -9.3)   # sobe uns 8 m (com Player.GRAVITY_RISE 30)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.6, 2.0)
	cs.shape = box
	cs.position.y = 0.3
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player and body.is_local:
		body.launch(global_transform.basis * launch_velocity)
		Sfx.at(self, "pad", global_position)
