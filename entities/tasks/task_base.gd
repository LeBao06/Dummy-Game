# entities/tasks/task_base.gd
class_name TaskBase
extends Control

## Emitted when the player finishes the mini-game successfully.
signal task_completed(task_id: String)
## Emitted when the player closes/cancels without finishing.
signal task_cancelled(task_id: String)

var _task_id: String = ""
var _task_info: TaskResource

var task_id: String:
	get:
		return _task_id
	set(value):
		_task_id = value
		_task_info = TaskManager.get_task_info(value)  # auto-fetch on assignment
		_on_setup()

var task_info: TaskResource:
	get:
		return _task_info
	set(value):
		_task_info = value
		_on_setup()

## Override in child scripts (Swipe Card, Fix Wiring, etc.) to populate
## labels, reset mini-game state, etc. Base does nothing.
func _on_setup() -> void:
	pass

## Call this from child scripts when the player successfully finishes.
func complete() -> void:
	task_completed.emit(_task_id)
	_report_to_server()
	queue_free()

## Call this from child scripts when the player backs out / closes the popup.
func cancel() -> void:
	task_cancelled.emit(_task_id)
	queue_free()

func _report_to_server() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		ServerManager.validate_and_complete_task(multiplayer.get_unique_id(), _task_id)
	else:
		ServerManager.rpc_id(1, "validate_and_complete_task", multiplayer.get_unique_id(), _task_id)
