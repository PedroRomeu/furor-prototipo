class_name AimArm
extends SkeletonModifier3D
## Depois da animação, levanta o braço direito do personagem na direção da mira,
## para ele andar e correr com a arma apontada.
##
## Nos Mini Characters o braço é um osso só que, em repouso, sai reto para o lado (-X do
## modelo, que olha para +Z). Para a frente é girar em volta do eixo vertical, como a
## animação "holding-right" do pacote (60 graus); aqui 80, mais reto, para a arma
## apontar para onde o personagem olha. A mira sobe e desce girando em volta de X.
## (Até 2026-10-06 girava só em X: o braço ficava aberto para o lado e a arma, presa no
## ombro, saía da axila.)

const YAW := deg_to_rad(80.0)

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
	skeleton.set_bone_pose_rotation(_bone, rest * Quaternion(Vector3.RIGHT, -pitch) * Quaternion(Vector3.UP, YAW))
