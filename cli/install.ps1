Write-Host "=== Addon Template Setup ===" -ForegroundColor Cyan
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