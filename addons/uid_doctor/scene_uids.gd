## Finds the identifiers an editor save writes into text scenes and resources
## (.tscn, .tres) that a hand-written file lacks or gets wrong: the header UID,
## each ext_resource UID and each node unique_id.
extends RefCounted

const TEXT_RESOURCE_EXTENSIONS: PackedStringArray = ["tscn", "tres"]
const EXCLUDED_DIR: String = "addons"
const HIDDEN_DIR_PREFIX: String = "."
const IGNORE_MARKER_FILE: String = ".gdignore"
const UID_FILE_SUFFIX: String = ".uid"
const IMPORT_FILE_SUFFIX: String = ".import"
const IMPORT_REMAP_SECTION: String = "remap"
const UID_ATTRIBUTE: String = "uid"
const PATH_ATTRIBUTE: String = "path"
const QUOTED_ATTRIBUTE_PATTERN: String = "\\b%s=\"([^\"]*)\""
const UNIQUE_ID_PATTERN: String = "\\bunique_id=-?\\d+\\b"
const ATTRIBUTE_VALUE_GROUP: int = 1
const EXT_RESOURCE_TAG: String = "[ext_resource "
const NODE_TAG: String = "[node "
const LINE_BREAK: String = "\n"
const HEADER_LINE_NUMBER: int = 1
const PATH_LIST_SEPARATOR: String = ", "
const NO_VALUE: String = ""
const MISSING_HEADER_UID: String = "%s:%d: no header UID"
const DUPLICATE_HEADER_UID: String = "%s:%d: header UID %s is also the UID of %s"
const NON_CANONICAL_UID: String = "%s:%d: UID %s is not in canonical form"
const MISSING_EXT_RESOURCE_PATH: String = "%s:%d: ext_resource has no path"
const MISSING_EXT_RESOURCE_UID: String = "%s:%d: ext_resource has no UID"
const MISSING_EXT_RESOURCE_AND_TARGET_UID: String = "%s:%d: ext_resource has no UID, and its target %s has none either"
const MISSING_TARGET: String = "%s:%d: ext_resource target %s does not exist"
const UNREADABLE_TARGET_UID: String = "%s:%d: ext_resource UID is %s, but its target %s has none"
const MISMATCHED_EXT_RESOURCE_UID: String = "%s:%d: ext_resource UID %s differs from %s, the UID of %s"
const MISSING_NODE_UNIQUE_ID: String = "%s:%d: node has no unique_id"


## Problems in every text scene and resource under root_dir, skipping addons/,
## hidden folders and folders Godot ignores.
static func find_problems_under(root_dir: String) -> PackedStringArray:
	var paths: PackedStringArray = text_resources_under(root_dir)
	var problems: PackedStringArray = []
	for path: String in paths:
		problems.append_array(find_problems(path))
	problems.append_array(find_duplicate_uids(paths, paths))
	return problems


static func text_resources_under(root_dir: String) -> PackedStringArray:
	return _text_resources_in(root_dir, root_dir.path_join(EXCLUDED_DIR))


static func is_text_resource(path: String) -> bool:
	return path.get_extension() in TEXT_RESOURCE_EXTENSIONS


## One problem for each of the paths whose header UID another file in
## all_paths also has: a copied file keeps the UID of its original.
static func find_duplicate_uids(paths: PackedStringArray, all_paths: PackedStringArray) -> PackedStringArray:
	var paths_by_uid: Dictionary[String, PackedStringArray] = {}
	for path: String in all_paths:
		var uid: String = header_uid(path)
		if not uid.is_empty():
			paths_by_uid.get_or_add(uid, PackedStringArray()).append(path)
	var problems: PackedStringArray = []
	for path: String in paths:
		var uid: String = header_uid(path)
		var other_paths: Array = Array(paths_by_uid.get(uid, PackedStringArray())).filter(
			func(other_path: String) -> bool: return other_path != path
		)
		if not uid.is_empty() and not other_paths.is_empty():
			problems.append(DUPLICATE_HEADER_UID % [path, HEADER_LINE_NUMBER, uid, PATH_LIST_SEPARATOR.join(other_paths)])
	return problems


