# scenes/ui/task_list/task_list.gd
extends CanvasLayer

@onready var task_label: RichTextLabel = $TaskContainer/RichTextLabel

func _ready() -> void:
	task_label.bbcode_enabled = true
	PlayerManager.players_state_updated.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var peer_id := multiplayer.get_unique_id()
	var task_ids: Array = PlayerManager.get_assigned_tasks(peer_id)
	var done_ids: Array = PlayerManager.get_done_tasks(peer_id)
	print("Refreshing task list, ids: ", task_ids)
	
	var text := ""
	for id in task_ids:
		var task_info := TaskManager.get_task_info(id)
		if not task_info:
			push_warning("[TaskList] No TaskResource found for id: " + str(id))
			continue

		var label: String = task_info.room
		if not task_info.task_name.is_empty():
			label = task_info.task_name

		if id in done_ids:
			text += "[color=green]%s ✓[/color]\n" % label
		else:
			text += "%s\n" % label

	task_label.text = text
	print("[TaskList] Set text on node: ", task_label.get_path(), " -> '", task_label.text, "'")
