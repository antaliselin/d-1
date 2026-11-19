class_name ShopPiece
extends RefCounted

var id: String
var units: int
var customer_owned: bool
var anchor := Vector2i.ZERO
var rotation := 0
var loaded := 0
var ammo_id := ""


func _init(item_id: String, amount: int = 1, belongs_to_customer: bool = false) -> void:
	id = item_id
	units = amount
	customer_owned = belongs_to_customer
