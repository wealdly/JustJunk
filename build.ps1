# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Build script for JustJunk distribution package
# Run: .\build.ps1

$addonName = "JustJunk"
$version = (Get-Content "JustJunk.toc" | Select-String "## Version:" | ForEach-Object { $_ -replace "## Version:\s*", "" }).Trim()
if (-not $version) { $version = "dev" }

$distDir = Join-Path $PSScriptRoot "dist"
$tempDir = Join-Path $env:TEMP "$addonName-build"
$outputDir = Join-Path $tempDir $addonName
$zipFile = Join-Path $distDir "$addonName-$version.zip"

if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Write-Host "Building $addonName v$version..." -ForegroundColor Cyan

$addonFiles = Get-Content "JustJunk.toc" |
    Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' -and $_ -notmatch '^Libs[\\/]' } |
    ForEach-Object { $_.Trim() }
$coreFiles = @("JustJunk.toc", "LICENSE", "README.md") + $addonFiles

$missingFiles = @()
foreach ($file in $coreFiles) {
    $src = Join-Path $PSScriptRoot $file
    if (-not (Test-Path $src)) {
        $missingFiles += $file
    }
}
if ($missingFiles.Count -gt 0) {
    Write-Host "`nBuild FAILED - missing files:" -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

foreach ($file in $coreFiles) {
    $src = Join-Path $PSScriptRoot $file
    $dest = Join-Path $outputDir $file
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item $src $dest -Force
}

$libsDest = Join-Path $outputDir "Libs"
Copy-Item (Join-Path $PSScriptRoot "Libs") $libsDest -Recurse -Force

Get-ChildItem $libsDest -Directory | ForEach-Object {
    $nested = Join-Path $_.FullName $_.Name
    if (Test-Path $nested) {
        Write-Host "  Removing duplicate: Libs/$($_.Name)/$($_.Name)" -ForegroundColor Yellow
        Remove-Item $nested -Recurse -Force
    }
}

Write-Host "Creating ZIP archive..." -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipFile, 'Create')
Get-ChildItem $outputDir -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($tempDir.Length + 1).Replace('\\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $_.FullName, $relativePath, [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
}
$zip.Dispose()

Remove-Item $tempDir -Recurse -Force

Write-Host "`nBuild complete!" -ForegroundColor Green
Write-Host "  ZIP: $zipFile" -ForegroundColor White

$size = (Get-Item $zipFile).Length / 1KB
Write-Host "  Size: $([math]::Round($size, 1)) KB" -ForegroundColor White
