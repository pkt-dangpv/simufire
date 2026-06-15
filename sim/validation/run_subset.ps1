param(
    [string]$Cases = "",
    [switch]$ContinueOnFailure
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runCaseScript = Join-Path $PSScriptRoot "run_case.ps1"
$allPass = $true
$caseList = $Cases -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

foreach ($c in $caseList) {
    Write-Host "[Suite] Caso: $c"
    $result = & $runCaseScript -CaseName $c -ProjectPath $projectPath 2>&1
    $passed = $result | Select-String "PASS" | Select-Object -Last 1
    $failed = $result | Select-String "FAIL" | Select-Object -Last 1
    if ($passed) {
        Write-Host " -> PASS"
    } elseif ($failed) {
        Write-Host " -> FAIL"
        $allPass = $false
        if (-not $ContinueOnFailure) { exit 1 }
    } else {
        Write-Host ($result | Select-Object -Last 5)
        $allPass = $false
        if (-not $ContinueOnFailure) { exit 1 }
    }
}

if ($allPass) {
    Write-Host "[Suite] Todos PASS"
    exit 0
} else {
    Write-Host "[Suite] Hay fallos"
    exit 1
}
