extends Control

var is_overlay: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_back_button_pressed() -> void:
	if is_overlay:
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.hide_settings()
	else:
		await TransitionLayer.play_out()
		await get_tree().create_timer(0.3).timeout
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		await TransitionLayer.play_in()
