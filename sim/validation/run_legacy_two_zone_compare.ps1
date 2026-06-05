param(
	[ValidateSet("freeze", "compare", "all")]
	[string]$Action = "compare",
	[ValidateSet("legacy", "two-zone")]
	[string]$CandidateMode = "two-zone",
	[string]$GodotExe = "",
	[string]$ProjectPath = "",
	[string]$FireO2Mode = "",
	[switch]$TwoZoneOpeningFlow,
	[switch]$CanonicalPressure,
	[int]$TimeoutSeconds = 900,
	[switch]$AllowContractFailure
)

$ErrorActionPreference = "Stop"

if (-not $ProjectPath) {
	$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
	$ProjectPath = (Resolve-Path $ProjectPath).Path
}

$manifestPath = Join-Path $PSScriptRoot "legacy_two_zone_manifest.json"
$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
$caseNames = @($manifest.cases.PSObject.Properties.Name)
$runCase = Join-Path $PSScriptRoot "run_case.ps1"
$compareScript = Join-Path $ProjectPath "scripts\simulation\legacy_two_zone_compare.py"
$modeReportsRoot = Join-Path $PSScriptRoot "reports\mode_comparison"
$referencePath = Join-Path $PSScriptRoot "baselines\contracts\legacy_two_zone_reference.json"
$comparisonPath = Join-Path $PSScriptRoot "reports\contracts\legacy_two_zone_comparison.json"

if ($FireO2Mode -and $FireO2Mode -notin @("legacy", "upper", "lower", "interface")) {
	throw "FireO2Mode no soportado '$FireO2Mode'. Usa legacy, upper, lower o interface."
}

function Invoke-ModeCases([string]$Mode, [bool]$AllowBaselineFailure) {
	$modeLabel = $Mode
	if ($TwoZoneOpeningFlow -and $Mode -eq "two-zone") {
		$modeLabel = "$Mode-opening-flow"
	}
	if ($CanonicalPressure -and $Mode -eq "two-zone") {
		$modeLabel = "$modeLabel-canonical-pressure"
	}
	$outputDir = Join-Path $modeReportsRoot $modeLabel
	New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
	foreach ($caseName in $caseNames) {
		$outputPath = Join-Path $outputDir ("{0}.json" -f $caseName)
		& $runCase `
			-CaseName $caseName `
			-GodotExe $GodotExe `
			-ProjectPath $ProjectPath `
			-ValidationOutput $outputPath `
			-EngineMode $Mode `
			-FireO2Mode $FireO2Mode `
			-TwoZoneOpeningFlow:$TwoZoneOpeningFlow `
			-CanonicalPressure:$CanonicalPressure `
			-AllowBaselineFailure:$AllowBaselineFailure `
			-TimeoutSeconds $TimeoutSeconds
	}
	return $outputDir
}

if ($Action -eq "freeze" -or $Action -eq "all") {
	$legacyDir = Invoke-ModeCases "legacy" $false
	python $compareScript --manifest $manifestPath freeze --reports-dir $legacyDir --output $referencePath
	if ($LASTEXITCODE -ne 0) {
		throw "No se pudo congelar la referencia legacy"
	}
}

if ($Action -eq "compare" -or $Action -eq "all") {
	if (-not (Test-Path $referencePath)) {
		throw "Referencia legacy ausente. Ejecuta primero -Action freeze."
	}
	$candidateDir = Invoke-ModeCases $CandidateMode $true
	python $compareScript `
		--manifest $manifestPath `
		--reference $referencePath `
		compare `
		--candidate-dir $candidateDir `
		--expected-mode $CandidateMode `
		--output $comparisonPath
	if ($LASTEXITCODE -ne 0) {
		if ($AllowContractFailure) {
			Write-Warning "La comparacion conserva desviaciones del candidato; revisar el reporte de contrato."
			exit 0
		}
		throw "La comparacion legacy/$CandidateMode no supera el contrato"
	}
}
