## Describes what a scene or resource produces when loaded: every node of an
## instantiated scene with its stored properties, groups and saved connections,
## or a resource's stored properties. It leaves out how the file spells that
## content (UIDs, unique_ids, sub_resource ids, values equal to the default), so a
## file and its re-save describe equal when the save kept all of its content.
extends RefCounted

const BUILT_IN_PATH_SEPARATOR: String = "::"
const ENGINE_GROUP_PREFIX: String = "_"
# In parentheses, so that no property name can collide with them.
const CLASS_KEY: String = "(class)"
const GROUPS_KEY: String = "(groups)"
const CONNECTIONS_KEY: String = "(connections)"
const NODES_KEY: String = "(nodes)"
const CONNECTION_FORMAT: String = "%s -> %s:%s%s"
const NO_BOUND_ARGUMENTS: String = ""
const NODE_REFERENCE_FORMAT: String = "node %s"
const LOST_NODE: String = "node %s would be dropped"
const ADDED_NODE: String = "node %s would be added"
const CHANGED_NODE: String = "node %s, %s: %s -> %s"
const CHANGED_RESOURCE: String = "%s: %s -> %s"


## The content of the scene or resource saved at path, or null if it can't load.
static func of_file(path: String) -> Variant:
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		return null
	return of_resource(resource)


## The content the editor would save for the scene at path: it opens a scene as
## an edited instance and packs that instance back.
static func of_scene_repacked(path: String) -> Variant:
	var scene: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if scene == null:
		return null
	var root: Node = scene.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	if root == null:
		return null
	var repacked: PackedScene = PackedScene.new()
	var result: Error = repacked.pack(root)
	root.free()
	if result != OK:
		return null
	return of_resource(repacked)


static func of_resource(resource: Resource) -> Variant:
	if not resource is PackedScene:
		return _of_embedded_resource(resource)
	var root: Node = (resource as PackedScene).instantiate()
	if root == null:
		return null
	var nodes: Dictionary[String, Dictionary] = {}
	_describe_tree(root, root, nodes)
	root.free()
	return {NODES_KEY: nodes}


## Human-readable differences between two contents, empty when they are equal.
static func differences(before: Dictionary, after: Dictionary) -> PackedStringArray:
	if before == after:
		return []
	if not before.has(NODES_KEY):
		return _value_differences(CHANGED_RESOURCE, [], before, after)
	var found: PackedStringArray = []
	var nodes_before: Dictionary = before[NODES_KEY]
	var nodes_after: Dictionary = after[NODES_KEY]
	for path: String in nodes_before:
		if not nodes_after.has(path):
			found.append(LOST_NODE % path)
		else:
			found.append_array(_value_differences(CHANGED_NODE, [path], nodes_before[path], nodes_after[path]))
	for path: String in nodes_after:
		if not nodes_before.has(path):
			found.append(ADDED_NODE % path)
	return found


static func _describe_tree(root: Node, node: Node, nodes: Dictionary[String, Dictionary]) -> void:
	var description: Dictionary = _stored_properties(node, root)
	description[CLASS_KEY] = node.get_class()
	description[GROUPS_KEY] = _saved_groups(node)
	description[CONNECTIONS_KEY] = _saved_connections(root, node)
	nodes[str(root.get_path_to(node))] = description
	for child: Node in node.get_children(true):
		_describe_tree(root, child, nodes)


## Node references are described relative to root, the instantiated scene they
## point into, or null outside a scene.
static func _stored_properties(object: Object, root: Node) -> Dictionary:
	var properties: Dictionary = {}
	for property: Dictionary in object.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			properties[property.name] = _value(object.get(property.name), root)
	return properties


static func _saved_groups(node: Node) -> Array:
	var groups: Array = node.get_groups().filter(
		func(group: StringName) -> bool: return not String(group).begins_with(ENGINE_GROUP_PREFIX)
	)
	groups.sort()
	return groups


static func _saved_connections(root: Node, node: Node) -> Array:
	var connections: Array = []
	for signal_info: Dictionary in node.get_signal_list():
		for connection: Dictionary in node.get_signal_connection_list(signal_info.name):
			if connection.flags & CONNECT_PERSIST:
				connections.append(_describe_connection(root, signal_info.name, connection.callable))
	connections.sort()
	return connections


static func _describe_connection(root: Node, signal_name: String, callable: Callable) -> String:
	var target: Node = callable.get_object() as Node
	var target_path: String = str(root.get_path_to(target)) if target != null else str(callable.get_object())
	var bound_arguments: String = str(callable.get_bound_arguments()) if callable.get_bound_arguments_count() > 0 else NO_BOUND_ARGUMENTS
	return CONNECTION_FORMAT % [signal_name, target_path, callable.get_method(), bound_arguments]


static func _of_embedded_resource(resource: Resource) -> Dictionary:
	return _of_embedded_resource_in(resource, null)


static func _of_embedded_resource_in(resource: Resource, root: Node) -> Dictionary:
	var description: Dictionary = _stored_properties(resource, root)
	description[CLASS_KEY] = resource.get_class()
	return description


## A resource saved in its own file is described by its path, because its
## content is not part of this file. An embedded one is described by its content,
## because its sub_resource id may be renumbered. A node by its path in root,
## because each instantiation creates new nodes.
static func _value(value: Variant, root: Node) -> Variant:
	if value is Resource:
		var resource: Resource = value
		if _is_own_file(resource):
			return resource.resource_path
		return _of_embedded_resource_in(resource, root)
	if value is Node and root != null:
		return NODE_REFERENCE_FORMAT % root.get_path_to(value)
	if value is Array:
		return (value as Array).map(func(item: Variant) -> Variant: return _value(item, root))
	if value is Dictionary:
		var described: Dictionary = {}
		for key: Variant in value:
			described[_value(key, root)] = _value(value[key], root)
		return described
	return value


static func _is_own_file(resource: Resource) -> bool:
	return resource.resource_path.is_absolute_path() and not resource.resource_path.contains(BUILT_IN_PATH_SEPARATOR)


## One line per key whose value differs: the prefix arguments, the key, and the
## values before and after, in that order.
static func _value_differences(format: String, prefix: Array, before: Dictionary, after: Dictionary) -> PackedStringArray:
	var keys: Array = before.keys()
	for key: Variant in after:
		if not keys.has(key):
			keys.append(key)
	var found: PackedStringArray = []
	for key: Variant in keys:
		if before.get(key) != after.get(key):
			found.append(format % (prefix + [key, before.get(key), after.get(key)]))
	return found
