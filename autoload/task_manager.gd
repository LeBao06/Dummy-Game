extends Node

# Signals emitted so the UI / ServerManager can react to task events
signal task_completed(player_id: int, task_id: String)
signal total_progress_updated(current_progress: float)
signal all_tasks_completed
@warning_ignore("UNUSED_SIGNAL")
signal client_tasks_updated(task_resources: Array)


# Dictionary holding every Task Resource, keyed by ID (the file name)
var task_database: Dictionary = {} # Key: String (task_id), Value: TaskResource

# Overall task progress across all Crewmates (feeds the global progress bar).
# total_tasks_count is set by ServerManager when assign_tasks() runs,
# NOT set here, since TaskManager has no knowledge of player count/roles.
var total_tasks_count: int = 0
var completed_tasks_count: int = 0


func _ready() -> void:
	_load_all_task_resources()


# 1. AUTOMATICALLY LOAD ALL .TRES FILES IN THE RESOURCES FOLDER
func _load_all_task_resources() -> void:
	var dir_path = "res://entities/tasks/resources/"
	var dir = DirAccess.open(dir_path)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				# Remove export suffixes (.remap / .import) added in release builds
				var clean_name = file_name.replace(".remap", "").replace(".import", "")
				
				if clean_name.ends_with(".tres"):
					# Use the file name (without extension) as the task ID (e.g. "fix_wiring")
					var task_id = clean_name.get_basename()
					# Avoid re-loading the same resource twice if both .tres and .tres.remap exist
					if not task_database.has(task_id):
						var res = load(dir_path + clean_name) as TaskResource
						if res:
							task_database[task_id] = res
			file_name = dir.get_next()
		print("[TaskManager] Loaded ", task_database.size(), " task resources.")
	else:
		push_error("[TaskManager] Cannot open directory: ", dir_path)


# 2. GET DATA FOR A SINGLE TASK
func get_task_info(task_id: String) -> TaskResource:
	return task_database.get(task_id, null)
	
# 2b. GET ALL TASK IDS (fixed list, no randomization)
func get_all_task_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in task_database.keys():
		ids.append(key)
	return ids

# 3. CALLED WHEN A PLAYER COMPLETES A TASK
## NOTE: This should only ever be called from server-authoritative code
## (ServerManager) after it has validated the task belongs to the player
## and hasn't already been completed. TaskManager itself does no validation.
func complete_task(player_id: int, task_id: String) -> void:
	# Get the actual task
	var task := get_task_info(task_id)
	if task:
		task.is_completed = true
		
	completed_tasks_count += 1
	var progress = float(completed_tasks_count) / float(max(1, total_tasks_count))

	task_completed.emit(player_id, task_id)
	total_progress_updated.emit(progress)

	print("Task completed: ", task_id, " | Progress: ", progress * 100, "%")

	if total_tasks_count > 0 and completed_tasks_count >= total_tasks_count:
		all_tasks_completed.emit()


## 4. RANDOM TASKS - for now fixed tasks, no randomized
#func get_random_task_ids(amount: int = 1) -> Array[String]:
	#var all_ids = task_database.keys()
	#all_ids.shuffle() # Shuffle the ID list
#
	#var result: Array[String] = []
	#var count = min(amount, all_ids.size()) # Avoid requesting more tasks than exist
#
	#for i in range(count):
		#result.append(all_ids[i])
#
	#return result


# 5. RESET (called when leaving the game / ending a match, so stats don't
#    bleed over between matches)
func reset_manager() -> void:
	total_tasks_count = 0
	completed_tasks_count = 0
