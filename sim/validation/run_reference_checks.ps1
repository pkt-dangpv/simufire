param(
	[string]$GodotExe = "",
	[string]$ProjectPath = "",
	[string]$PythonExe = "python",
	[int]$TimeoutSeconds = 300,
	[switch]$SkipCaseRuns
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
		"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe",
		"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"
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

$referenceCheckScript = Join-Path $ProjectPath "scripts\simulation\validate_reference_cases.py"
if (-not (Test-Path $referenceCheckScript)) {
	throw "No se encontro el comparador de referencias: $referenceCheckScript"
}

$cases = @(& $PythonExe $referenceCheckScript --list-runtime-cases)
if ($LASTEXITCODE -ne 0 -or $cases.Count -eq 0) {
	throw "No se pudo obtener el corpus runtime del comparador de referencias."
}
$cases = @($cases | ForEach-Object { $_.Trim() } | Where-Object { $_ })

Write-Host "[Reference Suite] Inicio de validacion contra referencias externas"
Write-Host ("[Reference Suite] Proyecto: {0}" -f $ProjectPath)
Write-Host ("[Reference Suite] Timeout por caso: {0}s" -f $TimeoutSeconds)

if (-not $SkipCaseRuns) {
	foreach ($caseName in $cases) {
		& $runCaseScript -CaseName $caseName -GodotExe $GodotExe -ProjectPath $ProjectPath -TimeoutSeconds $TimeoutSeconds -AllowBaselineFailure
	}
} else {
	Write-Host "[Reference Suite] Omitiendo ejecucion; el comparador exigira el corpus completo existente"
}

Write-Host "[Reference Suite] Comparando salidas con NIST CFAST y Ghanekar"
& $PythonExe $referenceCheckScript
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
	throw "El comparador de referencias fallo con exit code $exitCode"
}

Write-Host "[Reference Suite] Resultado final: PASS"
