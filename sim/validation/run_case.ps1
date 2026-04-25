param(
	[Parameter(Mandatory = $true)]
	[string]$CaseName,

	[string]$GodotExe = "C:\Users\dangp\Desktop\Godot_v4.6.2-stable_win64_console.exe",
	[string]$ProjectPath = "",
	[string]$ValidationOutput = "",
	[double]$ValidationDuration = 0,
	[int]$TimeoutSeconds = 300,
	[switch]$NoQuit
)

$ErrorActionPreference = "Stop"

if (-not $ProjectPath) {
	$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
	$ProjectPath = (Resolve-Path $ProjectPath).Path
}

if (-not (Test-Path $GodotExe)) {
	throw "No se encontro el ejecutable de Godot: $GodotExe"
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

if ($ValidationDuration -gt 0) {
	$godotArgs += "--validation-duration=$ValidationDuration"
}

if ($NoQuit) {
	$godotArgs += "--validation-no-quit"
}

Write-Host ("[Validation Runner] Caso: {0}" -f $CaseName)
Write-Host ("[Validation Runner] Proyecto: {0}" -f $ProjectPath)
Write-Host ("[Validation Runner] Log Godot: {0}" -f $logFile)
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
			throw "La validacion '$CaseName' no supera la baseline. Revisar reporte: $reportPath"
		}

		Write-Warning ("La validacion '{0}' genero reporte actualizado pero Godot salio con exit code {1}. Revisar log si hace falta: {2}" -f $CaseName, $exitCode, $logFile)
		exit 0
	}

	throw "La validacion '$CaseName' fallo con exit code $exitCode. Revisar: $logFile"
}
