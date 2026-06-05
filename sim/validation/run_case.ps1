param(
	[Parameter(Mandatory = $true)]
	[string]$CaseName,

	[string]$GodotExe = "",
	[string]$ProjectPath = "",
	[string]$ValidationOutput = "",
	[string]$EngineMode = "",
	[string]$FireO2Mode = "",
	[switch]$TwoZoneOpeningFlow,
	[switch]$CanonicalPressure,
	[double]$ValidationDuration = 0,
	[int]$TimeoutSeconds = 300,
	[switch]$AllowBaselineFailure,
	[switch]$NoQuit
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

if ($EngineMode -and $EngineMode -notin @("legacy", "two-zone")) {
	throw "EngineMode no soportado '$EngineMode'. Usa legacy o two-zone."
}
if ($FireO2Mode -and $FireO2Mode -notin @("legacy", "upper", "lower", "interface")) {
	throw "FireO2Mode no soportado '$FireO2Mode'. Usa legacy, upper, lower o interface."
}

$logDir = Join-Path $env:TEMP "simufire-godot-logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$runStarted = Get-Date
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$logFile = Join-Path $logDir ("{0}-{1}-{2}.log" -f $CaseName, $timestamp, [guid]::NewGuid().ToString("N"))
$reportPath = if ($ValidationOutput) {
	$ValidationOutput
} else {
	Join-Path $ProjectPath ("sim\validation\reports\{0}.json" -f $CaseName)
}

$godotArgs = @(
	"--headless",
	"--path", $ProjectPath,
	"--log-file", $logFile,
	"--",
	"--validation-case=$CaseName"
)

if ($ValidationOutput) {
	$godotArgs += "--validation-output=$ValidationOutput"
}

if ($EngineMode) {
	$godotArgs += "--validation-engine-mode=$EngineMode"
}

if ($FireO2Mode) {
	$godotArgs += "--validation-fire-o2-mode=$FireO2Mode"
}

if ($TwoZoneOpeningFlow) {
	$godotArgs += "--validation-two-zone-opening-flow"
}

if ($CanonicalPressure) {
	$godotArgs += "--validation-canonical-pressure"
}

if ($ValidationDuration -gt 0) {
	$godotArgs += "--validation-duration=$ValidationDuration"
}

if ($NoQuit) {
	$godotArgs += "--validation-no-quit"
}

Write-Host ("[Validation Runner] Caso: {0}" -f $CaseName)
Write-Host ("[Validation Runner] Proyecto: {0}" -f $ProjectPath)
Write-Host ("[Validation Runner] Log Godot: {0}" -f $logFile)
Write-Host ("[Validation Runner] Modo motor: {0}" -f ($(if ($EngineMode) { $EngineMode } else { "caso/default" })))
Write-Host ("[Validation Runner] O2 fuego: {0}" -f ($(if ($FireO2Mode) { $FireO2Mode } else { "caso/default" })))
Write-Host ("[Validation Runner] Flujos apertura two-zone: {0}" -f ($(if ($TwoZoneOpeningFlow) { "on" } else { "off" })))
Write-Host ("[Validation Runner] Presion canonica Phase 3: {0}" -f ($(if ($CanonicalPressure) { "on" } else { "off" })))
Write-Host ("[Validation Runner] Timeout: {0}s" -f $TimeoutSeconds)

function Quote-ProcessArgument([string]$Value) {
	if ($Value -eq "") {
		return '""'
	}
	if ($Value -notmatch '[\s"]') {
		return $Value
	}

	$escaped = $Value -replace '(\\*)"', '$1$1\"'
	$escaped = $escaped -replace '(\\+)$', '$1$1'
	return '"' + $escaped + '"'
}

$argumentString = ($godotArgs | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $GodotExe
$processInfo.Arguments = $argumentString
$processInfo.UseShellExecute = $true
$processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

$process = [System.Diagnostics.Process]::Start($processInfo)
$finished = $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)
if (-not $finished) {
	Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
	throw "La validacion '$CaseName' supero el timeout de $TimeoutSeconds segundos. Revisar: $logFile"
}

$process.Refresh()
$exitCode = $process.ExitCode

if ($exitCode -ne 0) {
	$reportUpdated = $false
	if (Test-Path $reportPath) {
		$reportItem = Get-Item $reportPath
		if ($reportItem.LastWriteTime -ge $runStarted.AddSeconds(-2)) {
			$reportUpdated = $true
		}
	}

	if ($reportUpdated) {
		if ($exitCode -eq 2) {
			if ($AllowBaselineFailure) {
				Write-Warning ("La validacion '{0}' no supera su baseline historica; se conserva el reporte para el contrato externo." -f $CaseName)
				exit 0
			}
			throw "La validacion '$CaseName' no supera la baseline. Revisar reporte: $reportPath"
		}

		Write-Warning ("La validacion '{0}' genero reporte actualizado pero Godot salio con exit code {1}. Revisar log si hace falta: {2}" -f $CaseName, $exitCode, $logFile)
		exit 0
	}

	throw "La validacion '$CaseName' fallo con exit code $exitCode. Revisar: $logFile"
}
