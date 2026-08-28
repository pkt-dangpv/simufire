extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")
const LogWriterScript = preload("res://sim/core/SimulationLogWriter.gd")
const Phase3CoupledPressureSolverScript = preload(
	"res://sim/core/Phase3CoupledPressureSolver.gd"
)
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")
const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")

var _failed: bool = false


func _init() -> void:
	_test_engine_runtime_gates()
	_test_energy_budget_diagnostic_path()
	_test_conservation_diagnostic_path()
	_test_exterior_boundary_diagnostic_path()
	_test_coupled_pressure_solver_path()
	_test_cfast_buoyancy_destination_path()
	if _failed:
		quit(1)
		return
	print("P1R4_MISSING_DIAGNOSTIC_ACTIVATION_PASS")
	quit(0)


func _test_engine_runtime_gates() -> void:
	var engine = EngineScript.new()
	_assert(not engine.energy_budget_enabled, "energy budget defaults OFF")
	_assert(not engine.conservation_check_enabled, "conservation defaults OFF")
	_assert(
		not engine.phase3_canonical_exterior_boundary_shadow_enabled,
		"exterior boundary defaults OFF"
	)
	_assert(
		not engine.phase3_canonical_fire_products_routing_shadow_enabled,
		"fire products routing defaults OFF"
	)
	_assert(
		not engine.phase3_coupled_pressure_solver_shadow_enabled,
		"coupled pressure solver defaults OFF"
	)
	_assert(
		not engine.phase3_cfast_buoyancy_destination_shadow_enabled,
		"CFAST buoyancy destination defaults OFF"
	)

	engine.phase3_canonical_zone_shadow_enabled = true
	engine.phase3_canonical_persistence_shadow_enabled = true
	engine.phase3_canonical_combustion_shadow_enabled = true
	engine.phase3_canonical_multisurface_shadow_enabled = true
	engine.phase3_canonical_plume_shadow_enabled = true
	engine.phase3_coupled_plume_shadow_enabled = true
	engine.phase3_canonical_fire_proposal_shadow_enabled = true
	engine.phase3_canonical_fire_products_shadow_enabled = true
	engine.phase3_canonical_fire_products_routing_shadow_enabled = true
	_assert(
		engine._phase3_canonical_fire_products_routing_active(),
		"fire products routing gate activates with all parents"
	)

	engine.phase3_canonical_interior_opening_shadow_enabled = true
	engine.phase3_coupled_pressure_solver_shadow_enabled = true
	_assert(
		engine._phase3_coupled_pressure_solver_active(),
		"coupled pressure solver gate activates with all parents"
	)
	engine.phase3_canonical_exterior_boundary_shadow_enabled = true
	engine.phase3_cfast_buoyancy_destination_shadow_enabled = true
	_assert(
		engine.phase3_canonical_exterior_boundary_shadow_enabled,
		"exterior boundary engine entrypoint activates"
	)
	_assert(
		engine.phase3_cfast_buoyancy_destination_shadow_enabled,
		"CFAST buoyancy destination engine entrypoint activates"
	)
	engine.free()


func _test_energy_budget_diagnostic_path() -> void:
	var thermal = ThermalSystemScript.new()
	thermal.configure({"energy_budget_enabled": true})
	_assert(thermal.energy_budget_enabled, "energy budget reaches ThermalSystem")
	thermal._energy_budget = {0: {"e_fire_kj": 2.0, "q_residual_kj": 0.25}}
	thermal._bud_cum_e_fire_kj = {0: 3.0}
	thermal._bud_cum_q_residual_kj = {0: 0.5}
	var budget: Dictionary = thermal.get_energy_budget()
	_assert(budget.has(0), "energy budget is observable")
	_assert_close(float(budget[0]["cum_e_fire_kj"]), 3.0, "energy cumulative output")
	_assert_close(
		float(budget[0]["cum_q_residual_kj"]), 0.5, "residual cumulative output"
	)


func _test_conservation_diagnostic_path() -> void:
	var building = BuildingModelScript.new()
	var room = _room(0)
	room.co2_kg = 1.0
	building.rooms = {0: room}
	var solver = ZoneFireSolverScript.new()
	solver.zone_solver_phase = 3
	var result: Dictionary = solver.validate_conservation(
		building,
		{
			"co2_residual_kg": 0.01,
			"hcn_residual_kg": 0.0,
			"co_residual_kg": 0.0,
			"smoke_residual_kg": 0.0,
			"call_count": 1,
		},
		1.0
	)
	_assert(bool(result.get("has_violation", false)), "conservation violation visible")
	_assert(
		float(result.get("conservation_violation_count", 0.0)) == 1.0,
		"conservation counter increments"
	)
	building.free()


func _test_exterior_boundary_diagnostic_path() -> void:
	var logger = LogWriterScript.new()
	logger.configure_phase3_canonical_exterior_boundary_shadow(true)
	_assert(
		logger.phase3_canonical_exterior_boundary_shadow_enabled,
		"exterior boundary output schema activates"
	)

	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var room = _room(0)
	room.upper_gas_kg = 20.0
	room.lower_gas_kg = 20.0
	room.upper_energy_kj = 2000.0
	room.lower_energy_kj = 0.0
	building.rooms = {0: room}
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_exterior_boundary_requests(
		building, 0.1, 20.0, 0.209, 0.005, 0.0, 0.61, false
	)
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results().get("0", {})
	_assert(
		result.has("phase3_shadow_exterior_pressure_pre_pa"),
		"exterior boundary telemetry is observable"
	)
	building.free()


func _test_coupled_pressure_solver_path() -> void:
	var logger = LogWriterScript.new()
	logger.configure_phase3_coupled_pressure_solver_shadow(true)
	_assert(
		logger.phase3_coupled_pressure_solver_shadow_enabled,
		"coupled solver output schema activates"
	)
	var solver = Phase3CoupledPressureSolverScript.new()
	var result: Dictionary = solver.solve_coupled_pressure(
		{
			"0": {
				"volume_m3": 48.0,
				"floor_area_m2": 20.0,
				"height_m": 2.4,
				"upper_gas_kg": 20.0,
				"lower_gas_kg": 36.0,
				"upper_energy_kj": 0.0,
				"lower_energy_kj": 0.0,
			}
		},
		[],
		{"0": {"mass_kg": 0.0, "energy_kj": 0.0}},
		1.0,
		20.0
	)
	_assert(bool(result.get("valid", false)), "coupled pressure solver returns a valid result")
	_assert(bool(result.get("converged", false)), "coupled pressure solver converges")


func _test_cfast_buoyancy_destination_path() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var hot: Dictionary = system.preview_cfast_buoyancy_destination_split(
		200.0, 80.0, 20.0
	)
	var cold: Dictionary = system.preview_cfast_buoyancy_destination_split(
		10.0, 80.0, 20.0
	)
	_assert_close(float(hot["upper"]) + float(hot["lower"]), 1.0, "hot split")
	_assert_close(float(cold["upper"]) + float(cold["lower"]), 1.0, "cold split")
	_assert(float(hot["upper"]) > float(cold["upper"]), "buoyancy changes destination")


func _room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	room.o2_upper = 0.209
	room.o2_lower = 0.209
	return room


func _assert(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		_failed = true


func _assert_close(
		actual: float, expected: float, label: String, tolerance: float = 1.0e-8
	) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %s got %s" % [label, str(expected), str(actual)])
		_failed = true
