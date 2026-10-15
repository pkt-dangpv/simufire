# Tool discovery is local to the executing machine; no drive or username is shared.
function Resolve-SimuFireGodot {
    param([string]$RequestedPath = "")

    foreach ($value in @($RequestedPath, $env:GODOT_EXE)) {
        if (-not $value) { continue }
        if (Test-Path -LiteralPath $value -PathType Leaf) {
            return (Resolve-Path -LiteralPath $value).Path
        }
        $command = Get-Command $value -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
        throw "No se encontro Godot: $value. Corrige -GodotExe o GODOT_EXE."
    }

    foreach ($name in @("godot", "godot4", "godot_console", "godot4_console")) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    $directories = @(
        [Environment]::GetFolderPath("Desktop"),
        (Join-Path ([Environment]::GetFolderPath("UserProfile")) "Desktop"),
        (Join-Path ([Environment]::GetFolderPath("UserProfile")) "Escritorio")
    )
    foreach ($oneDriveRoot in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if ($oneDriveRoot) {
            $directories += Join-Path $oneDriveRoot "Desktop"
            $directories += Join-Path $oneDriveRoot "Escritorio"
        }
    }
    foreach ($directory in ($directories | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        $builds = @(Get-ChildItem -LiteralPath $directory -Filter "Godot*.exe" -File |
            Sort-Object @{Expression = { $_.Name -match "v4.7.1-stable" }; Descending = $true},
                        @{Expression = { $_.Name -match "console" }; Descending = $true},
                        @{Expression = { $_.Name }; Descending = $true})
        if ($builds.Count -gt 0) { return $builds[0].FullName }
    }
    throw "No se encontro Godot. Define -GodotExe, GODOT_EXE o anade Godot al PATH de este equipo."
}
