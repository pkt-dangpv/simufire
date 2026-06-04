param(
	[string]$GodotExe = "",
	[string]$ProjectPath = "",
	[int]$TimeoutSeconds = 600,
	[switch]$ContinueOnFailure
)

$ErrorActionPreference = "Stop"

if (-not $ProjectPath) {
	$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
	$ProjectPath = (Resolve-Path $ProjectPath).Path
}

function Resolve-GodotExecutable([string]$RequestedPath) {
	if ($RequestedPath -and (Test-Path $RequestedPath)) {
		return (Resolve-Path $RequestedPath).Path
	}

	if ($env:GODOT_EXE -and (Test-Path $env:GODOT_EXE)) {
		return (Resolve-Path $env:GODOT_EXE).Path
	}

	$candidates = @(
		"F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe",
		"C:\Users\dangp\Desktop\Godot_v4.6.3-stable_win64_console.exe"
	)

	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			return (Resolve-Path $candidate).Path
		}
	}

	if ($RequestedPath) {
		throw "No se encontro el ejecutable de Godot: $RequestedPath"
	}
	throw "No se encontro el ejecutable de Godot. Define -GodotExe o la variable GODOT_EXE."
}

$GodotExe = Resolve-GodotExecutable $GodotExe

$runCaseScript = Join-Path $PSScriptRoot "run_case.ps1"
if (-not (Test-Path $runCaseScript)) {
	throw "No se encontro el runner individual: $runCaseScript"
}

$cases = @(
	"living_room_hallway",
	"layer150_tenability",
	"postfire_decay",
	"ul_exterior_water_knockdown",
	"confinement_open_close",
	"v1_backdraft_accumulation",
	"v2_sealed_room_o2_depletion",
	"v3_hallway_fed_exposure",
	"v4_co_remote_rooms",
	"v5_ventilation_hrr_spike",
	"v6_spread_to_hallway",
	"v7_underventilated_co_peak",
	"v8_suppression_reburn",
	"g1_gie_confinement_attack",
	"g2_gie_transitional_attack",
	"g3_gie_ppv_post_knockdown",
	"g4_gie_delayed_entry_hazard",
	# SF-AUD-022: flashover criterion
	"flashover_simple_house",
	# SF-AUD-023: glass break window spike
	"glass_break_window_spike",
	# SF-AUD-024: FEC irritants – PU foam sofa
	"pu_sofa_fec_incapacitation",
	# SF-AUD-024: FEC irritants – PVC HCl release
	"pvc_curtain_hcl_release",
	# SF-AUD-021: template coverage
	"compact_apartment_smoke",
	"uk_bungalow_smoke",
	"piso_mediterraneo_smoke",
	"two_bed_apartment_smoke",
	"three_bed_apartment_smoke",
	"row_house_ground_floor_smoke",
	"ranch_family_house_smoke",
	# SF-AUD-028: energy budget diagnostic
	"energy_budget_living_room",
	# SF-AUD-038: Babrauskas pool fire (grease kitchen)
	"kitchen_grease_pool_fire",
	# SF-AUD-029: TargetModel radiation flux
	"ranch_radiation_target_ignition",
	# SF-AUD-035: CO oxidation in hot upper layer
	"co_oxidation_post_flashover",
	# SF-AUD-033: HRR tabulated curve per-object
	"hrr_tabulated_curve_sofa",
	# SF-AUD-034: char layer insulation + LOI extinction
	"char_layer_loi_wood",
	# SF-AUD-036: PPV mechanical ventilation + smoke purge
	"ppv_attack_pressurized",
	# SF-AUD-030: 1D wall PDE Crank-Nicolson 5 nodos
	"mediterraneo_concrete_wall_conduction",
	# SF-AUD-037: efecto viento Cp fachada + spread acelerado
	"wind_assisted_exterior_spread",
	# SF-AUD-039: TC array sondas alturas ISO 9705
	"tc_array_iso9705",
	# SF-AUD-032: balance elemental de carbono C/H/O/N (clamp conservación)
	"c_balance_high_phi",
	# SF-R-2026-05-18: pirolisis Tewarson + ignicion secundaria por propagacion termica
	"secondary_ignition_demo",
	"two_storey_smoke",
	# SF-R7: stack effect vertical multi-planta (chimenea escalera)
	"cfast_two_floor_stairwell",
	# B-01: sobrepresion termodynamica en sala sellada (gap HVAC-1)
	"cfast_overpressure_sealed",
	# B-02: estratificacion CO2 capa superior vs inferior (gap HVAC-2)
	"cfast_co2_stratification",
	# B-03: agotamiento O2 capa superior pasillo via puerta (gap HVAC-3)
	"cfast_hall_upper_o2_doorway",
	# B-04: plateau HRR por ventilacion limitada — fuego t2-fast sin O2 suficiente (gap HVAC-4)
	"cfast_hrr_ventilation_limited_f2",
	# B-05: acumulacion FED letal CO+hipoxia en sala sellada (gap HVAC-5)
	"cfast_fed_hypoxia_sealed",
	# SF-R6 Phase 3: conservación de transporte de contaminantes (residual ~0)
	"conservation_transport",
	# SF-VIC-001: acumulación FED individual de víctima (compute_fed_delta_for_height)
	"victim_fed_incapacitation"
)

$results = New-Object System.Collections.Generic.List[object]
$suiteStart = Get-Date

Write-Host "[Validation Suite] Inicio de bateria completa"
Write-Host ("[Validation Suite] Proyecto: {0}" -f $ProjectPath)
Write-Host ("[Validation Suite] Casos: {0}" -f ($cases -join ", "))
Write-Host ("[Validation Suite] Timeout por caso: {0}s" -f $TimeoutSeconds)

foreach ($caseName in $cases) {
	$caseStart = Get-Date

	try {
		& $runCaseScript -CaseName $caseName -GodotExe $GodotExe -ProjectPath $ProjectPath -TimeoutSeconds $TimeoutSeconds

		$duration = (Get-Date) - $caseStart
		$results.Add([pscustomobject]@{
			CaseName = $caseName
			Status = "PASS"
			DurationSeconds = [math]::Round($duration.TotalSeconds, 2)
			Message = ""
		})
	} catch {
		$duration = (Get-Date) - $caseStart
		$message = $_.Exception.Message

		$results.Add([pscustomobject]@{
			CaseName = $caseName
			Status = "FAIL"
			DurationSeconds = [math]::Round($duration.TotalSeconds, 2)
			Message = $message
		})

		if (-not $ContinueOnFailure) {
			break
		}
	}
}

$suiteDuration = (Get-Date) - $suiteStart

Write-Host ""
Write-Host "[Validation Suite] Resumen"

foreach ($result in $results) {
	$line = " - {0}: {1} ({2}s)" -f $result.CaseName, $result.Status, $result.DurationSeconds
	if ($result.Message) {
		$line = "{0} | {1}" -f $line, $result.Message
	}
	Write-Host $line
}

$allPassed = $results.Count -eq $cases.Count -and ($results | Where-Object { $_.Status -ne "PASS" }).Count -eq 0

Write-Host ("[Validation Suite] Duracion total: {0}s" -f [math]::Round($suiteDuration.TotalSeconds, 2))
Write-Host ("[Validation Suite] Resultado final: {0}" -f ($(if ($allPassed) { "PASS" } else { "FAIL" })))

if (-not $allPassed) {
	exit 1
}