## Problems in one text scene or resource, each as "path:line: message".
static func find_problems(path: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split(LINE_BREAK)
	var uid: String = header_uid(path)
	if uid.is_empty():
		problems.append(MISSING_HEADER_UID % [path, HEADER_LINE_NUMBER])
	elif not is_canonical(uid):
		problems.append(NON_CANONICAL_UID % [path, HEADER_LINE_NUMBER, uid])
	for line_index: int in lines.size():
		var line: String = lines[line_index]
		var line_number: int = line_index + 1
		if line.begins_with(EXT_RESOURCE_TAG):
			problems.append_array(_ext_resource_problems(path, line_number, line))
		elif line.begins_with(NODE_TAG) and not _has_unique_id(line):
			problems.append(MISSING_NODE_UNIQUE_ID % [path, line_number])
	return problems


## The UID in the first line of a text scene or resource, or "" if it has none.
static func header_uid(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return NO_VALUE
	return _quoted_attribute(file.get_line(), UID_ATTRIBUTE)


## The UID of any resource file, read from where Godot keeps it: the header of a
## text scene or resource, the .import file of an imported asset, or the .uid
## file of anything else (scripts, shaders).
static func uid_of(path: String) -> String:
	if is_text_resource(path):
		return header_uid(path)
	var import_path: String = path + IMPORT_FILE_SUFFIX
	if FileAccess.file_exists(import_path):
		var import_settings: ConfigFile = ConfigFile.new()
		if import_settings.load(import_path) != OK:
			return NO_VALUE
		return import_settings.get_value(IMPORT_REMAP_SECTION, UID_ATTRIBUTE, NO_VALUE)
	var uid_path: String = path + UID_FILE_SUFFIX
	if not FileAccess.file_exists(uid_path):
		return NO_VALUE
	return FileAccess.get_file_as_string(uid_path).strip_edges()


## True when the UID text is what the engine writes for its value: an invented
## UID that overflows 63 bits still loads, but the editor rewrites it on save.
static func is_canonical(uid: String) -> bool:
	return ResourceUID.id_to_text(ResourceUID.text_to_id(uid)) == uid


static func _ext_resource_problems(path: String, line_number: int, tag: String) -> PackedStringArray:
	var target_path: String = _quoted_attribute(tag, PATH_ATTRIBUTE)
	if target_path.is_empty():
		return [MISSING_EXT_RESOURCE_PATH % [path, line_number]]
	if not FileAccess.file_exists(target_path):
		return [MISSING_TARGET % [path, line_number, target_path]]
	var uid: String = _quoted_attribute(tag, UID_ATTRIBUTE)
	var target_uid: String = uid_of(target_path)
	if uid.is_empty() and target_uid.is_empty():
		return [MISSING_EXT_RESOURCE_AND_TARGET_UID % [path, line_number, target_path]]
	if uid.is_empty():
		return [MISSING_EXT_RESOURCE_UID % [path, line_number]]
	if not is_canonical(uid):
		return [NON_CANONICAL_UID % [path, line_number, uid]]
	if target_uid.is_empty():
		return [UNREADABLE_TARGET_UID % [path, line_number, uid, target_path]]
	if uid != target_uid:
		return [MISMATCHED_EXT_RESOURCE_UID % [path, line_number, uid, target_uid, target_path]]
	return []


static func _text_resources_in(dir_path: String, excluded_dir: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	if FileAccess.file_exists(dir_path.path_join(IGNORE_MARKER_FILE)):
		return paths
	for file_name: String in DirAccess.get_files_at(dir_path):
		if is_text_resource(file_name):
			paths.append(dir_path.path_join(file_name))
	for subdir_name: String in DirAccess.get_directories_at(dir_path):
		var subdir_path: String = dir_path.path_join(subdir_name)
		if subdir_path != excluded_dir and not subdir_name.begins_with(HIDDEN_DIR_PREFIX):
			paths.append_array(_text_resources_in(subdir_path, excluded_dir))
	return paths


static func _has_unique_id(node_tag: String) -> bool:
	return RegEx.create_from_string(UNIQUE_ID_PATTERN).search(node_tag) != null


static func _quoted_attribute(tag: String, attribute: String) -> String:
	var pattern: RegEx = RegEx.create_from_string(QUOTED_ATTRIBUTE_PATTERN % attribute)
	var found: RegExMatch = pattern.search(tag)
	if found == null:
		return NO_VALUE
	return found.get_string(ATTRIBUTE_VALUE_GROUP)
