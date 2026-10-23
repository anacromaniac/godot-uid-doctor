## Saves each listed text scene or resource (.tscn, .tres) the way the Godot
## editor does, so a hand-written file gets what an editor save adds: the header
## UID, ext_resource UIDs and node unique_ids. Scenes go through the editor's own
## open and save; resources through ResourceSaver with the editor's flags.
## An existing canonical UID is kept, and running it again changes nothing.
## A file the save would change beyond that (the editor drops, for example,
## overrides inside a non-editable instance) is left as it was and reported.
## Usage:
## godot --headless --editor -s res://addons/uid_doctor/resave_scenes.gd -- <res:// paths>
## Judge it by its exit status: the editor prints leak warnings when a script quits it.
extends SceneTree

const SceneUids = preload("res://addons/uid_doctor/scene_uids.gd")
const SceneContent = preload("res://addons/uid_doctor/scene_content.gd")
const EXIT_FAILURE: int = 1
const PROJECT_ROOT: String = "res://"
const SCENE_EXTENSION: String = "tscn"
const WITHOUT_PREVIEW: bool = false
const USAGE: String = "Usage: godot --headless --editor -s res://addons/uid_doctor/resave_scenes.gd -- <res:// paths of .tscn/.tres files>"
const NEEDS_EDITOR: String = "Run with --editor: only the editor's file system writes UIDs on save."
const NOT_PROJECT_PATH: String = "%s: not a res:// path"
const NOT_TEXT_RESOURCE: String = "%s: not a .tscn or .tres file"
const NOT_FOUND: String = "%s: file not found"
const NON_CANONICAL_UID: String = "%s: header UID %s is not in canonical form, so the file was left as it was. Remove the UID from the header and rerun to get a new one."
const NOT_LOADED: String = "%s: cannot load"
const WOULD_CHANGE_CONTENT: String = "%s: not saved, because an editor save would change its content:"
const CHANGED_CONTENT: String = "%s: the save changed its content, so the file was restored:"
const CONTENT_DIFFERENCE: String = "  %s"
const UID_NOT_ASSIGNED: String = "%s: cannot assign a UID: %s"
const NOT_SAVED: String = "%s: not saved: %s"
const UID_CHANGED: String = "%s: header UID changed from %s to %s"
const DUPLICATE_UIDS: String = "Nothing was saved: an ext_resource UID could resolve to the wrong file while two files share a UID. Remove the UID from the copy's header, then rerun."
const UPDATED: String = "%s: updated"
const UNCHANGED: String = "%s: unchanged"

var _paths: PackedStringArray = []
var _bytes_before: Dictionary[String, PackedByteArray] = {}
var _uids_before: Dictionary[String, String] = {}
var _contents_before: Dictionary[String, Dictionary] = {}
var _exit_code: int = OK
var _started: bool = false


func _init() -> void:
	if not Engine.is_editor_hint():
		_fail(NEEDS_EDITOR)
		_fail(USAGE)
		_quit_without_saving()
		return
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		_fail(USAGE)
		_quit_without_saving()
		return
	if _has_duplicate_uids():
		_fail(DUPLICATE_UIDS)
		_quit_without_saving()
		return
	# Read before the editor's first scan, which may rewrite a header UID.
	for path: String in arguments:
		if _is_valid_target(path):
			_paths.append(path)
			_bytes_before[path] = FileAccess.get_file_as_bytes(path)
			_uids_before[path] = SceneUids.header_uid(path)


func _process(_delta: float) -> bool:
	if _started or not _is_editor_ready():
		return false
	_started = true
	_paths = Array(_paths).filter(_keeps_content_when_saved)
	_assign_missing_uids()
	for path: String in _paths:
		_save(path)
	_paths = Array(_paths).filter(_kept_content)
	for path: String in _paths:
		_report(path)
	quit(_exit_code)
	return false


func _quit_without_saving() -> void:
	_started = true
	quit(_exit_code)


## A UID that two files share may resolve to either file when the editor loads a
## reference, so a save could silently retarget it.
func _has_duplicate_uids() -> bool:
	var all_paths: PackedStringArray = SceneUids.text_resources_under(PROJECT_ROOT)
	var problems: PackedStringArray = SceneUids.find_duplicate_uids(all_paths, all_paths)
	for problem: String in problems:
		_fail(problem)
	return not problems.is_empty()


