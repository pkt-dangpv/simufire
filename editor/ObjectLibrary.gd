extends RefCounted
class_name ObjectLibrary


static func get_object_kinds() -> Array[String]:
	return ["sofa", "bed", "table", "curtain", "wardrobe", "kitchen_unit"]


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
		"bed":
			base.merge({
				"name": "Bed",
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
				"name": "Table",
				"kind": "table",
				"size_m": {"x": 1.4, "y": 0.8},
				"footprint_m2": 1.12,
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
		"curtain":
			base.merge({
				"name": "Curtain",
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
				"name": "Wardrobe",
				"kind": "wardrobe",
				"size_m": {"x": 1.2, "y": 0.6},
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
		"kitchen_unit":
			base.merge({
				"name": "KitchenUnit",
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
