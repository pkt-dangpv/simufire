extends RefCounted
class_name ObjectLibrary


static func get_object_kinds() -> Array[String]:
	return [
		"sofa",
		"armchair",
		"bed",
		"table",
		"coffee_table",
		"desk",
		"curtain",
		"wardrobe",
		"bookcase",
		"dresser",
		"tv_stand",
		"rug",
		"kitchen_unit",
		"plastic_bin"
	]


static func create_object(kind: String, id: String, room_id: int, position_m: Vector2) -> Dictionary:
	var base: Dictionary = _base_object(id, room_id, position_m)
	match kind:
		"sofa":
			base.merge({
				"name": "Sofa",
				"kind": "sofa",
				"size_m": {"x": 2.0, "y": 0.9},
				"footprint_m2": 1.8,
				"exposed_area_m2": 2.5,
				"fuel_energy_MJ": 500.0,
				"remaining_fuel_MJ": 500.0,
				"max_hrr_kw": 1000.0,
				"ignition_temp_c": 320.0,
				"ignition_flux_kw_m2": 18.0,
				"smoke_yield_kg_per_MJ": 0.012,
				"co_yield_kg_per_MJ": 0.0004
			}, true)
		"armchair":
			base.merge({
				"name": "Sillon",
				"kind": "armchair",
				"size_m": {"x": 0.85, "y": 0.85},
				"footprint_m2": 0.72,
				"exposed_area_m2": 1.4,
				"elevation_m": 0.35,
				"fuel_energy_MJ": 360.0,
				"remaining_fuel_MJ": 360.0,
				"max_hrr_kw": 650.0,
				"ignition_temp_c": 310.0,
				"ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.012,
				"co_yield_kg_per_MJ": 0.0004
			}, true)
		"bed":
			base.merge({
				"name": "Cama",
				"kind": "bed",
				"size_m": {"x": 2.0, "y": 1.4},
				"footprint_m2": 2.8,
				"exposed_area_m2": 3.5,
				"elevation_m": 0.45,
				"fuel_energy_MJ": 900.0,
				"remaining_fuel_MJ": 900.0,
				"max_hrr_kw": 1200.0,
				"ignition_temp_c": 295.0,
				"ignition_flux_kw_m2": 15.0,
				"smoke_yield_kg_per_MJ": 0.013,
				"co_yield_kg_per_MJ": 0.0004
			}, true)
		"table":
			base.merge({
				"name": "Mesa",
				"kind": "table",
				"size_m": {"x": 1.20, "y": 0.75},
				"footprint_m2": 0.90,
				"exposed_area_m2": 1.6,
				"elevation_m": 0.7,
				"fuel_energy_MJ": 180.0,
				"remaining_fuel_MJ": 180.0,
				"max_hrr_kw": 250.0,
				"ignition_temp_c": 330.0,
				"ignition_flux_kw_m2": 18.0,
				"smoke_yield_kg_per_MJ": 0.008,
				"co_yield_kg_per_MJ": 0.00025
			}, true)
		"coffee_table":
			base.merge({
				"name": "Mesa centro",
				"kind": "coffee_table",
				"size_m": {"x": 1.05, "y": 0.58},
				"footprint_m2": 0.61,
				"exposed_area_m2": 1.0,
				"elevation_m": 0.40,
				"fuel_energy_MJ": 140.0,
				"remaining_fuel_MJ": 140.0,
				"max_hrr_kw": 180.0,
				"ignition_temp_c": 330.0,
				"ignition_flux_kw_m2": 18.0,
				"smoke_yield_kg_per_MJ": 0.008,
				"co_yield_kg_per_MJ": 0.00025
			}, true)
		"desk":
			base.merge({
				"name": "Escritorio",
				"kind": "desk",
				"size_m": {"x": 1.15, "y": 0.55},
				"footprint_m2": 0.63,
				"exposed_area_m2": 1.2,
				"elevation_m": 0.72,
				"fuel_energy_MJ": 260.0,
				"remaining_fuel_MJ": 260.0,
				"max_hrr_kw": 260.0,
				"ignition_temp_c": 320.0,
				"ignition_flux_kw_m2": 17.0,
				"smoke_yield_kg_per_MJ": 0.009,
				"co_yield_kg_per_MJ": 0.00025
			}, true)
		"curtain":
			base.merge({
				"name": "Cortina",
				"kind": "curtain",
				"size_m": {"x": 1.2, "y": 0.12},
				"footprint_m2": 0.15,
				"exposed_area_m2": 2.0,
				"elevation_m": 1.4,
				"fuel_energy_MJ": 120.0,
				"remaining_fuel_MJ": 120.0,
				"max_hrr_kw": 350.0,
				"ignition_temp_c": 270.0,
				"ignition_flux_kw_m2": 12.0,
				"smoke_yield_kg_per_MJ": 0.016,
				"co_yield_kg_per_MJ": 0.0005
			}, true)
		"wardrobe":
			base.merge({
				"name": "Armario",
				"kind": "wardrobe",
				"size_m": {"x": 0.45, "y": 1.60},
				"footprint_m2": 0.72,
				"exposed_area_m2": 2.4,
				"fuel_energy_MJ": 800.0,
				"remaining_fuel_MJ": 800.0,
				"max_hrr_kw": 700.0,
				"ignition_temp_c": 300.0,
				"ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.008,
				"co_yield_kg_per_MJ": 0.00025
			}, true)
		"bookcase":
			base.merge({
				"name": "Libreria",
				"kind": "bookcase",
				"size_m": {"x": 0.40, "y": 1.35},
				"footprint_m2": 0.54,
				"exposed_area_m2": 1.8,
				"fuel_energy_MJ": 650.0,
				"remaining_fuel_MJ": 650.0,
				"max_hrr_kw": 320.0,
				"ignition_temp_c": 300.0,
				"ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.008,
				"co_yield_kg_per_MJ": 0.00025
			}, true)
		"dresser":
			base.merge({
				"name": "Comoda",
				"kind": "dresser",
				"size_m": {"x": 0.90, "y": 0.45},
				"footprint_m2": 0.41,
				"exposed_area_m2": 1.0,
				"elevation_m": 0.45,
				"fuel_energy_MJ": 420.0,
				"remaining_fuel_MJ": 420.0,
				"max_hrr_kw": 360.0,
				"ignition_temp_c": 305.0,
				"ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.009,
				"co_yield_kg_per_MJ": 0.00025
			}, true)
		"tv_stand":
			base.merge({
				"name": "Mueble TV",
				"kind": "tv_stand",
				"size_m": {"x": 1.50, "y": 0.35},
				"footprint_m2": 0.53,
				"exposed_area_m2": 1.1,
				"elevation_m": 0.35,
				"fuel_energy_MJ": 360.0,
				"remaining_fuel_MJ": 360.0,
				"max_hrr_kw": 240.0,
				"ignition_temp_c": 305.0,
				"ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.008,
				"co_yield_kg_per_MJ": 0.00025
			}, true)
		"rug":
			base.merge({
				"name": "Alfombra",
				"kind": "rug",
				"size_m": {"x": 1.80, "y": 1.05},
				"footprint_m2": 1.89,
				"exposed_area_m2": 1.89,
				"elevation_m": 0.03,
				"fuel_energy_MJ": 220.0,
				"remaining_fuel_MJ": 220.0,
				"max_hrr_kw": 150.0,
				"ignition_temp_c": 275.0,
				"ignition_flux_kw_m2": 13.0,
				"smoke_yield_kg_per_MJ": 0.015,
				"co_yield_kg_per_MJ": 0.0005
			}, true)
		"kitchen_unit":
			base.merge({
				"name": "Encimera",
				"kind": "kitchen_unit",
				"size_m": {"x": 2.0, "y": 0.6},
				"footprint_m2": 1.2,
				"exposed_area_m2": 2.4,
				"elevation_m": 0.8,
				"fuel_energy_MJ": 1000.0,
				"remaining_fuel_MJ": 1000.0,
				"max_hrr_kw": 900.0,
				"ignition_temp_c": 285.0,
				"ignition_flux_kw_m2": 14.0,
				"smoke_yield_kg_per_MJ": 0.009,
				"co_yield_kg_per_MJ": 0.00028
			}, true)
		"plastic_bin":
			base.merge({
				"name": "Cubo plastico",
				"kind": "plastic_bin",
				"size_m": {"x": 0.40, "y": 0.40},
				"footprint_m2": 0.16,
				"exposed_area_m2": 0.45,
				"elevation_m": 0.25,
				"fuel_energy_MJ": 80.0,
				"remaining_fuel_MJ": 80.0,
				"max_hrr_kw": 100.0,
				"ignition_temp_c": 350.0,
				"ignition_flux_kw_m2": 20.0,
				"smoke_yield_kg_per_MJ": 0.025,
				"co_yield_kg_per_MJ": 0.0009
			}, true)
		_:
			pass
	return base


static func _base_object(id: String, room_id: int, position_m: Vector2) -> Dictionary:
	return {
		"id": id,
		"name": "Generic combustible",
		"kind": "generic",
		"room_id": room_id,
		"position_m": {"x": position_m.x, "y": position_m.y},
		"size_m": {"x": 1.0, "y": 1.0},
		"rotation_deg": 0.0,
		"footprint_m2": 1.0,
		"exposed_area_m2": 1.0,
		"elevation_m": 0.0,
		"fuel_energy_MJ": 100.0,
		"remaining_fuel_MJ": 100.0,
		"max_hrr_kw": 300.0,
		"ignition_temp_c": 330.0,
		"ignition_flux_kw_m2": 18.0,
		"smoke_yield_kg_per_MJ": 0.00375,
		"co_yield_kg_per_MJ": 0.00025,
		"o2_consumption_kg_per_MJ": 0.076,
		"is_primary_ignition_source": false
	}
