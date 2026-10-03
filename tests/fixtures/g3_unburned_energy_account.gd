extends SceneTree

## G3-4A: cuenta energética (MJ) del pirolizado sin inventario. Ejecuta el motor
## real sobre el control `o2_closed` (sofá de 120 MJ / 600 kW en la sala 0 de
## simple_house, puerta 0-1 cerrada) y comprueba, paso a paso y con inventario
## leído antes y después:
##   - con la cuenta ON, cada MJ debitado a un objeto queda en calor fresco, saldo
##     R, alta pedida al depósito o cuenta del objeto;
##   - con la cuenta OFF (comportamiento anterior) esa identidad NO cierra;
##   - lo que sale del depósito sin arder queda en su cuenta de sala por ruta;
##   - la cuenta no cambia la física: ON y OFF dan la misma trayectoria.
## Es contabilidad, no un inventario físico: nada aquí la trata como gas.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")

const OWNERSHIP_SWITCH: String = "fire_explicit_object_fuel_ownership_enabled"
const ACCOUNT_SWITCH: String = "fire_unburned_energy_account_enabled"
const STEP_S: float = 1.0 / 12.0
const DURATION_S: float = 340.0
const SUPPRESSION_AT_S: float = 325.0
const TOL_MJ: float = 1.0e-12

