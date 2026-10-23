## Fails when a text scene or resource outside addons/ lacks an identifier the
## editor writes on save, or carries a wrong one. Fix a failure with
## resave_scenes.gd. Usage:
## godot --headless -s res://addons/uid_doctor/check_scene_uids.gd
extends SceneTree

const SceneUids = preload("res://addons/uid_doctor/scene_uids.gd")
const PROJECT_ROOT: String = "res://"
const EXIT_FAILURE: int = 1
const FIX_HINT: String = "Fix with: godot --headless --editor -s res://addons/uid_doctor/resave_scenes.gd -- <res:// paths>"


func _init() -> void:
	var problems: PackedStringArray = SceneUids.find_problems_under(PROJECT_ROOT)
	for problem: String in problems:
		printerr(problem)
	if not problems.is_empty():
		printerr(FIX_HINT)
	quit(EXIT_FAILURE if not problems.is_empty() else OK)
