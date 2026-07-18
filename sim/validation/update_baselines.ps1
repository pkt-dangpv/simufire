param(
	[string]$GodotExe = "C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe",
	[string]$ProjectPath = "",
	[int]$TimeoutSeconds = 300,
	[string[]]$Cases = @()
)

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force 2>$null

if (-not $ProjectPath) {
	$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
	$ProjectPath = (Resolve-Path $ProjectPath).Path
}

$allCases = @(
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
	"g4_gie_delayed_entry_hazard"
)

if ($Cases.Count -gt 0) {
	$targetCases = $Cases
} else {
	$targetCases = $allCases
}

$runCaseScript = Join-Path $PSScriptRoot "run_case.ps1"

Write-Host "[UpdateBaselines] Iniciando regeneracion de baselines"
Write-Host ("[UpdateBaselines] Casos: {0}" -f ($targetCases -join ", "))

foreach ($caseName in $targetCases) {
	$baselinePath = Join-Path $ProjectPath "sim\validation\baselines\$caseName.json"
	$reportPath   = Join-Path $ProjectPath "sim\validation\reports\$caseName.json"

	if (-not (Test-Path $baselinePath)) {
		Write-Host "[UpdateBaselines] SKIP $caseName — sin baseline existente"
		continue
	}

	# 1. Correr el caso para obtener el report con los valores actuales
	Write-Host "[UpdateBaselines] Corriendo: $caseName"
	& $runCaseScript `
		-CaseName $caseName `
		-GodotExe $GodotExe `
		-ProjectPath $ProjectPath `
		-TimeoutSeconds $TimeoutSeconds

	if (-not (Test-Path $reportPath)) {
		Write-Host "[UpdateBaselines] ERROR: no se genero report para $caseName"
		continue
	}

	# 2. Leer el report (valores actuales) y el baseline (tolerancias)
	$report   = Get-Content $reportPath   -Raw | ConvertFrom-Json
	$baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json

	# 3. Para cada metrica en el baseline, actualizar el expected con el actual del report
	$updated = $false
	foreach ($metric in $baseline.metrics.PSObject.Properties) {
		$key = $metric.Name
		if ($report.baseline.checks.PSObject.Properties.Name -contains $key) {
			$actual = $report.baseline.checks.$key.actual
			$oldExpected = $baseline.metrics.$key.expected
			$baseline.metrics.$key.expected = [math]::Round($actual, 6)
			Write-Host ("  {0}: {1} -> {2}" -f $key, $oldExpected, $baseline.metrics.$key.expected)
			$updated = $true
		} else {
			Write-Host ("  {0}: no encontrado en report, se mantiene" -f $key)
		}
	}

	if ($updated) {
		$baseline | ConvertTo-Json -Depth 10 | Set-Content $baselinePath -Encoding UTF8
		Write-Host "[UpdateBaselines] Baseline actualizado: $baselinePath"
	}

	Write-Host ""
}

Write-Host "[UpdateBaselines] Completado."
