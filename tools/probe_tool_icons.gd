extends SceneTree
## Sonda: como se ven los iconos de la barra de herramientas.
##
## Los iconos son SVG de 18 px; a ese tamaño un trazo de mas los convierte en
## una mancha. Esta sonda los pega en una hoja de contactos ampliada x6 sobre el
## fondo del editor para poder mirarlos antes de creerselos.
##
## Uso: godot --headless --path . --script res://tools/probe_tool_icons.gd -- <salida.png>

const ICON_DIR: String = "res://ui/icons"
const ZOOM: int = 6
const COLUMNS: int = 7
const CELL: int = 18


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "icons_sheet.png"

	var names: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(ICON_DIR)
	if dir == null:
		print("no se puede abrir ", ICON_DIR)
		quit(1)
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".svg"):
			names.append(file_name)
	names.sort()

	var rows: int = int(ceil(float(names.size()) / float(COLUMNS)))
	var cell_px: int = CELL * ZOOM + 8
	var sheet := Image.create(COLUMNS * cell_px, rows * cell_px, false, Image.FORMAT_RGBA8)
	# El gris del panel del editor: un icono blanco sobre blanco no dice nada.
	sheet.fill(Color(0.09, 0.11, 0.13, 1.0))

	for i in range(names.size()):
		var texture := load("%s/%s" % [ICON_DIR, names[i]]) as Texture2D
		if texture == null:
			print("no carga ", names[i])
			continue
		var image: Image = texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
		var origin := Vector2i((i % COLUMNS) * cell_px + 4, int(i / COLUMNS) * cell_px + 4)
		sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), origin)
		print("%-24s %dx%d" % [names[i], texture.get_width(), texture.get_height()])

	var error: int = sheet.save_png(out_path)
	print("hoja de contactos: %s (error=%d)" % [out_path, error])
	quit(0 if error == OK else 1)
