param(
	[Parameter(Mandatory = $true)]
	[string]$CaseName,

	[string]$GodotExe = "C:\Users\dangp\Desktop\Godot_v4.6.2-stable_win64_console.exe",
	[string]$ProjectPath = "",
	[string]$ValidationOutput = "",
	[double]$ValidationDuration = 0,
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

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$logFile = Join-Path $logDir ("{0}-{1}-{2}.log" -f $CaseName, $timestamp, [guid]::NewGuid().ToString("N"))

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

& $GodotExe @godotArgs
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
	throw "La validacion '$CaseName' fallo con exit code $exitCode. Revisar: $logFile"
}
