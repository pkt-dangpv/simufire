param(
	[string]$RepoRoot = "F:\OneDrive\Documentos\GitHub\simufire",
	[string]$GodotExe = "F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe",
	[double]$DurationS = 300.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$casesDir = Join-Path $RepoRoot "sim\validation\cases"
$reportsDir = Join-Path $RepoRoot "sim\validation\reports\sweeps"
$summaryJsonPath = Join-Path $reportsDir "ghanekar_sweep_summary_2026-04-20.json"
$summaryMdPath = Join-Path $RepoRoot "sim\validation\SWEEP_GHANEKAR_BEDROOM_2026-04-20.md"

New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

function New-BaseCase {
	return [ordered]@{
		template = "ghanekar_bedroom_hallway"
		duration_s = 420.0
		ignite_on_start = $true
		ignition_room_id = 0
		enable_logging = $false
		watch_room_ids = @(0, 1, 2, 3, 4, 5, 6, 7)
		smoke_trigger_room_id = 0
		spread_target_room_id = 2
		l150_room_id = 0
		threshold_metrics = @(
			[ordered]@{
				metric_name = "time_room_0_temp_0_9m_above_600c_s"
				room_id = 0
				field = "temp_at_0_9m_c"
				op = ">="
				value = 600.0
			},
			[ordered]@{
				metric_name = "time_room_2_o2_below_20_4pct_s"
				room_id = 2
				field = "o2"
				op = "<="
				value = 0.204
			},
			[ordered]@{
				metric_name = "time_room_2_co_above_200ppm_s"
				room_id = 2
				field = "co_ppm"
				op = ">="
				value = 200.0
			},
			[ordered]@{
				metric_name = "time_room_2_co_above_1200ppm_s"
				room_id = 2
				field = "co_ppm"
				op = ">="
				value = 1200.0
			}
		)
		engine_overrides = [ordered]@{
			time_scale = 5.0
			fire_spread_enabled = $false
			glass_auto_break_enabled = $false
		}
	}
}

function Get-MetricValue {
	param(
		[Parameter(Mandatory = $true)] $Metrics,
		[Parameter(Mandatory = $true)][string]$Name
	)

	if ($null -eq $Metrics) {
		return $null
	}

	$property = $Metrics.PSObject.Properties[$Name]
	if ($null -eq $property) {
		return $null
	}

	return [double]$property.Value
}

function Get-Score {
	param(
		[double]$FlashoverS,
		[double]$O2S,
		[double]$Co200S,
		[double]$Co1200S,
		[double]$SmokeS
	)

	$flashPenalty = if ([double]::IsNaN($FlashoverS)) { 220.0 } else { [math]::Abs($FlashoverS - 186.0) }
	$o2Penalty = if ([double]::IsNaN($O2S)) { 180.0 } else { [math]::Abs($O2S - 198.0) }
	$co200Penalty = if ([double]::IsNaN($Co200S)) { 180.0 } else { [math]::Abs($Co200S - 204.0) }
	$co1200Penalty = if ([double]::IsNaN($Co1200S)) { 180.0 } else { [math]::Abs($Co1200S - 216.0) }
	$smokePenalty = if ([double]::IsNaN($SmokeS)) { 120.0 } else { [math]::Abs($SmokeS - 198.0) }

	return [math]::Round(($flashPenalty * 1.5) + $o2Penalty + $co200Penalty + $co1200Penalty + ($smokePenalty * 0.5), 2)
}

$variants = @(
	[pscustomobject]@{
		Name = "baseline"
		Description = "Caso base empirico actual"
		Engine = [ordered]@{}
	},
	[pscustomobject]@{
		Name = "transport_soft"
		Description = "Menos intercambio interior y algo mas de renovacion exterior"
		Engine = [ordered]@{
			doorway_o2_exchange_coeff = 1.20
			doorway_o2_background_exchange_kg_s_m2 = 0.045
			base_spill_kg_s_per_m2 = 0.38
			temp_push_factor = 0.0065
			ach_infiltration = 0.90
		}
	},
	[pscustomobject]@{
		Name = "transport_soft_plus"
		Description = "Transporte aun mas amortiguado con mas aire exterior"
		Engine = [ordered]@{
			doorway_o2_exchange_coeff = 1.00
			doorway_o2_background_exchange_kg_s_m2 = 0.035
			base_spill_kg_s_per_m2 = 0.30
			temp_push_factor = 0.0050
			ach_infiltration = 1.10
		}
	},
	[pscustomobject]@{
		Name = "thermal_fire_room"
		Description = "Mas acople termico hacia capa baja en el compartimento de fuego"
		Engine = [ordered]@{
			upper_to_lower_loss_rate = 0.040
			upper_to_ambient_loss_rate = 0.0060
			wall_absorption_rate = 0.0020
			thermal_gradient_band_fraction = 0.55
			thermal_gradient_max_band_m = 0.95
			floor_cooling_band_fraction = 0.10
			floor_cooling_band_max_m = 0.18
		}
	},
	[pscustomobject]@{
		Name = "combo_balanced"
		Description = "Retrasa transporte y calienta mas la zona baja del cuarto de fuego"
		Engine = [ordered]@{
			doorway_o2_exchange_coeff = 1.20
			doorway_o2_background_exchange_kg_s_m2 = 0.045
			base_spill_kg_s_per_m2 = 0.38
			temp_push_factor = 0.0065
			ach_infiltration = 0.90
			upper_to_lower_loss_rate = 0.038
			upper_to_ambient_loss_rate = 0.0065
			wall_absorption_rate = 0.0025
			thermal_gradient_band_fraction = 0.50
			thermal_gradient_max_band_m = 0.90
			floor_cooling_band_fraction = 0.12
			floor_cooling_band_max_m = 0.20
		}
	},
	[pscustomobject]@{
		Name = "combo_aggressive"
		Description = "Variante agresiva para acercar tanto transporte como flashover"
		Engine = [ordered]@{
			doorway_o2_exchange_coeff = 1.00
			doorway_o2_background_exchange_kg_s_m2 = 0.035
			base_spill_kg_s_per_m2 = 0.30
			temp_push_factor = 0.0050
			ach_infiltration = 1.10
			upper_to_lower_loss_rate = 0.045
			upper_to_ambient_loss_rate = 0.0055
			wall_absorption_rate = 0.0018
			thermal_gradient_band_fraction = 0.60
			thermal_gradient_max_band_m = 1.10
			floor_cooling_band_fraction = 0.08
			floor_cooling_band_max_m = 0.16
			thermal_feedback_coeff = 0.18
			fire_alpha_kw_s2 = 0.14
		}
	}
)

$results = @()
$tempCasePaths = @()

foreach ($variant in $variants) {
	$caseName = "_sweep_ghanekar_$($variant.Name)"
	$casePath = Join-Path $casesDir "$caseName.json"
	$reportPath = Join-Path $reportsDir "$caseName.json"
	$tempCasePaths += $casePath

	$caseData = New-BaseCase
	foreach ($key in $variant.Engine.Keys) {
		$caseData.engine_overrides[$key] = $variant.Engine[$key]
	}

	$caseJson = $caseData | ConvertTo-Json -Depth 12
	Set-Content -LiteralPath $casePath -Value $caseJson -Encoding UTF8

	Write-Host ("[Sweep] Running {0}" -f $variant.Name)
	& $GodotExe --headless --path $RepoRoot -- --validation-case $caseName --validation-output ("res://sim/validation/reports/sweeps/{0}.json" -f $caseName) --validation-duration $DurationS | Out-Host
	if ($LASTEXITCODE -ne 0) {
		throw "Godot devolvio codigo $LASTEXITCODE en $caseName"
	}

	if (-not (Test-Path -LiteralPath $reportPath)) {
		throw "No se genero reporte para $caseName"
	}

	$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
	$metrics = $report.metrics

	$flashoverS = Get-MetricValue -Metrics $metrics -Name "time_room_0_temp_0_9m_above_600c_s"
	$o2S = Get-MetricValue -Metrics $metrics -Name "time_room_2_o2_below_20_4pct_s"
	$co200S = Get-MetricValue -Metrics $metrics -Name "time_room_2_co_above_200ppm_s"
	$co1200S = Get-MetricValue -Metrics $metrics -Name "time_room_2_co_above_1200ppm_s"
	$smokeS = Get-MetricValue -Metrics $metrics -Name "time_room_2_smoke_start_s"
	$score = Get-Score `
		-FlashoverS $(if ($null -eq $flashoverS) { [double]::NaN } else { $flashoverS }) `
		-O2S $(if ($null -eq $o2S) { [double]::NaN } else { $o2S }) `
		-Co200S $(if ($null -eq $co200S) { [double]::NaN } else { $co200S }) `
		-Co1200S $(if ($null -eq $co1200S) { [double]::NaN } else { $co1200S }) `
		-SmokeS $(if ($null -eq $smokeS) { [double]::NaN } else { $smokeS })

	$result = [ordered]@{
		name = $variant.Name
		description = $variant.Description
		score = $score
		report = $reportPath
		metrics = [ordered]@{
			time_room_0_temp_0_9m_above_600c_s = $flashoverS
			time_room_2_o2_below_20_4pct_s = $o2S
			time_room_2_co_above_200ppm_s = $co200S
			time_room_2_co_above_1200ppm_s = $co1200S
			time_room_2_smoke_start_s = $smokeS
			room_0_peak_hrr_kw = Get-MetricValue -Metrics $metrics -Name "room_0_peak_hrr_kw"
			room_0_final_temp_at_0_9m_c = Get-MetricValue -Metrics $metrics -Name "room_0_final_temp_at_0_9m_c"
			room_2_peak_temp_upper_c = Get-MetricValue -Metrics $metrics -Name "room_2_peak_temp_upper_c"
			room_2_peak_co_ppm = Get-MetricValue -Metrics $metrics -Name "room_2_peak_co_ppm"
		}
		engine_overrides = [pscustomobject]$variant.Engine
	}
	$results += [pscustomobject]$result
}

foreach ($tempCasePath in $tempCasePaths) {
	if (Test-Path -LiteralPath $tempCasePath) {
		Remove-Item -LiteralPath $tempCasePath -Force
	}
}

$sorted = $results | Sort-Object score

$summary = [ordered]@{
	generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
	duration_s = $DurationS
	targets = [ordered]@{
		flashover_s = 186.0
		o2_hallway_s = 198.0
		co_hallway_s = 204.0
		idlh_proxy_co1200_s = 216.0
	}
	results = $sorted
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryJsonPath -Encoding UTF8

$lines = @()
$lines += "# Sweep Ghanekar Bedroom - 2026-04-20"
$lines += ""
$lines += 'Duracion por corrida: `300 s`'
$lines += ""
$lines += "Objetivos empiricos:"
$lines += '- `flashover @ 0.9 m ~= 186 s`'
$lines += '- `DeltaO2 hallway ~= 198 s`'
$lines += '- `DeltaCO hallway ~= 204 s`'
$lines += '- `IDLH proxy (CO > 1200 ppm) ~= 216 s`'
$lines += ""
$lines += "## Ranking"
$lines += ""
$lines += "| Variante | Score | Flashover 0.9 m | O2 hallway | CO hallway | CO>1200 | Smoke hallway |"
$lines += "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"

foreach ($item in $sorted) {
	$metrics = $item.metrics
	$flashCell = if ($null -eq $metrics.time_room_0_temp_0_9m_above_600c_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_0_temp_0_9m_above_600c_s, 2) }
	$o2Cell = if ($null -eq $metrics.time_room_2_o2_below_20_4pct_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_2_o2_below_20_4pct_s, 2) }
	$co200Cell = if ($null -eq $metrics.time_room_2_co_above_200ppm_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_2_co_above_200ppm_s, 2) }
	$co1200Cell = if ($null -eq $metrics.time_room_2_co_above_1200ppm_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_2_co_above_1200ppm_s, 2) }
	$smokeCell = if ($null -eq $metrics.time_room_2_smoke_start_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_2_smoke_start_s, 2) }
	$lines += "| $($item.name) | $([math]::Round([double]$item.score, 2)) | $flashCell | $o2Cell | $co200Cell | $co1200Cell | $smokeCell |"
}

$best = $sorted | Select-Object -First 1
$lines += ""
$lines += "## Mejor variante provisional"
$lines += ""
$lines += ('- `nombre`: {0}' -f $best.name)
$lines += ('- `score`: {0}' -f [math]::Round([double]$best.score, 2))
$lines += ('- `descripcion`: {0}' -f $best.description)
$lines += ""
$lines += "Parametros modificados:"
if (@($best.engine_overrides.PSObject.Properties).Count -eq 0) {
	$lines += "- sin cambios sobre el caso base"
}
else {
	foreach ($property in $best.engine_overrides.PSObject.Properties) {
		$lines += ('- `{0} = {1}`' -f $property.Name, $property.Value)
	}
}

$lines += ""
$lines += "Observacion tecnica:"
$lines += '- Nota historica: este barrido fue concebido para la primera pasada de calibracion. Si `lower_layer_warming_rate` cambia de estado o se conecta en el codigo, conviene repetir el barrido porque la comparacion deja de ser estrictamente equivalente.'

Set-Content -LiteralPath $summaryMdPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8

Write-Host ""
Write-Host "[Sweep] Summary written to $summaryMdPath"
Write-Host "[Sweep] JSON written to $summaryJsonPath"
