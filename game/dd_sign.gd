extends Node3D
## A roadside sign: a post and a board, the course's name on its face. One-sided Label3D facing
## +Z, back toward a driver coming up the road (the family's rule for every sign on a road:
## a double-sided label reads backwards from behind). No `class_name`: this game is delivered
## as a pack.

const BOARD := Vector2(8.0, 2.6)
const POST_HEIGHT := 4.6


## Draws the sign: [param text] on a board in [param tint], the post tall enough to read over a
## truck's bonnet. Origin is the post's foot.
func build(text: String, tint: Color) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.3, 0.32, 0.34)
	steel.roughness = 0.7

	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_box := BoxMesh.new()
		post_box.size = Vector3(0.25, POST_HEIGHT, 0.25)
		post.mesh = post_box
		post.material_override = steel
		post.position = Vector3(side * (BOARD.x * 0.5 - 0.6), POST_HEIGHT * 0.5, 0.0)
		add_child(post)

	var board := MeshInstance3D.new()
	var board_box := BoxMesh.new()
	board_box.size = Vector3(BOARD.x, BOARD.y, 0.2)
	board.mesh = board_box
	var paint := StandardMaterial3D.new()
	paint.albedo_color = tint.darkened(0.55)
	paint.roughness = 0.6
	board.material_override = paint
	board.position = Vector3(0.0, POST_HEIGHT - BOARD.y * 0.5 + 0.4, 0.0)
	add_child(board)

	var words := Label3D.new()
	words.name = "Label"
	words.text = text
	words.font_size = 72
	words.pixel_size = 0.0105
	words.double_sided = false
	words.modulate = Color(1.0, 0.97, 0.85)
	words.outline_size = 0
	words.position = board.position + Vector3(0.0, 0.0, 0.11)
	add_child(words)
