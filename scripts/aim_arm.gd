class_name AimArm
extends SkeletonModifier3D
## Depois da animação, levanta o braço direito do personagem na direção da mira,
## para ele andar e correr com a arma apontada.

var pitch := 0.0
var _bone := -1


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _bone < 0:
		_bone = skeleton.find_bone("arm-right")
		if _bone < 0:
			return
	var rest := skeleton.get_bone_rest(_bone).basis.get_rotation_quaternion()
	# O braço em repouso aponta para baixo; -90 graus em X o põe para a frente.
	skeleton.set_bone_pose_rotation(_bone, rest * Quaternion(Vector3.RIGHT, -PI / 2.0 - pitch))
