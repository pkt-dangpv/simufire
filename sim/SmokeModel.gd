extends Resource
class_name SmokeModel

## ============================================================
## SmokeModel
## ------------------------------------------------------------
## Modelo simplificado de humo para una sala.
##
## Responsabilidades:
## - generar humo a partir del HRR
## - actualizar la altura de capa
## - ofrecer funciones auxiliares reutilizables
##
## No decide la física global del incendio. Solo trabaja sobre
## una RoomModel concreta.
## ============================================================


# ============================================================
# PARÁMETROS
# ============================================================

## Producción simplificada de humo: kg/s por kW
@export var smoke_yield_kg_per_kw_s: float = 0.0001

## Densidad efectiva del humo para convertir masa -> volumen
@export var smoke_density_kg_m3: float = 0.60

## Altura mínima de capa desde el suelo
@export var min_layer_height_m: float = 0.20


# ============================================================
# API PRINCIPAL
# ============================================================

## Genera humo a partir del HRR actual de la sala.
func generate_fire_smoke(room: RoomModel, hrr_kw: float, delta: float) -> void:
	if room == null:
		return

	var smoke_generated_kg: float = maxf(hrr_kw, 0.0) * smoke_yield_kg_per_kw_s * maxf(delta, 0.0)
	room.add_upper_smoke(smoke_generated_kg)


## Recalcula la altura de capa a partir de la masa de humo.
func update_layer_height(room: RoomModel) -> void:
	if room == null:
		return

	var smoke_volume_m3: float = room.smoke_mass_kg / maxf(0.05, smoke_density_kg_m3)
	var floor_area_m2: float = room.get_floor_area_m2()

	if floor_area_m2 <= 0.01:
		floor_area_m2 = maxf(room.get_volume_m3() / maxf(0.1, room.height_m), 0.01)

	var upper_height_target_m: float = smoke_volume_m3 / maxf(0.01, floor_area_m2)
	var target_layer_m: float = clampf(room.height_m - upper_height_target_m, min_layer_height_m, room.height_m)

	room.h_layer_m = target_layer_m
	room.clamp_state()


## Paso completo del modelo de humo para una sala.
func step_room_smoke(room: RoomModel, hrr_kw: float, delta: float) -> void:
	generate_fire_smoke(room, hrr_kw, delta)
	update_layer_height(room)


# ============================================================
# UTILIDADES
# ============================================================

func estimate_smoke_volume_m3(room: RoomModel) -> float:
	if room == null:
		return 0.0

	return room.smoke_mass_kg / maxf(0.05, smoke_density_kg_m3)