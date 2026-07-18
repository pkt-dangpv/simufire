param(
	[string]$GodotExe = "",
	[string]$ProjectPath = "",
	[string]$PythonExe = "python",
	[int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Continue"

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
		"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe",
		"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"
	)
	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			return (Resolve-Path $candidate).Path
		}
	}
	throw "No se encontro Godot. Define -GodotExe o GODOT_EXE."
}

$GodotExe = Resolve-GodotExecutable $GodotExe
$runCaseScript = Join-Path $PSScriptRoot "run_case.ps1"

# All 18 cases needed by validate_reference_cases.py + ghanekar
$cases = @(
	"cfast_r0_window_360",
	"ghanekar_bedroom_hallway",
	"ghanekar_kitchen_living_room",
	"cfast_single_room_closed",
	"cfast_two_room_door_open",
	"cfast_post_flashover_vented",
	"cfast_hvac_residential",
	"cfast_long_burnout_3600s",
	"cfast_door_close_midfire",
	"cfast_fast_growth_closed",
	"cfast_two_floor_stairwell",
	"cfast_multi_fuel_couch_tv",
	"cfast_window_break_t180",
	"cfast_bedroom_closed_door",
	"cfast_corridor_chain",
	"cfast_slow_growth_sealed",
	"cfast_pool_fire_open",
	"cfast_suppression_water"
)

Write-Host "[Full Reference Suite] Inicio: $($cases.Count) casos"
Write-Host "[Full Reference Suite] Proyecto: $ProjectPath"
Write-Host "[Full Reference Suite] Timeout por caso: ${TimeoutSeconds}s"

$results = @()
foreach ($caseName in $cases) {
	Write-Host "[Full Reference Suite] Corriendo: $caseName"
	$start = Get-Date
	try {
		& $runCaseScript -CaseName $caseName -GodotExe $GodotExe -ProjectPath $ProjectPath -TimeoutSeconds $TimeoutSeconds -AllowBaselineFailure
		$status = "OK"
	} catch {
		$status = "ERROR: $_"
		Write-Host "[Full Reference Suite] ADVERTENCIA: $caseName -> $status"
	}
	$elapsed = [int]((Get-Date) - $start).TotalSeconds
	$results += [PSCustomObject]@{ Case = $caseName; Status = $status; Seconds = $elapsed }
	Write-Host "[Full Reference Suite] $caseName completado en ${elapsed}s ($status)"
}

Write-Host ""
Write-Host "[Full Reference Suite] === Resumen de corridas ==="
foreach ($r in $results) {
	Write-Host ("  {0}: {1} ({2}s)" -f $r.Case, $r.Status, $r.Seconds)
}

Write-Host ""
Write-Host "[Full Reference Suite] Ejecutando validate_reference_cases.py..."
& $PythonExe (Join-Path $ProjectPath "scripts\simulation\validate_reference_cases.py")

Write-Host ""
Write-Host "[Full Reference Suite] Ejecutando audit_ilv_layer_coherence_suite.py..."
& $PythonExe (Join-Path $ProjectPath "scripts\simulation\audit_ilv_layer_coherence_suite.py") -v
$ilv_exit = $LASTEXITCODE
if ($ilv_exit -ne 0) {
	Write-Host "[Full Reference Suite] ADVERTENCIA: ILV coherence audit encontró findings inesperados (exit $ilv_exit)."
} else {
	Write-Host "[Full Reference Suite] ILV coherence audit: OK"
}

Write-Host ""
Write-Host "[Full Reference Suite] Ejecutando audit_physics_coherence_suite.py..."
& $PythonExe (Join-Path $ProjectPath "scripts\simulation\audit_physics_coherence_suite.py") -v
$physics_exit = $LASTEXITCODE
if ($physics_exit -ne 0) {
	Write-Host "[Full Reference Suite] ADVERTENCIA: physics coherence audit encontró findings inesperados (exit $physics_exit)."
} else {
	Write-Host "[Full Reference Suite] Physics coherence audit: OK"
}
Write-Host "[Full Reference Suite] Completado."
