extends RefCounted
class_name CombustionRegimeClassifier

# ============================================================
# COMBUSTION REGIME CLASSIFIER — Fase 1 diagnóstico (read-only)
# ------------------------------------------------------------
# Lee el estado ya calculado de RoomModel y devuelve un string
# de régimen. No escribe ningún campo de física, no altera HRR,
# O₂, gases ni temperaturas.
#
# Orden de prioridad estricto: el primer match gana.
# Umbrales como const — calibrables sin tocar lógica.
#
# Referencia: docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md
# ============================================================

# ── Umbrales de clasificación ────────────────────────────────

# BACKDRAFT_RISK
const BD_O2_MAX: float = 0.13
const BD_TEMP_MIN_C: float = 180.0
const BD_VOL_FRAC_LFL: float = 0.02
const BD_VOL_FRAC_UFL: float = 0.20

# FULLY_DEVELOPED
const FD_HRR_FRACTION: float = 0.85
const FD_TEMP_MIN_C: float = 500.0

# VENTILATION_INDUCED_GROWTH
const VIG_VENT_FACTOR_MIN: float = 0.50
const VIG_RETAINED_MIN_MJ: float = 0.5

# VENTILATION_CONTROLLED_BURNING
const VCB_O2_FACTOR_MAX: float = 0.40

# VENTILATION_STRESSED
const VS_O2_FACTOR_MAX: float = 0.75

# ── API pública ──────────────────────────────────────────────

static func classify(room: RoomModel) -> String:
	if room == null or room.fire == null:
		return "EXTINGUISHED"

	# 1. BACKDRAFT_EVENT
	if room.backdraft_active:
		return "BACKDRAFT_EVENT"

	# 2. BACKDRAFT_RISK — mezcla inflamable, O₂ bajo, temperatura alta
	if room.unburned_gas_vol_frac >= BD_VOL_FRAC_LFL \
			and room.unburned_gas_vol_frac <= BD_VOL_FRAC_UFL \
			and room.o2 <= BD_O2_MAX \
			and room.temp_upper_c >= BD_TEMP_MIN_C:
		return "BACKDRAFT_RISK"

	# 3. FULLY_DEVELOPED — HRR cerca del máximo, temperatura alta
	var max_hrr_kw: float = maxf(1.0, room.fire.max_hrr_kw)
	if room.hrr_kw >= max_hrr_kw * FD_HRR_FRACTION \
			and room.temp_upper_c >= FD_TEMP_MIN_C:
		return "FULLY_DEVELOPED"

	# 4. VENTILATION_INDUCED_GROWTH — respuesta ventilación activa con reserva
	if room.ventilation_response_factor >= VIG_VENT_FACTOR_MIN \
			and room.retained_unburned_MJ >= VIG_RETAINED_MIN_MJ:
		return "VENTILATION_INDUCED_GROWTH"

	# 5. ILV_LATENT — latencia viable sin requerir HRR mínimo (Fase 2: fire_latent_active)
	if room.fire_latent_active:
		return "ILV_LATENT"

	# 6. VENTILATION_CONTROLLED_BURNING — HRR limitado por O₂, llama presente
	if room.o2_hrr_factor < VCB_O2_FACTOR_MAX and room.hrr_kw > 0.0:
		return "VENTILATION_CONTROLLED_BURNING"

	# 7. VENTILATION_STRESSED — O₂ moderadamente reducido
	if room.o2_hrr_factor < VS_O2_FACTOR_MAX and room.hrr_kw > 0.0:
		return "VENTILATION_STRESSED"

	# 8. FUEL_CONTROLLED — default cuando hay fuego activo bien ventilado
	if room.hrr_kw > 0.0 or room.fire_time_s > 0.0:
		return "FUEL_CONTROLLED"

	return "EXTINGUISHED"
