extends Node2D
@onready var mat = $TransitionLayer/ColorRect.material
var is_overlay: bool = false

func _ready():
	$TransitionLayer/ColorRect.visible = true
	mat.set("shader_parameter/luminance_cutoff", 1.0)
	await get_tree().process_frame
	await play_in()

func play_out():
	$TransitionLayer/ColorRect.mouse_filter = Control.MOUSE_FILTER_STOP
	$TransitionLayer/ColorRect.visible = true
	var tween = create_tween()
	tween.tween_property(mat, "shader_parameter/luminance_cutoff", 1.0, 0.8)
	await tween.finished

func play_in():
	var tween = create_tween()
	tween.tween_property(mat, "shader_parameter/luminance_cutoff", 0.0, 0.8)
	await tween.finished
	$TransitionLayer/ColorRect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TransitionLayer/ColorRect.visible = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_exit_pressed() -> void:
	await play_out()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
