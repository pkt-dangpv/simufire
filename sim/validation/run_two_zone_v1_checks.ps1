param(
	[string]$GodotExe = "",
	[string]$ProjectPath = "",
	[string]$PythonExe = "python",
	[int]$TimeoutSeconds = 900,
	[switch]$SkipUnitTests,
	[switch]$SkipRuntimeCompare,
	[switch]$SkipGuardrails
)

$ErrorActionPreference = "Stop"

if (-not $ProjectPath) {
	$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
	$ProjectPath = (Resolve-Path $ProjectPath).Path
}

$unitModules = @(
	"tests.test_two_zone_energy_core",
	"tests.test_two_zone_opening_flow",
	"tests.test_fire_o2_mode",
	"tests.test_legacy_two_zone_compare"
)

$compareScript = Join-Path $PSScriptRoot "run_legacy_two_zone_compare.ps1"
$manifestPath = Join-Path $PSScriptRoot "legacy_two_zone_manifest.json"
$candidateDir = Join-Path $PSScriptRoot "reports\mode_comparison\two-zone-opening-flow-canonical-pressure"
$comparisonPath = Join-Path $PSScriptRoot "reports\contracts\legacy_two_zone_comparison.json"
$stableComparisonPath = Join-Path $PSScriptRoot "reports\contracts\legacy_two_zone_comparison_two_zone_v1_pass.json"
$guardrailsScript = Join-Path $ProjectPath "scripts\simulation\validation_guardrails.py"
$freshAfter = $null

function Get-JsonPropertyValue($Object, [string]$Name) {
	$property = $Object.PSObject.Properties[$Name]
	if (-not $property) {
		return $null
	}
	return $property.Value
}

function Assert-ReportFlag($Report, [string]$CaseName, [string]$FlagName) {
	$value = Get-JsonPropertyValue $Report.metrics $FlagName
	if ($null -eq $value) {
		throw "Falta metrica '$FlagName' en reporte candidato two-zone: $CaseName"
	}
	if ([Math]::Abs([double]$value - 1.0) -gt 1e-9) {
		throw "Flag '$FlagName' no esta activo en $CaseName (valor=$value)"
	}
}

function Assert-ReportFreshness([string]$Path, [string]$Label) {
	if ($null -eq $script:freshAfter) {
		return
	}

	$item = Get-Item -LiteralPath $Path
	if ($item.LastWriteTime -lt $script:freshAfter.AddSeconds(-2)) {
		throw "Reporte TwoZoneV1 obsoleto para ${Label}: $Path"
	}
}

function Get-ManifestCaseNames {
	if (-not (Test-Path $manifestPath)) {
		throw "No se encontro manifest two-zone: $manifestPath"
	}

	$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
	return @($manifest.cases.PSObject.Properties.Name)
}

function Assert-ExactCaseSet($ActualNames, $ExpectedNames, [string]$Label) {
	$actual = @($ActualNames | Sort-Object)
	$expected = @($ExpectedNames | Sort-Object)
	$missing = @($expected | Where-Object { $actual -notcontains $_ })
	$extra = @($actual | Where-Object { $expected -notcontains $_ })
	if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
		throw "Inventario de casos TwoZoneV1 invalido para ${Label}. Faltan=[$($missing -join ', ')] Extras=[$($extra -join ', ')]"
	}
}

function Assert-TwoZoneCandidateReports {
	if (-not (Test-Path $candidateDir)) {
		throw "No se encontro directorio de candidatos two-zone: $candidateDir"
	}

	$caseNames = @(Get-ManifestCaseNames)
	$reportNames = @(Get-ChildItem -LiteralPath $candidateDir -Filter "*.json" -File | ForEach-Object { $_.BaseName })
	Assert-ExactCaseSet $reportNames $caseNames "reportes candidato"
	foreach ($caseName in $caseNames) {
		$reportPath = Join-Path $candidateDir ("{0}.json" -f $caseName)
		if (-not (Test-Path $reportPath)) {
			throw "Falta reporte candidato two-zone: $reportPath"
		}
		Assert-ReportFreshness $reportPath "candidato $caseName"

		$report = Get-Content -Raw $reportPath | ConvertFrom-Json
		if ($report.engine_mode -ne "two-zone") {
			throw "engine_mode inesperado en ${caseName}: $($report.engine_mode)"
		}
		if ($report.two_zone_v1_profile -ne $true) {
			throw "two_zone_v1_profile no esta activo en $caseName"
		}

		Assert-ReportFlag $report $caseName "two_zone_solver_enabled"
		Assert-ReportFlag $report $caseName "two_zone_opening_flow_enabled"
		Assert-ReportFlag $report $caseName "phase3_pressure_canonical_enabled"

		$residual = Get-JsonPropertyValue $report.metrics "peak_global_carbon_transport_residual_kg_abs"
		if ($null -eq $residual) {
			throw "Falta residual de carbono two-zone en $caseName"
		}
		if ([double]$residual -gt 0.02) {
			throw "Residual de carbono two-zone excesivo en ${caseName}: $residual kg"
		}
	}

	Write-Host ("[TwoZoneV1] Auditoria de reportes candidato: {0}/{0} PASS" -f $caseNames.Count)
}

