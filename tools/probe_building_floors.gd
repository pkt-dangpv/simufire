extends SceneTree

## Cuantas plantas tiene cada escenario del catalogo, y a que altura queda la
## calle segun la planta en la que se arranque.
##
## Existe porque N-4 se decidio "las plantas son las dibujadas": antes de
## gastar ese dato hay que ver que devuelve en los diez escenarios, incluidos
## los que no son pisos.
##
## Uso: godot --headless --path . --script res://tools/probe_building_floors.gd

const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd")
const BuildingModelScript = preload("res://sim/BuildingModel.gd")

## Altura de planta de reserva: la que se usa cuando el edificio tiene una sola
## planta dibujada y no hay nada que medir.
const FALLBACK_FLOOR_H: float = 2.85


func _initialize() -> void:
	var builder = BuildingTemplateScript.new()
	print("escenario                 tipo          dibujadas  h_planta  P=1 aparenta/caida   P=15 aparenta/caida")
	for preset in builder.get_preset_definitions():
		var id: String = String(preset.get("id", ""))
		var linea: String = "%-25s" % id
		var tipo: String = ""
		var fila: String = ""
		for planta in [1, 15]:
			var data: Dictionary = builder.create_by_name(id)
			data["apartment_floor_number"] = planta
			var building: BuildingModel = BuildingModelScript.new()
			building.load_template_data(data)
			tipo = String(building.building_type)
			if planta == 1:
				linea += " %-13s %-10d %-9.2f" % [
					tipo,
					BuildingLevels.drawn_floor_count(building),
					BuildingLevels.floor_to_floor_m(building, FALLBACK_FLOOR_H)]
			fila += "  %2d / %5.2f m      " % [
				BuildingLevels.apparent_total_floors(building),
				BuildingLevels.street_drop_m(building, FALLBACK_FLOOR_H)]
		print(linea + fila)
	quit()
