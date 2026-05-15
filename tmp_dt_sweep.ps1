# tmp_dt_sweep.ps1 — SF-AUD-019: barrido de sensibilidad numérica a dt
# Ejecuta el caso living_room_hallway con diferentes sim_fixed_dt y compara métricas.
# Uso: .\tmp_dt_sweep.ps1 -GodotExe "F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe"
# ─────────────────────────────────────────────────────────────────────────────────
param(
    [string]$GodotExe = "F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe",
    [string]$ProjectPath = $PSScriptRoot,
    [string]$BaseCaseName = "living_room_hallway",
    [int]   $TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$casesDir  = Join-Path $ProjectPath "sim\validation\cases"
$reportsDir = Join-Path $ProjectPath "sim\validation\reports"
$runScript = Join-Path $ProjectPath "sim\validation\run_case.ps1"

# dt values to sweep (seconds of simulated time per engine frame)
$dtValues = @(0.5, 1.0, 2.0, 5.0, 10.0, 20.0)

# Metrics to compare (from validation report JSON .metrics field)
$metricsToCompare = @(
    "room_0_peak_temp_upper_c",
    "room_0_peak_hrr_kw",
    "room_0_peak_co_ppm",
    "room_0_min_l150_m",
    "room_1_peak_temp_upper_c",
    "room_1_peak_co_ppm"
)

# ── Read base case JSON ────────────────────────────────────────────────────────
$baseCasePath = Join-Path $casesDir "$BaseCaseName.json"
if (-not (Test-Path $baseCasePath)) {
    throw "Base case not found: $baseCasePath"
}
$baseCase = Get-Content $baseCasePath -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "=== SF-AUD-019: Barrido de sensibilidad numerica a dt ==="
Write-Host "Caso base : $BaseCaseName"
Write-Host "dt values : $($dtValues -join ', ') s"
Write-Host ""

$results = [System.Collections.Generic.List[hashtable]]::new()

foreach ($dt in $dtValues) {
    # Build a modified case JSON: inject sim_fixed_dt in engine_overrides
    $tempCaseName = "dt_sweep_${BaseCaseName}_dt$(($dt -replace '\.', '_'))"
    $tempCasePath = Join-Path $casesDir "$tempCaseName.json"
    $tempReportPath = Join-Path $reportsDir "$tempCaseName.json"

    # Deep-copy the base case and patch engine_overrides
    $caseObj = $baseCase | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    if ($null -eq $caseObj.engine_overrides) {
        $caseObj | Add-Member -NotePropertyName "engine_overrides" -NotePropertyValue ([PSCustomObject]@{})
    }
    $caseObj.engine_overrides | Add-Member -NotePropertyName "sim_fixed_dt" -NotePropertyValue $dt -Force
    # Keep time_scale=1 so that fixed_dt is purely controlled by sim_fixed_dt
    $caseObj.engine_overrides | Add-Member -NotePropertyName "time_scale" -NotePropertyValue 1.0 -Force

    $caseObj | ConvertTo-Json -Depth 10 | Set-Content -Path $tempCasePath -Encoding UTF8

    Write-Host -NoNewline "  dt = $($dt.ToString('F1').PadLeft(5)) s  →  "

    $ok = $true
    try {
        & $runScript `
            -CaseName $tempCaseName `
            -GodotExe $GodotExe `
            -ProjectPath $ProjectPath `
            -TimeoutSeconds $TimeoutSeconds `
            -ValidationOutput $tempReportPath | Out-Null
    } catch {
        $ok = $false
        Write-Host "FALLO: $($_.Exception.Message)"
    }

    if ($ok -and (Test-Path $tempReportPath)) {
        $report = Get-Content $tempReportPath -Raw | ConvertFrom-Json
        $metrics = $report.metrics

        $row = @{ dt_s = $dt; ok = $true }
        foreach ($m in $metricsToCompare) {
            $row[$m] = if ($null -ne $metrics.$m) { [double]$metrics.$m } else { [double]::NaN }
        }
        $results.Add($row)
        Write-Host "OK  (sim_time=$([math]::Round($report.sim_time_s, 1)) s)"
    } elseif ($ok) {
        Write-Host "FALLO: reporte no generado"
        $results.Add(@{ dt_s = $dt; ok = $false })
    }

    # Clean up temp case JSON (keep report for reference)
    Remove-Item $tempCasePath -ErrorAction SilentlyContinue
}

# ── Print comparison table ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Resultados del barrido ==="

if ($results.Count -eq 0) {
    Write-Host "No se obtuvieron resultados."
    exit 1
}

# Header
$cols = @("dt_s") + $metricsToCompare
$header = ($cols | ForEach-Object { $_.PadLeft(22) }) -join "  |  "
Write-Host $header
Write-Host ("-" * ($header.Length))

# Reference = smallest dt
$refRow = $results | Where-Object { $_.ok } | Sort-Object { $_.dt_s } | Select-Object -First 1

foreach ($row in ($results | Sort-Object { $_.dt_s })) {
    if (-not $row.ok) {
        Write-Host ("$($row.dt_s.ToString('F1').PadLeft(22))  |  FALLO")
        continue
    }
    $line = $row.dt_s.ToString("F1").PadLeft(22)
    foreach ($m in $metricsToCompare) {
        $val = $row[$m]
        if ([double]::IsNaN($val)) {
            $cell = "N/A"
        } else {
            $cell = $val.ToString("F2")
            if ($null -ne $refRow -and $row.dt_s -ne $refRow.dt_s -and -not [double]::IsNaN($refRow[$m]) -and $refRow[$m] -ne 0.0) {
                $pct = ($val - $refRow[$m]) / [math]::Abs($refRow[$m]) * 100.0
                $cell += " ($($pct.ToString('+0.1;-0.1'))%)"
            }
        }
        $line += "  |  " + $cell.PadLeft(22)
    }
    Write-Host $line
}

# ── Tolerance check ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Tolerancias (variacion relativa vs dt_ref=$($refRow.dt_s) s) ==="
$warnThreshold = 5.0   # %
$failThreshold = 15.0  # %
$anyFail = $false

foreach ($row in ($results | Where-Object { $_.ok } | Sort-Object { $_.dt_s })) {
    if ($row.dt_s -eq $refRow.dt_s) { continue }
    $dtLabel = "dt=$($row.dt_s.ToString('F1'))s"
    foreach ($m in $metricsToCompare) {
        $val = $row[$m]; $ref = $refRow[$m]
        if ([double]::IsNaN($val) -or [double]::IsNaN($ref) -or $ref -eq 0.0) { continue }
        $pct = [math]::Abs(($val - $ref) / $ref * 100.0)
        if ($pct -ge $failThreshold) {
            Write-Host "  [FAIL]  $dtLabel  $m  Δ=$($pct.ToString('F1'))% (>= $failThreshold%)"
            $anyFail = $true
        } elseif ($pct -ge $warnThreshold) {
            Write-Host "  [WARN]  $dtLabel  $m  Δ=$($pct.ToString('F1'))% (>= $warnThreshold%)"
        }
    }
}
if (-not $anyFail) {
    Write-Host "  Todos los dt evaluados estan dentro de tolerancia de ${failThreshold}%."
}

Write-Host ""
Write-Host "=== Fin barrido dt ==="
