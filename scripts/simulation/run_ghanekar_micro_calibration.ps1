param(
	[string]$RepoRoot = "F:\OneDrive\Documentos\GitHub\simufire",
	[string]$GodotExe = "F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe",
	[double]$DurationS = 420.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$casesDir = Join-Path $RepoRoot "sim\validation\cases"
$reportsDir = Join-Path $RepoRoot "sim\validation\reports\micro_sweeps"
$summaryJsonPath = Join-Path $reportsDir "ghanekar_micro_calibration_2026-04-20.json"
$summaryMdPath = Join-Path $RepoRoot "sim\validation\MICRO_CALIBRACION_GHANEKAR_2026-04-20.md"

New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

function New-BaseCase {
	return [ordered]@{
		template = "ghanekar_bedroom_hallway"
		duration_s = $DurationS
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
		$FlashoverS,
		$FinalTemp09C,
		$O2S,
		$Co200S,
		$Co1200S,
		$SmokeS
	)

	$flashPenalty = 0.0
	if ($null -ne $FlashoverS) {
		$flashPenalty = [math]::Abs([double]$FlashoverS - 186.0)
	}
	else {
		$tempPenalty = if ($null -ne $FinalTemp09C) { [math]::Max(0.0, 600.0 - [double]$FinalTemp09C) * 0.40 } else { 120.0 }
		$flashPenalty = 140.0 + $tempPenalty
	}

	$o2Penalty = if ($null -ne $O2S) { [math]::Abs([double]$O2S - 198.0) } else { 180.0 }
	$co200Penalty = if ($null -ne $Co200S) { [math]::Abs([double]$Co200S - 204.0) } else { 180.0 }
	$co1200Penalty = if ($null -ne $Co1200S) { [math]::Abs([double]$Co1200S - 216.0) } else { 180.0 }
	$smokePenalty = if ($null -ne $SmokeS) { [math]::Abs([double]$SmokeS - 198.0) } else { 120.0 }

	return [math]::Round(($flashPenalty * 1.7) + $o2Penalty + $co200Penalty + $co1200Penalty + ($smokePenalty * 0.6), 2)
}

$variants = @(
	[pscustomobject]@{
		Name = "current_wired"
		Description = "Caso actual con lower_layer_warming_rate activo por defecto"
		Engine = [ordered]@{}
	},
	[pscustomobject]@{
		Name = "combo_balanced_llw016"
		Description = "Combo balanced con calentamiento moderado de capa baja"
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
			lower_layer_warming_rate = 0.016
		}
	},
	[pscustomobject]@{
		Name = "combo_balanced_llw020"
		Description = "Combo balanced con calentamiento fuerte de capa baja"
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
			lower_layer_warming_rate = 0.020
		}
	},
	[pscustomobject]@{
		Name = "combo_balanced_llw024"
		Description = "Combo balanced con calentamiento muy fuerte de capa baja"
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
			lower_layer_warming_rate = 0.024
		}
	},
	[pscustomobject]@{
		Name = "hybrid_transport_thermal"
		Description = "Pasillo mas amortiguado con termica balanceada y capa baja activa"
		Engine = [ordered]@{
			doorway_o2_exchange_coeff = 1.00
			doorway_o2_background_exchange_kg_s_m2 = 0.035
			base_spill_kg_s_per_m2 = 0.32
			temp_push_factor = 0.0055
			ach_infiltration = 1.00
			upper_to_lower_loss_rate = 0.038
			upper_to_ambient_loss_rate = 0.0065
			wall_absorption_rate = 0.0025
			thermal_gradient_band_fraction = 0.50
			thermal_gradient_max_band_m = 0.90
			floor_cooling_band_fraction = 0.12
			floor_cooling_band_max_m = 0.20
			lower_layer_warming_rate = 0.020
		}
	},
	[pscustomobject]@{
		Name = "hybrid_transport_thermal_hot"
		Description = "Como el hybrid pero empujando mas la zona respirable"
		Engine = [ordered]@{
			doorway_o2_exchange_coeff = 1.00
			doorway_o2_background_exchange_kg_s_m2 = 0.035
			base_spill_kg_s_per_m2 = 0.32
			temp_push_factor = 0.0055
			ach_infiltration = 1.00
			upper_to_lower_loss_rate = 0.042
			upper_to_ambient_loss_rate = 0.0060
			wall_absorption_rate = 0.0022
			thermal_gradient_band_fraction = 0.55
			thermal_gradient_max_band_m = 0.95
			floor_cooling_band_fraction = 0.10
			floor_cooling_band_max_m = 0.18
			lower_layer_warming_rate = 0.022
		}
	},
	[pscustomobject]@{
		Name = "transport_soft_plus_hotfloor"
		Description = "Mejor transporte del barrido previo con calentamiento respirable adicional"
		Engine = [ordered]@{
			doorway_o2_exchange_coeff = 1.00
			doorway_o2_background_exchange_kg_s_m2 = 0.035
			base_spill_kg_s_per_m2 = 0.30
			temp_push_factor = 0.0050
			ach_infiltration = 1.10
			upper_to_lower_loss_rate = 0.040
			upper_to_ambient_loss_rate = 0.0060
			wall_absorption_rate = 0.0022
			thermal_gradient_band_fraction = 0.55
			thermal_gradient_max_band_m = 0.95
			floor_cooling_band_fraction = 0.10
			floor_cooling_band_max_m = 0.18
			lower_layer_warming_rate = 0.022
		}
	}
)

