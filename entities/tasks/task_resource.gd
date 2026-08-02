class_name TaskResource
extends Resource

@export var task_id: String
@export var task_name: String
@export var minigame_scene: PackedScene
@export var description: String
@export var point: int
@export var room: String

signal completion_changed(task_id: String, completed: bool)

var _is_completed: bool = false

var is_completed: bool:
	get:
		return _is_completed
	set(value):
		_is_completed = value
		completion_changed.emit(task_id,value)
		
