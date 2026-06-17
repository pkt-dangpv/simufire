[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludeGodotCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDirectory

$targets = @(
    ".godot_validation_logs",
    ".matplotlib-cache",
    ".tmp_guardrail_tests",
    "graphs",
    "runs"
)

if ($IncludeGodotCache) {
    $targets += ".godot"
}

foreach ($relativePath in $targets) {
    $target = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $target)) {
        continue
    }

    if ($PSCmdlet.ShouldProcess($target, "Remove local generated artifact")) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

Write-Host "Workspace cleanup complete."
