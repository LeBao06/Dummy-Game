class_name Interactable # register like public class in java, this can be used anywhere in the project
extends Area2D

signal interacted(player) # Signal to listen for objects that player interacted with

@export var interaction_name: String = "Interact"
@export var enabled: bool = true

func _ready() -> void:
	add_to_group("interactables")
	
func can_interact(player) -> bool:
	return enabled
	
func interact(player) -> void:
	if can_interact(player):
		interacted.emit(player)
		
func set_highlighted(state: bool) -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite and sprite.material:
		sprite.material.set_shader_paremeter("enable",state)