func _is_valid_target(path: String) -> bool:
	if not path.begins_with(PROJECT_ROOT):
		_fail(NOT_PROJECT_PATH % path)
	elif not SceneUids.is_text_resource(path):
		_fail(NOT_TEXT_RESOURCE % path)
	elif not FileAccess.file_exists(path):
		_fail(NOT_FOUND % path)
	elif not SceneUids.header_uid(path).is_empty() and not SceneUids.is_canonical(SceneUids.header_uid(path)):
		_fail(NON_CANONICAL_UID % [path, SceneUids.header_uid(path)])
	else:
		return true
	return false


func _is_editor_ready() -> bool:
	return Engine.has_singleton("EditorInterface") and not EditorInterface.get_resource_filesystem().is_scanning()


func _keeps_content_when_saved(path: String) -> bool:
	var content: Variant = SceneContent.of_file(path)
	if content == null:
		_fail(NOT_LOADED % path)
		return false
	_contents_before[path] = content
	if path.get_extension() != SCENE_EXTENSION:
		return true
	var repacked: Variant = SceneContent.of_scene_repacked(path)
	if repacked == null:
		_fail(NOT_LOADED % path)
		return false
	var differences: PackedStringArray = SceneContent.differences(content, repacked)
	if not differences.is_empty():
		_fail_with_differences(WOULD_CHANGE_CONTENT % path, differences)
		return false
	return true


## Every listed file gets its UID before any is saved, so a file that references
## another listed file can write that file's UID in its ext_resource.
func _assign_missing_uids() -> void:
	for path: String in _paths:
		if not SceneUids.header_uid(path).is_empty():
			continue
		var result: Error = ResourceSaver.set_uid(path, ResourceUID.create_id_for_path(path))
		if result != OK:
			_fail(UID_NOT_ASSIGNED % [path, error_string(result)])
		EditorInterface.get_resource_filesystem().update_file(path)


func _save(path: String) -> void:
	if path.get_extension() == SCENE_EXTENSION:
		_save_scene(path)
	else:
		_save_resource(path)


func _save_scene(path: String) -> void:
	EditorInterface.open_scene_from_path(path)
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null or scene_root.scene_file_path != path:
		_fail(NOT_LOADED % path)
		return
	EditorInterface.save_scene_as(path, WITHOUT_PREVIEW)
	EditorInterface.close_scene()


func _save_resource(path: String) -> void:
	var resource: Resource = ResourceLoader.load(path)
	if resource == null:
		_fail(NOT_LOADED % path)
		return
	var result: Error = ResourceSaver.save(resource, path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	if result != OK:
		_fail(NOT_SAVED % [path, error_string(result)])


## Restores a file whose save changed its content, before any file is checked,
## so a file referencing a restored one reports the UID it lost.
func _kept_content(path: String) -> bool:
	var content_after: Variant = SceneContent.of_file(path)
	var differences: PackedStringArray = (
		SceneContent.differences(_contents_before[path], content_after) if content_after != null else PackedStringArray([NOT_LOADED % path])
	)
	if differences.is_empty():
		return true
	_restore(path)
	_fail_with_differences(CHANGED_CONTENT % path, differences)
	return false


func _report(path: String) -> void:
	var uid_before: String = _uids_before[path]
	var uid_after: String = SceneUids.header_uid(path)
	if not uid_before.is_empty() and uid_after != uid_before:
		_fail(UID_CHANGED % [path, uid_before, uid_after])
	var problems: PackedStringArray = SceneUids.find_problems(path)
	for problem: String in problems:
		_fail(problem)
	if problems.is_empty():
		var changed: bool = FileAccess.get_file_as_bytes(path) != _bytes_before[path]
		print((UPDATED if changed else UNCHANGED) % path)


func _restore(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(_bytes_before[path])
	file.close()
	EditorInterface.get_resource_filesystem().update_file(path)


func _fail_with_differences(message: String, differences: PackedStringArray) -> void:
	_fail(message)
	for difference: String in differences:
		_fail(CONTENT_DIFFERENCE % difference)


func _fail(message: String) -> void:
	printerr(message)
	_exit_code = EXIT_FAILURE