var _failed: bool = false
var _failures: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var defaults = SimulationEngineScript.new()
	_check(not defaults.fire_unburned_energy_account_enabled, "the account switch defaults OFF")
	_check(not defaults.fire_explicit_object_fuel_ownership_enabled, "the ownership switch defaults OFF")
	defaults.free()

	var account_on: Dictionary = _simulate(true, true, {})
	var account_off: Dictionary = _simulate(true, false, {})
	var capped: Dictionary = _simulate(true, true, {"fire_unburned_capacity_MJ_per_m2": 0.0005})
	var not_owned: Dictionary = _simulate(false, true, {})
	if _failed:
		push_error("G3-4A: " + String(_failures[0]))
		quit(1)
		return

	# 1. Con la cuenta ON la identidad por objeto cierra en todos los pasos.
	_check(int(account_on["committed_steps"]) > 3000, "the control ran its committed steps")
	_check(int(account_on["steps_with_unburned"]) > 100, "the control has pyrolysate without inventory")
	_check(int(account_on["steps_identity_open"]) == 0, "ON: no step leaves the object identity open")
	_check(float(account_on["worst_object_residual_MJ"]) <= TOL_MJ, "ON: object identity closes")
	_check(float(account_on["object_account_MJ"]) > 0.1, "ON: the object account is not empty")
	_check(
		absf(float(account_on["object_account_MJ"]) - float(account_on["unburned_rule_MJ"])) <= 1.0e-9,
		"ON: the object account equals the pyrolysate without inventory"
	)
	# 2. Con la cuenta OFF (comportamiento anterior) la misma identidad no cierra.
	_check(float(account_off["object_account_MJ"]) == 0.0, "OFF: no account is written")
	_check(int(account_off["steps_identity_open"]) > 100, "OFF: the identity is open in many steps")
	_check(
		absf(float(account_off["open_identity_MJ"]) - float(account_on["object_account_MJ"])) <= 1.0e-9,
		"OFF: what stays open is exactly what the account holds when ON"
	)
	# 3. Depósito: lo que sale sin arder queda en su cuenta de sala, por ruta.
	_check(float(account_on["worst_pool_residual_MJ"]) <= TOL_MJ, "ON: pool identity closes")
	_check(float(account_on["pool_account_decay_MJ"]) > 0.0, "ON: decay reaches its account")
	_check(float(account_on["pool_account_suppression_MJ"]) > 0.0, "ON: suppression reaches its account")
	_check(float(account_on["pool_account_capacity_MJ"]) == 0.0, "ON: the capacity never binds in the control")
	_check(float(capped["pool_account_capacity_MJ"]) > 0.0, "capacity route reaches its account")
	_check(float(capped["worst_pool_residual_MJ"]) <= TOL_MJ, "capped: pool identity closes")
	_check(float(capped["worst_object_residual_MJ"]) <= TOL_MJ, "capped: object identity closes")
	_check(float(account_off["pool_account_total_MJ"]) == 0.0, "OFF: no pool account is written")
	_check(float(account_off["pool_lost_without_account_MJ"]) > 0.0, "OFF: the pool loses energy with no account")
	# 4. La cuenta no cambia la física: misma trayectoria con ON y con OFF.
	_check(_same_trace(account_on["trace"], account_off["trace"]), "ON and OFF give the same trajectory")
	# 5. Solo crece y solo existe en salas explicit_objects.
	_check(bool(account_on["monotonic"]), "accounts never decrease")
	_check(float(not_owned["object_account_MJ"]) == 0.0, "not owned: no object account")
	_check(float(not_owned["pool_account_total_MJ"]) == 0.0, "not owned: no pool account")
	# 6. El reinicio del escenario las pone a cero.
	_check(bool(account_on["reset_clears"]), "reset clears the accounts")

	var summary: Dictionary = {}
	for label in ["account_on", "account_off", "capped", "not_owned"]:
		var source: Dictionary = {
			"account_on": account_on, "account_off": account_off, "capped": capped, "not_owned": not_owned,
		}[label]
		var copy: Dictionary = source.duplicate()
		copy.erase("trace")
		summary[label] = copy
	summary["failures"] = _failures
	print("G3_UNBURNED_ENERGY_ACCOUNT " + JSON.stringify(summary))
	if _failed:
		for failure in _failures:
			push_error("G3-4A: " + String(failure))
		quit(1)
		return
	print("G3_UNBURNED_ENERGY_ACCOUNT_PASS")
	quit(0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		_failures.append(label)


func _same_trace(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for index in range(a.size()):
		if a[index] != b[index]:
			return false
	return true


func _sofa() -> Dictionary:
	return {
		"id": "g3_sofa", "name": "g3_sofa", "kind": "mobiliario_tapizado",
		"room_id": 0, "position_m": {"x": 0.2, "y": 1.4},
		"size_m": {"x": 2.2, "y": 0.9}, "footprint_m2": 2.0,
		"exposed_area_m2": 3.5, "elevation_m": 0.4,
		"fuel_energy_MJ": 120.0, "remaining_fuel_MJ": 120.0,
		"max_hrr_kw": 600.0, "ignition_temp_c": 310.0,
		"ignition_flux_kw_m2": 16.0, "smoke_yield_kg_per_MJ": 0.012,
		"co_yield_kg_per_MJ": 0.0004, "is_primary_ignition_source": true,
	}


func _template() -> Dictionary:
	var data: Dictionary = BuildingTemplateScript.new().create_by_name("simple_house")
	for room_data in data.get("rooms_data", []):
		if int(room_data.get("id", -1)) == 0:
			room_data["fuel_energy_MJ"] = 0.0
			room_data["max_hrr_kw"] = 0.0
			room_data["fuel_objects"] = [_sofa()]
	for opening_data in data.get("openings_data", []):
		if int(opening_data.get("a", -1)) == 0 and int(opening_data.get("b", -1)) == 1 \
				and String(opening_data.get("type", "")) == "door":
			opening_data["open_fraction"] = 0.0
	return data


func _simulate(ownership_on: bool, account_on: bool, extra: Dictionary) -> Dictionary:
	var building = BuildingModelScript.new()
	root.add_child(building)
	if not building.load_template_data(_template()):
		_check(false, "template cannot be loaded")
		return {}
	var engine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	root.add_child(engine)
	var overrides: Dictionary = {
		"fire_spread_enabled": false, "glass_auto_break_enabled": false,
		"fire_alpha_kw_s2": 0.04, "fire_o2_min_for_flame": 0.10,
		"fire_secondary_hrr_gain_kw": 0.0, "fire_latent_o2_viable_margin": 0.008,
		"fire_extinction_delay_s": 240.0, "fire_latent_extinction_delay_s": 300.0,
		OWNERSHIP_SWITCH: ownership_on, ACCOUNT_SWITCH: account_on,
	}
	for key in extra.keys():
		overrides[key] = extra[key]
	for key in overrides.keys():
		engine.set(String(key), overrides[key])
	engine.ignition_room_id = 0
	engine.reset_simulation(0, true)
	engine.sim_duration_limit_s = 0.0
	engine.combustion_system.g3_fuel_ledger_enabled = true

	var room = building.get_room(0)
	var sofa = null
	for obj in room.fuel_objects:
		if String(obj.id) == "g3_sofa":
			sofa = obj
	var result: Dictionary = {
		"committed_steps": 0, "steps_with_unburned": 0, "steps_identity_open": 0,
		"worst_object_residual_MJ": 0.0, "worst_pool_residual_MJ": 0.0,
		"open_identity_MJ": 0.0, "unburned_rule_MJ": 0.0, "pool_lost_without_account_MJ": 0.0,
		"monotonic": true, "suppression_applied": false,
	}
	var trace: Array = []
	var previous_object_account: float = 0.0
	var previous_pool_account: float = 0.0
	while engine.sim_time_s < DURATION_S:
		if not bool(result["suppression_applied"]) and engine.sim_time_s >= SUPPRESSION_AT_S:
			engine.apply_suppression(0, 2.0, 60.0, 0.5)
			result["suppression_applied"] = true
		engine.step(STEP_S / maxf(0.001, engine.time_scale))
		for row in engine.combustion_system.g3_drain_fuel_ledger(building):
			if int(row["room_id"]) == 0:
				_check_row(row, result)
		trace.append([
			sofa.remaining_fuel_MJ, sofa.g3_r_balance_MJ, room.hrr_kw, room.retained_unburned_MJ,
			room.o2, room.o2_upper, room.o2_lower, room.co_kg, room.co2_kg, room.smoke_kg,
			room.temp_upper_c,
		])
		var pool_account: float = room.g3_pool_account_capacity_MJ + room.g3_pool_account_decay_MJ \
				+ room.g3_pool_account_suppression_MJ + room.g3_pool_account_burnout_MJ
		if sofa.g3_unburned_energy_account_MJ < previous_object_account or pool_account < previous_pool_account:
			result["monotonic"] = false
		previous_object_account = sofa.g3_unburned_energy_account_MJ
		previous_pool_account = pool_account

	result["object_account_MJ"] = float(sofa.g3_unburned_energy_account_MJ)
	result["pool_account_capacity_MJ"] = float(room.g3_pool_account_capacity_MJ)
	result["pool_account_decay_MJ"] = float(room.g3_pool_account_decay_MJ)
	result["pool_account_suppression_MJ"] = float(room.g3_pool_account_suppression_MJ)
	result["pool_account_burnout_MJ"] = float(room.g3_pool_account_burnout_MJ)
	result["pool_account_total_MJ"] = previous_pool_account
	result["pool_end_MJ"] = float(room.retained_unburned_MJ)
	result["fuel_debited_MJ"] = float(sofa.fuel_energy_MJ - sofa.remaining_fuel_MJ)
	result["r_balance_MJ"] = float(sofa.g3_r_balance_MJ)
	result["sim_time_s"] = float(engine.sim_time_s)
	result["trace"] = trace
	engine.reset_simulation(0, false)
	result["reset_clears"] = sofa.g3_unburned_energy_account_MJ == 0.0 \
			and room.g3_pool_account_capacity_MJ == 0.0 and room.g3_pool_account_decay_MJ == 0.0 \
			and room.g3_pool_account_suppression_MJ == 0.0 and room.g3_pool_account_burnout_MJ == 0.0
	root.remove_child(engine)
	engine.free()
	root.remove_child(building)
	building.free()
	return result


## Una fila del libro por paso: identidad por objeto y por depósito, siempre con
## el inventario leído antes y después (no con el número que calculó la regla).
func _check_row(row: Dictionary, result: Dictionary) -> void:
	var account: Dictionary = row.get("bal_account", {})
	var pool: Dictionary = row.get("bal_pool", {})
	if not pool.is_empty():
		var lost: float = float(pool["before_MJ"]) + float(pool["credit_requested_MJ"]) \
				- float(pool["after_credit_MJ"])
		lost += float(pool["after_burn_MJ"]) - float(pool["after_decay_MJ"])
		var suppression: Dictionary = row.get("bal_suppression", {})
		if not suppression.is_empty():
			lost += float(suppression["pool_before_MJ"]) - float(suppression["pool_after_MJ"])
		var extinction: Dictionary = row.get("bal_extinction", {})
		if not extinction.is_empty() and bool(extinction["burned_out"]):
			lost += float(extinction["pool_before_MJ"])
		if not account.is_empty() and bool(account["room_owned"]):
			var written: float = 0.0
			for key in ["capacity_MJ", "decay_MJ", "suppression_MJ", "burnout_MJ"]:
				written += float(account["pool_after"][key]) - float(account["pool_before"][key])
			result["worst_pool_residual_MJ"] = maxf(
				float(result["worst_pool_residual_MJ"]), absf(lost - written)
			)
		else:
			# Sin cuenta (OFF, o sala que no es explicit_objects) esa energía no queda en nada.
			result["pool_lost_without_account_MJ"] = float(result["pool_lost_without_account_MJ"]) + lost
	var species: Dictionary = row.get("bal_species", {})
	if not row.has("optd") or bool(row.get("optd_uncommitted", false)) \
			or not bool(species.get("committed", false)):
		return
	result["committed_steps"] = int(result["committed_steps"]) + 1
	var debit: float = 0.0
	var account_change: float = 0.0
	for entry in row["objects"]:
		if bool(entry["is_proxy"]):
			continue
		debit += float(entry["remaining_before_MJ"]) - float(entry["remaining_after_MJ"])
		if entry.has("unburned_account_before_MJ"):
			account_change += float(entry["unburned_account_after_MJ"]) \
					- float(entry["unburned_account_before_MJ"])
	var fresh_heat: float = 0.0
	var accrued: float = 0.0
	for key in row["optd"]["objects"].keys():
		fresh_heat += float(row["optd"]["objects"][key]["B0_MJ"])
		accrued += float(row["optd"]["objects"][key]["acc_MJ"])
	var fuel: Dictionary = row["bal_fuel"]
	var to_pool: float = float(fuel["pool_generation_MJ"])
	var rule: float = float(fuel["unburned_without_inventory_MJ"])
	result["unburned_rule_MJ"] = float(result["unburned_rule_MJ"]) + rule
	if rule > TOL_MJ:
		result["steps_with_unburned"] = int(result["steps_with_unburned"]) + 1
	var residual: float = debit - fresh_heat - accrued - to_pool - account_change
	if absf(residual) > 1.0e-9:
		result["steps_identity_open"] = int(result["steps_identity_open"]) + 1
		result["open_identity_MJ"] = float(result["open_identity_MJ"]) + residual
	else:
		result["worst_object_residual_MJ"] = maxf(float(result["worst_object_residual_MJ"]), absf(residual))
