param(
    [string]$GodotExe = "C:\Users\dangp\Desktop\Godot_v4.6.3-stable_win64_console.exe",
    [string]$ProjectPath = "",
    [int]$TimeoutSeconds = 300,
    [string[]]$Cases = @()
)
$ErrorActionPreference = "Stop"
if (-not $ProjectPath) {
    $ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $ProjectPath = (Resolve-Path $ProjectPath).Path
}
$allCases = @("living_room_hallway","layer150_tenability","postfire_decay","ul_exterior_water_knockdown","confinement_open_close","v1_backdraft_accumulation","v2_sealed_room_o2_depletion","v3_hallway_fed_exposure","v4_co_remote_rooms","v5_ventilation_hrr_spike","v6_spread_to_hallway","v7_underventilated_co_peak","v8_suppression_reburn","g1_gie_confinement_attack","g2_gie_transitional_attack","g3_gie_ppv_post_knockdown","g4_gie_delayed_entry_hazard")
if ($Cases.Count -gt 0) { $targetCases = $Cases } else { $targetCases = $allCases }
$runCaseScript = Join-Path $PSScriptRoot "run_case.ps1"
Write-Host "[UpdateBaselines] Iniciando regeneracion de baselines"
foreach ($caseName in $targetCases) {
    $baselinePath = Join-Path $ProjectPath "sim\validation\baselines\$caseName.json"
    $reportPath   = Join-Path $ProjectPath "sim\validation\reports\$caseName.json"
    if (-not (Test-Path $baselinePath)) { Write-Host "SKIP $caseName"; continue }
    Write-Host "[UpdateBaselines] Corriendo: $caseName"
    try {
        & $runCaseScript -CaseName $caseName -GodotExe $GodotExe -ProjectPath $ProjectPath -TimeoutSeconds $TimeoutSeconds
    } catch {
        Write-Host "  (baseline no paso, actualizando de todas formas)"
    }
    if (-not (Test-Path $reportPath)) { Write-Host "ERROR: sin report para $caseName"; continue }
    $report   = Get-Content $reportPath   -Raw | ConvertFrom-Json
    $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
    foreach ($metric in $baseline.metrics.PSObject.Properties) {
        $key = $metric.Name
        $metricObj = $metric.Value
        # Solo actualizar si el metrico tiene campo expected
        if ($metricObj.PSObject.Properties.Name -notcontains "expected") { continue }
        if ($report.baseline.checks.PSObject.Properties.Name -notcontains $key) { continue }
        $actual = $report.baseline.checks.$key.actual
        $old = $metricObj.expected
        $metricObj.expected = [math]::Round($actual, 6)
        Write-Host ("  {0}: {1} -> {2}" -f $key, $old, $metricObj.expected)
    }
    $baseline | ConvertTo-Json -Depth 10 | Set-Content $baselinePath -Encoding UTF8
    Write-Host "[UpdateBaselines] OK: $caseName"
}
Write-Host "[UpdateBaselines] Completado."
