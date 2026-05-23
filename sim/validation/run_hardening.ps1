<#
.SYNOPSIS
    Phase 1.5D — Validation Hardening runner.

    1. Detects reports that are stale (mtime older than their case JSON or
       baseline JSON).
    2. Reruns only the stale cases (or all gating cases when -Force is used).
    3. Runs validate_reference_cases.py.
    4. Runs audit_validation_freshness.py.
    5. Exits 1 if any case fails, or if either Python script exits non-zero
       (which happens whenever a CRITICAL issue is detected by the audit).

.PARAMETER GodotExe
    Path to the Godot executable.  Defaults to well-known locations or the
    GODOT_EXE environment variable.

.PARAMETER ProjectPath
    Root of the SimuFire repository.  Defaults to two levels above this script.

.PARAMETER PythonExe
    Python interpreter to use.  Defaults to "python".

.PARAMETER TimeoutSeconds
    Per-case Godot timeout.  Defaults to 300 s.

.PARAMETER Force
    When set, rerun ALL gating cases (those that have a baseline file),
    regardless of staleness.

.EXAMPLE
    cd sim\validation
    powershell -ExecutionPolicy Bypass -File run_hardening.ps1

.EXAMPLE
    # Rerun everything unconditionally:
    powershell -ExecutionPolicy Bypass -File run_hardening.ps1 -Force
#>
param(
	[string]$GodotExe       = "",
	[string]$ProjectPath    = "",
	[string]$PythonExe      = "python",
	[int]$TimeoutSeconds    = 300,
	[switch]$Force
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
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
		"F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe",
		"C:\Users\dangp\Desktop\Godot_v4.6.2-stable_win64_console.exe"
	)
	foreach ($c in $candidates) {
		if (Test-Path $c) { return (Resolve-Path $c).Path }
	}
	if ($RequestedPath) { throw "No se encontro Godot: $RequestedPath" }
	throw "No se encontro Godot. Define -GodotExe o la variable GODOT_EXE."
}

$GodotExe = Resolve-GodotExecutable $GodotExe

$runCaseScript    = Join-Path $PSScriptRoot "run_case.ps1"
$baselineDir      = Join-Path $PSScriptRoot "baselines"
$reportDir        = Join-Path $PSScriptRoot "reports"
$caseDir          = Join-Path $PSScriptRoot "cases"
$refCheckScript   = Join-Path $ProjectPath  "scripts\simulation\validate_reference_cases.py"
$freshnessScript  = Join-Path $ProjectPath  "scripts\simulation\audit_validation_freshness.py"

foreach ($required in @($runCaseScript, $baselineDir, $reportDir, $caseDir,
                         $refCheckScript, $freshnessScript)) {
	if (-not (Test-Path $required)) {
		throw "No se encontro: $required"
	}
}

