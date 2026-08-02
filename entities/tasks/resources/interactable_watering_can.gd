extends Area2D

var can_interact = false

func _input(event):
	# "ui_accept" thường là phím Enter hoặc Space
	if can_interact and event.is_action_pressed("ui_accept"):
		print("Đã tương tác với bình tưới nước! Bắt đầu nhiệm vụ Tưới cây.")
		# Sau này logic hiện thanh progress bar hoặc UI mini-game sẽ code ở đây

func _on_body_entered(body):
	# Kiểm tra xem có đúng là nhân vật đi vào vùng cảm biến không
	if body.name == "Player":
		can_interact = true
		print("Đứng gần bình tưới! Nhấn Space/Enter để tương tác.")

func _on_body_exited(body):
	if body.name == "Player":
		can_interact = false
		print("Đã đi ra xa khỏi bình tưới.")