$results = @()
$tempCasePaths = @()

foreach ($variant in $variants) {
	$caseName = "_micro_ghanekar_$($variant.Name)"
	$casePath = Join-Path $casesDir "$caseName.json"
	$reportPath = Join-Path $reportsDir "$caseName.json"
	$tempCasePaths += $casePath

	$caseData = New-BaseCase
	foreach ($key in $variant.Engine.Keys) {
		$caseData.engine_overrides[$key] = $variant.Engine[$key]
	}

	$caseJson = $caseData | ConvertTo-Json -Depth 12
	Set-Content -LiteralPath $casePath -Value $caseJson -Encoding UTF8

	Write-Host ("[Micro] Running {0}" -f $variant.Name)
	& $GodotExe --headless --path $RepoRoot -- --validation-case $caseName --validation-output ("res://sim/validation/reports/micro_sweeps/{0}.json" -f $caseName) --validation-duration $DurationS | Out-Host
	if ($LASTEXITCODE -ne 0) {
		throw "Godot devolvio codigo $LASTEXITCODE en $caseName"
	}

	if (-not (Test-Path -LiteralPath $reportPath)) {
		throw "No se genero reporte para $caseName"
	}

	$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
	$metrics = $report.metrics

	$flashoverS = Get-MetricValue -Metrics $metrics -Name "time_room_0_temp_0_9m_above_600c_s"
	$finalTemp09C = Get-MetricValue -Metrics $metrics -Name "room_0_final_temp_at_0_9m_c"
	$o2S = Get-MetricValue -Metrics $metrics -Name "time_room_2_o2_below_20_4pct_s"
	$co200S = Get-MetricValue -Metrics $metrics -Name "time_room_2_co_above_200ppm_s"
	$co1200S = Get-MetricValue -Metrics $metrics -Name "time_room_2_co_above_1200ppm_s"
	$smokeS = Get-MetricValue -Metrics $metrics -Name "time_room_2_smoke_start_s"
	$score = Get-Score `
		-FlashoverS $flashoverS `
		-FinalTemp09C $finalTemp09C `
		-O2S $o2S `
		-Co200S $co200S `
		-Co1200S $co1200S `
		-SmokeS $smokeS

	$result = [ordered]@{
		name = $variant.Name
		description = $variant.Description
		score = $score
		report = $reportPath
		metrics = [ordered]@{
			time_room_0_temp_0_9m_above_600c_s = $flashoverS
			room_0_final_temp_at_0_9m_c = $finalTemp09C
			time_room_2_o2_below_20_4pct_s = $o2S
			time_room_2_co_above_200ppm_s = $co200S
			time_room_2_co_above_1200ppm_s = $co1200S
			time_room_2_smoke_start_s = $smokeS
			room_0_peak_hrr_kw = Get-MetricValue -Metrics $metrics -Name "room_0_peak_hrr_kw"
			room_2_peak_co_ppm = Get-MetricValue -Metrics $metrics -Name "room_2_peak_co_ppm"
			room_2_peak_temp_upper_c = Get-MetricValue -Metrics $metrics -Name "room_2_peak_temp_upper_c"
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
		flashover_temp_0_9m_c = 600.0
		o2_hallway_s = 198.0
		co_hallway_s = 204.0
		idlh_proxy_co1200_s = 216.0
	}
	results = $sorted
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryJsonPath -Encoding UTF8

$lines = @()
$lines += "# Micro Calibracion Ghanekar - 2026-04-20"
$lines += ""
$lines += ('Duracion por corrida: `{0} s`' -f $DurationS)
$lines += ""
$lines += "## Ranking"
$lines += ""
$lines += "| Variante | Score | Flashover 0.9 m | Temp final 0.9 m | O2 hallway | CO hallway | CO>1200 | Smoke hallway |"
$lines += "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"

foreach ($item in $sorted) {
	$metrics = $item.metrics
	$flashCell = if ($null -eq $metrics.time_room_0_temp_0_9m_above_600c_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_0_temp_0_9m_above_600c_s, 2) }
	$tempCell = if ($null -eq $metrics.room_0_final_temp_at_0_9m_c) { "n/a" } else { [math]::Round([double]$metrics.room_0_final_temp_at_0_9m_c, 2) }
	$o2Cell = if ($null -eq $metrics.time_room_2_o2_below_20_4pct_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_2_o2_below_20_4pct_s, 2) }
	$co200Cell = if ($null -eq $metrics.time_room_2_co_above_200ppm_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_2_co_above_200ppm_s, 2) }
	$co1200Cell = if ($null -eq $metrics.time_room_2_co_above_1200ppm_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_2_co_above_1200ppm_s, 2) }
	$smokeCell = if ($null -eq $metrics.time_room_2_smoke_start_s) { "n/a" } else { [math]::Round([double]$metrics.time_room_2_smoke_start_s, 2) }
	$lines += "| $($item.name) | $([math]::Round([double]$item.score, 2)) | $flashCell | $tempCell | $o2Cell | $co200Cell | $co1200Cell | $smokeCell |"
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
	$lines += "- sin cambios sobre el caso actual"
}
else {
	foreach ($property in $best.engine_overrides.PSObject.Properties) {
		$lines += ('- `{0} = {1}`' -f $property.Name, $property.Value)
	}
}

Set-Content -LiteralPath $summaryMdPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8

Write-Host ""
Write-Host "[Micro] Summary written to $summaryMdPath"
Write-Host "[Micro] JSON written to $summaryJsonPath"
