param(
    [string]$Variant
)

$ErrorActionPreference = "Stop"

$dotnetTargetSyncTrayzor = "net8.0-windows10.0.17763.0"
. "$PSScriptRoot\helpers\get-arch.ps1"
$arch = Get-Arch
$dotnetArch = switch ($arch) {
    "amd64" { "win-x64" }
    "arm64" { "win-arm64" }
    default { throw "Unknown architecture: $arch" }
}
$syncthingExe = ".\syncthing\syncthing.exe"
$publishDir = ".\src\SyncTrayzor\bin\Release\$dotnetTargetSyncTrayzor\$dotnetArch\publish"
$publishDirFramework = ".\src\SyncTrayzor\bin\Release\$dotnetTargetSyncTrayzor\framework-publish"
$mergedDir = ".\dist"
$mergedFrameworkDir = ".\dist-framework"

Write-Host "Building SyncTrayzor for $Variant"

# Clean publish dirs first
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
if (Test-Path $publishDirFramework) { Remove-Item $publishDirFramework -Recurse -Force }

# Publish self-contained (existing behaviour)
dotnet publish -c Release -p:DebugType=None -p:DebugSymbols=false -p:SelfContained=true -r $dotnetArch -p:AppConfigVariant=$Variant -o $publishDir src/SyncTrayzor/SyncTrayzor.csproj
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build SyncTrayzor. Exiting."
    exit $LASTEXITCODE
}

# Publish framework-dependent build (requires system .NET runtime)
dotnet publish -c Release -p:DebugType=None -p:DebugSymbols=false -p:SelfContained=false -p:AppConfigVariant=$Variant -o $publishDirFramework src/SyncTrayzor/SyncTrayzor.csproj
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build framework-dependent SyncTrayzor. Exiting."
    exit $LASTEXITCODE
}

# Remove and recreate merged directory (self-contained)
if (Test-Path $mergedDir) { Remove-Item $mergedDir -Recurse -Force }
New-Item -ItemType Directory -Path $mergedDir | Out-Null
Copy-Item "$publishDir\*" $mergedDir -Recurse -Force

# Also create a framework-dependent dist alongside the self-contained dist
if (Test-Path $mergedFrameworkDir) { Remove-Item $mergedFrameworkDir -Recurse -Force }
New-Item -ItemType Directory -Path $mergedFrameworkDir | Out-Null
Copy-Item "$publishDirFramework\*" $mergedFrameworkDir -Recurse -Force

$additionalFiles = @(
    $syncthingExe,
    # Also include VC++ runtime files for systems that do not have it
    "C:\Windows\System32\msvcp140.dll",
    "C:\Windows\System32\vcruntime140.dll",
    "C:\Windows\System32\vcruntime140_1.dll"
)
foreach ($file in $additionalFiles) {
    if (Test-Path $file) {
        Copy-Item $file $mergedDir -Force
    }
    else {
        Write-Error "File not found: $file"
        exit 1
    }
}
