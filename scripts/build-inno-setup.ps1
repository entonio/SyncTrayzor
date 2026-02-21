param(
    [string]$Variant
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\helpers\get-arch.ps1"
$arch = Get-Arch
$installerArch = switch ($arch) {
    "amd64" { "x64" }
    "arm64" { "arm64" }
    default { throw "Unknown architecture: $arch" }
}
# Try to find ISCC.exe in PATH
$isccPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue

# Fallback to default location if not found
if (-not $isccPath) {
    $isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (-not (Test-Path $isccPath)) {
        throw "ISCC.exe not found in PATH or at '$isccPath'"
    }
}

$innoScript = Join-Path $PSScriptRoot "..\installer\installer-$installerArch.iss"

& $isccPath $innoScript
if ($LASTEXITCODE -ne 0) {
    throw "ISCC.exe failed with exit code $LASTEXITCODE"
}

# If a framework-dependent dist exists, build a framework-dependent installer
if (Test-Path "$PSScriptRoot\..\dist-framework") {
    Write-Host "Building framework-dependent installer"
    $cwd = Get-Location
    try {
        # Backup current dist
        if (Test-Path "$PSScriptRoot\..\dist-backup") { Remove-Item "$PSScriptRoot\..\dist-backup" -Recurse -Force }
        if (Test-Path "$PSScriptRoot\..\dist") { Move-Item "$PSScriptRoot\..\dist" "$PSScriptRoot\..\dist-backup" -Force }

        # Copy framework dist into place
        Copy-Item "$PSScriptRoot\..\dist-framework" "$PSScriptRoot\..\dist" -Recurse -Force

        & $isccPath $innoScript
        if ($LASTEXITCODE -ne 0) {
            throw "ISCC.exe (framework) failed with exit code $LASTEXITCODE"
        }

        # Find the produced installer and rename with -framework suffix
        $releaseDir = Join-Path $PSScriptRoot "..\release"
        $pattern = "*Setup-$installerArch.exe"
        $installer = Get-ChildItem -Path $releaseDir -Filter $pattern | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($installer) {
            $target = Join-Path $releaseDir ($installer.BaseName + "-framework" + $installer.Extension)
            Move-Item $installer.FullName $target -Force
            Write-Host "Framework-dependent installer created: $target"
        } else {
            Write-Warning "Framework installer was produced but couldn't be found to rename"
        }
    } finally {
        # Restore original dist
        if (Test-Path "$PSScriptRoot\..\dist") { Remove-Item "$PSScriptRoot\..\dist" -Recurse -Force }
        if (Test-Path "$PSScriptRoot\..\dist-backup") { Move-Item "$PSScriptRoot\..\dist-backup" "$PSScriptRoot\..\dist" -Force }
        Set-Location $cwd
    }
}
