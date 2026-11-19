class_name StockDropScroll
extends ScrollContainer

signal piece_returned(piece: ShopPiece)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var piece := data.get("piece") as ShopPiece
	return piece != null and not piece.customer_owned


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	piece_returned.emit(data.piece)
