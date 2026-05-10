param(
	[string]$GodotExe = "C:\Users\dangp\Desktop\Godot_v4.6.2-stable_win64_console.exe",
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
	"g4_gie_delayed_entry_hazard"
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
