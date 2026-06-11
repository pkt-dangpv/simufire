# regenerate_truth.ps1
# Regenera todos los CSVs de referencia CFAST y actualiza el manifiesto.
#
# REQUISITOS:
#   - CFAST 7.7.x instalado y accesible en $env:CFAST_EXE (o en PATH como 'cfast')
#   - Ejecutar desde la raiz del repositorio: .\truth\cfast\regenerate_truth.ps1
#
# USO INTENCIONADO SOLAMENTE: este script destruye los CSVs actuales y los
# reemplaza con los resultados de una nueva corrida de CFAST. Solo ejecutar si
# se modifican los ficheros .in del escenario o si se actualiza la version de CFAST.
# Despues de ejecutar, hacer commit del MANIFEST.json actualizado.

param(
    [string]$CfastExe = $env:CFAST_EXE,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$CfastDir = Join-Path $Root "sim\validation\cfast"

if (-not $CfastExe) {
    $CfastExe = (Get-Command "cfast" -ErrorAction SilentlyContinue)?.Source
}
if (-not $CfastExe -or -not (Test-Path $CfastExe)) {
    Write-Error "CFAST no encontrado. Instalar CFAST 7.7.x y definir `$env:CFAST_EXE o anyadirlo al PATH."
    exit 1
}

Write-Host "CFAST exe: $CfastExe"
Write-Host "Escenarios en: $CfastDir"

$inputs = Get-ChildItem -Path $CfastDir -Filter "*.in" | Where-Object { $_.Name -notmatch "^r0_" }
Write-Host "Ficheros .in encontrados: $($inputs.Count)"

foreach ($inp in $inputs) {
    $name = $inp.BaseName
    Write-Host "  Corriendo: $name ..."
    if (-not $DryRun) {
        Push-Location $CfastDir
        try {
            & $CfastExe $inp.Name
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "  CFAST retorno exit code $LASTEXITCODE para $name"
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "  [DryRun] Saltando ejecucion."
    }
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "Actualizando manifiesto de hashes..."
    python (Join-Path $Root "tools\freeze_cfast_truth.py") --update
    Write-Host "Listo. Hacer commit del MANIFEST.json actualizado."
} else {
    Write-Host "[DryRun] No se ejecuto CFAST ni se actualizo el manifiesto."
}