function Assert-TwoZoneComparisonReport {
	if (-not (Test-Path $comparisonPath)) {
		throw "Falta reporte de contrato TwoZoneV1: $comparisonPath"
	}
	Assert-ReportFreshness $comparisonPath "contrato"

	$comparison = Get-Content -Raw $comparisonPath | ConvertFrom-Json
	$caseNames = @(Get-ManifestCaseNames)
	$comparisonCaseNames = @($comparison.cases.PSObject.Properties.Name)
	Assert-ExactCaseSet $comparisonCaseNames $caseNames "contrato"
	if ($comparison.candidate_mode -ne "two-zone") {
		throw "candidate_mode inesperado en contrato TwoZoneV1: $($comparison.candidate_mode)"
	}
	if ($comparison.all_required_pass -ne $true) {
		throw "El contrato TwoZoneV1 no tiene all_required_pass=true"
	}
	if ([int]$comparison.required_count -ne 18) {
		throw "required_count inesperado en contrato TwoZoneV1: $($comparison.required_count)"
	}
	if ([int]$comparison.failed_required_count -ne 0) {
		throw "failed_required_count inesperado en contrato TwoZoneV1: $($comparison.failed_required_count)"
	}
	if (@($comparison.contract_errors).Count -ne 0) {
		throw "El contrato TwoZoneV1 contiene contract_errors"
	}

	Write-Host (
		"[TwoZoneV1] Auditoria de contrato: 18/18 required PASS, {0}/18 non-gating fuera de tolerancia" -f
		$comparison.failed_non_gating_count
	)
}

Write-Host "========================================================================"
Write-Host "  TwoZoneV1 Checks -- SimuFire"
Write-Host "========================================================================"
Write-Host ("  Proyecto          : {0}" -f $ProjectPath)
Write-Host ("  Timeout runtime   : {0}s" -f $TimeoutSeconds)

if (-not $SkipUnitTests) {
	Write-Host "[TwoZoneV1] Unitarios especificos"
	& $PythonExe -m unittest @unitModules -v
	if ($LASTEXITCODE -ne 0) {
		throw "Fallan los unitarios especificos two-zone"
	}
} else {
	Write-Host "[TwoZoneV1] Unitarios omitidos"
}

if (-not $SkipRuntimeCompare) {
	Write-Host "[TwoZoneV1] Contrato runtime legacy/two-zone"
	$script:freshAfter = Get-Date
	& $compareScript `
		-Action compare `
		-CandidateMode two-zone `
		-TwoZoneV1 `
		-GodotExe $GodotExe `
		-ProjectPath $ProjectPath `
		-TimeoutSeconds $TimeoutSeconds
	if ($LASTEXITCODE -ne 0) {
		throw "Falla el contrato runtime TwoZoneV1"
	}
} else {
	Write-Host "[TwoZoneV1] Contrato runtime omitido"
}

Assert-TwoZoneComparisonReport
Assert-TwoZoneCandidateReports

if (-not $SkipRuntimeCompare -and (Test-Path $comparisonPath)) {
	Copy-Item -LiteralPath $comparisonPath -Destination $stableComparisonPath -Force
}

if (-not $SkipGuardrails) {
	Write-Host "[TwoZoneV1] Guardrails globales"
	& $PythonExe $guardrailsScript
	if ($LASTEXITCODE -ne 0) {
		throw "Fallan los guardrails globales"
	}
} else {
	Write-Host "[TwoZoneV1] Guardrails omitidos"
}

Write-Host "------------------------------------------------------------------------"
Write-Host "  TWOZONEV1 CHECKS PASS"
Write-Host "========================================================================"
