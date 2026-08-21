Write-Host "=== Cadon - Addon Template Setup ===" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
$sourceRoot = Split-Path $scriptDir -Parent

$destDir = Read-Host "Enter the destination folder for AddonTemplate (e.g. D:\Tools\AddonTemplate)"
if ([string]::IsNullOrWhiteSpace($destDir)) {
    Write-Host "Destination folder cannot be empty." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

$comMojangPath = Read-Host "Enter the path to your com.mojang folder on this device"
if ([string]::IsNullOrWhiteSpace($comMojangPath) -or -not (Test-Path $comMojangPath)) {
    Write-Host "The com.mojang path is invalid or was not found." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

if ($sourceRoot -ne $destDir) {
    Write-Host "Copying template files to $destDir..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Path "$sourceRoot\*" -Destination $destDir -Recurse -Force -Exclude "install.ps1", "install.bat"
} else {
    Write-Host "Source and destination are the same, skipping copy." -ForegroundColor Yellow
}

# ---- Extract RP.zip / BP.zip into RP/ and BP/ folders ----
function Resolve-ExtractedRoot($extractPath) {
    if (Test-Path (Join-Path $extractPath "manifest.json")) {
        return $extractPath
    }
    $subDirs = Get-ChildItem -Path $extractPath -Directory
    if ($subDirs.Count -eq 1) {
        return $subDirs[0].FullName
    }
    return $extractPath
}

$rpZipDest = Join-Path $destDir "RP.zip"
$bpZipDest = Join-Path $destDir "BP.zip"
$rpFolderDest = Join-Path $destDir "RP"
$bpFolderDest = Join-Path $destDir "BP"

if (Test-Path $rpZipDest) {
    Write-Host "Extracting RP.zip..." -ForegroundColor Cyan
    $tempRP = Join-Path $env:TEMP "cadon_install_rp_$(Get-Random)"
    Expand-Archive -Path $rpZipDest -DestinationPath $tempRP -Force
    $rpRoot = Resolve-ExtractedRoot $tempRP

    if (Test-Path $rpFolderDest) { Remove-Item -Recurse -Force $rpFolderDest }
    Move-Item -Path $rpRoot -Destination $rpFolderDest

    Remove-Item -Recurse -Force $tempRP -ErrorAction SilentlyContinue
    Remove-Item -Force $rpZipDest
    Write-Host "RP folder ready." -ForegroundColor Green
} elseif (-not (Test-Path $rpFolderDest)) {
    Write-Host "Warning: neither RP.zip nor RP/ folder found." -ForegroundColor Yellow
}

if (Test-Path $bpZipDest) {
    Write-Host "Extracting BP.zip..." -ForegroundColor Cyan
    $tempBP = Join-Path $env:TEMP "cadon_install_bp_$(Get-Random)"
    Expand-Archive -Path $bpZipDest -DestinationPath $tempBP -Force
    $bpRoot = Resolve-ExtractedRoot $tempBP

    if (Test-Path $bpFolderDest) { Remove-Item -Recurse -Force $bpFolderDest }
    Move-Item -Path $bpRoot -Destination $bpFolderDest

    Remove-Item -Recurse -Force $tempBP -ErrorAction SilentlyContinue
    Remove-Item -Force $bpZipDest
    Write-Host "BP folder ready." -ForegroundColor Green
} elseif (-not (Test-Path $bpFolderDest)) {
    Write-Host "Warning: neither BP.zip nor BP/ folder found." -ForegroundColor Yellow
}

$cliDestDir = Join-Path $destDir "cli"
New-Item -ItemType Directory -Force -Path $cliDestDir | Out-Null

$config = @{ comMojangPath = $comMojangPath } | ConvertTo-Json
Set-Content -Path (Join-Path $cliDestDir "config.json") -Value $config

$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$cliDestDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$cliDestDir", "User")
    Write-Host "Folder added to PATH." -ForegroundColor Green
} else {
    Write-Host "Folder is already in PATH." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "Close and reopen Command Prompt, then try: cadon ProjectName"
Read-Host "Press Enter to exit"