# ---------------------------------------------------------------------------
# Known fragile benchmarks — specific diagnostics on stale/fail
# ---------------------------------------------------------------------------
$fragileCases = @{
	"cfast_r0_window_360"       = "Brecha estructural one-zone: hot-gas outflow de ventana no modelado. " +
	                              "Checks non-gating documentados. Override: plume_mccaffrey_enabled=false, o2_upper_plume_entr_rate=0.015."
	"cfast_multi_fuel_couch_tv" = "Reporte puede quedar stale respecto al baseline (diferencia de minutos). " +
	                              "Siempre verificar con freshness audit tras re-ejecutar."
	"g3_gie_ppv_post_knockdown" = "Check de timing 361+-3s. Requiere override: background_o2_exchange_multiplier=1.0. " +
	                              "Sin ese override el humo se despeja ~22s antes (339s FAIL)."
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
$W = 72
Write-Host ("=" * $W)
Write-Host "  Phase 1.5D -- Validation Hardening"
Write-Host ("=" * $W)
Write-Host ("[Hardening] Proyecto : {0}" -f $ProjectPath)
Write-Host ("[Hardening] Godot    : {0}" -f $GodotExe)
Write-Host ("[Hardening] Python   : {0}" -f $PythonExe)
Write-Host ("[Hardening] Timeout  : {0}s por caso" -f $TimeoutSeconds)
if ($Force) { Write-Host "[Hardening] Modo     : FORCE (todos los casos con baseline)" }
else        { Write-Host "[Hardening] Modo     : incremental (solo casos obsoletos)" }

# ---------------------------------------------------------------------------
# Step 1 — Detect stale cases
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("-" * $W)
Write-Host "  Paso 1: Deteccion de reportes obsoletos"
Write-Host ("-" * $W)

$staleCases = [System.Collections.Generic.List[string]]::new()
$baselineFiles = Get-ChildItem -Path $baselineDir -Filter "*.json" | Sort-Object BaseName

foreach ($baseline in $baselineFiles) {
	$caseName   = $baseline.BaseName
	$reportPath = Join-Path $reportDir "$caseName.json"
	$casePath   = Join-Path $caseDir   "$caseName.json"

	if ($Force) {
		$staleCases.Add($caseName) | Out-Null
		continue
	}

	# No report at all — must run
	if (-not (Test-Path $reportPath)) {
		$fragNote = if ($fragileCases.ContainsKey($caseName)) { " [FRAGILE]" } else { "" }
		Write-Host ("[Hardening]   STALE{0} (sin reporte): {1}" -f $fragNote, $caseName)
		$staleCases.Add($caseName) | Out-Null
		continue
	}

	$reportMtime   = (Get-Item $reportPath).LastWriteTime
	$reasons       = [System.Collections.Generic.List[string]]::new()

	if (Test-Path $casePath) {
		$caseMtime = (Get-Item $casePath).LastWriteTime
		if ($caseMtime -gt $reportMtime) {
			$reasons.Add(("case.json {0} > reporte {1}" -f
				$caseMtime.ToString("yyyy-MM-dd HH:mm:ss"),
				$reportMtime.ToString("yyyy-MM-dd HH:mm:ss")))
		}
	}

	$baselineMtime = $baseline.LastWriteTime
	if ($baselineMtime -gt $reportMtime) {
		$reasons.Add(("baseline.json {0} > reporte {1}" -f
			$baselineMtime.ToString("yyyy-MM-dd HH:mm:ss"),
			$reportMtime.ToString("yyyy-MM-dd HH:mm:ss")))
	}

	if ($reasons.Count -gt 0) {
		$fragNote  = if ($fragileCases.ContainsKey($caseName)) { " [FRAGILE]" } else { "" }
		$reasonStr = $reasons -join "; "
		Write-Host ("[Hardening]   STALE{0}: {1} -- {2}" -f $fragNote, $caseName, $reasonStr)
		$staleCases.Add($caseName) | Out-Null
	}
}

if ($staleCases.Count -eq 0) {
	Write-Host "[Hardening]   Todos los reportes estan frescos."
} else {
	Write-Host ("[Hardening]   Total stale: {0} caso(s)" -f $staleCases.Count)
}

# ---------------------------------------------------------------------------
# Fragile benchmark summary (always printed for awareness)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("-" * $W)
Write-Host "  Benchmarks fragiles conocidos"
Write-Host ("-" * $W)
foreach ($kv in ($fragileCases.GetEnumerator() | Sort-Object Key)) {
	$staleTag = if ($staleCases -contains $kv.Key) { "STALE  " } else { "fresco " }
	Write-Host ("[{0}] {1}" -f $staleTag, $kv.Key)
	Write-Host ("           {0}" -f $kv.Value)
}

# ---------------------------------------------------------------------------
# Step 2 — Rerun stale cases
# ---------------------------------------------------------------------------
$caseFailures = 0
$caseResults  = [System.Collections.Generic.List[string]]::new()

if ($staleCases.Count -gt 0) {
	Write-Host ""
	Write-Host ("-" * $W)
	Write-Host ("  Paso 2: Reejecutando {0} caso(s) obsoleto(s)" -f $staleCases.Count)
	Write-Host ("-" * $W)

	foreach ($caseName in $staleCases) {
		$label = if ($fragileCases.ContainsKey($caseName)) { "$caseName [FRAGILE]" } else { $caseName }
		Write-Host ("[Hardening]   -> $label")
		if ($fragileCases.ContainsKey($caseName)) {
			Write-Host ("             NOTA: {0}" -f $fragileCases[$caseName])
		}

		try {
			& $runCaseScript -CaseName $caseName `
			                 -GodotExe $GodotExe `
			                 -ProjectPath $ProjectPath `
			                 -TimeoutSeconds $TimeoutSeconds
			$ec = $LASTEXITCODE
			if ($ec -ne 0) {
				Write-Host ("[Hardening]   [FAIL] $caseName (exit $ec)")
				$caseResults.Add("FAIL  $caseName")
				$caseFailures++
			} else {
				$caseResults.Add("PASS  $caseName")
			}
		} catch {
			Write-Host ("[Hardening]   [ERROR] ${caseName}: $($_.Exception.Message)")
			$caseResults.Add("ERROR $caseName")
			$caseFailures++
		}
	}
} else {
	Write-Host ""
	Write-Host "[Hardening] Paso 2: no hay casos obsoletos, omitiendo reejecutacion."
}

# ---------------------------------------------------------------------------
# Step 3 — validate_reference_cases.py
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("-" * $W)
Write-Host "  Paso 3: validate_reference_cases.py"
Write-Host ("-" * $W)
& $PythonExe $refCheckScript
$refExitCode = $LASTEXITCODE

# ---------------------------------------------------------------------------
# Step 4 — audit_validation_freshness.py
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("-" * $W)
Write-Host "  Paso 4: audit_validation_freshness.py"
Write-Host ("-" * $W)
& $PythonExe $freshnessScript
$auditExitCode = $LASTEXITCODE

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * $W)
Write-Host "  RESUMEN Phase 1.5D"
Write-Host ("=" * $W)

if ($caseResults.Count -gt 0) {
	Write-Host "  Casos reejecutados:"
	foreach ($r in $caseResults) { Write-Host ("    {0}" -f $r) }
} else {
	Write-Host "  Casos reejecutados  : ninguno (todos frescos)"
}

$refStatus   = if ($refExitCode   -eq 0) { "OK" } else { "FAIL (exit $refExitCode)" }
$auditStatus = if ($auditExitCode -eq 0) { "OK (0 CRIT)" } else { "FAIL (exit $auditExitCode) - hay CRIT, ver salida arriba" }

Write-Host ("  Fallos en casos     : {0}" -f $caseFailures)
Write-Host ("  validate_reference  : {0}" -f $refStatus)
Write-Host ("  freshness audit     : {0}" -f $auditStatus)

$overallExit = 0
if ($caseFailures     -gt 0) { $overallExit = 1 }
if ($refExitCode      -ne 0) { $overallExit = 1 }
if ($auditExitCode    -ne 0) { $overallExit = 1 }

Write-Host ""
if ($overallExit -eq 0) {
	Write-Host "  Estado global : PASS -- suite fiable y fresca"
} else {
	Write-Host "  Estado global : FAIL -- revisar issues arriba"
}
Write-Host ("=" * $W)

exit $overallExit
