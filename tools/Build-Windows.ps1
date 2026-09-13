param([Parameter(Mandatory=$true)][string]$Godot, [string]$Templates)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$templateDir = Join-Path $PSScriptRoot 'local\templates'
if ($Templates) {
    New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
    foreach ($filename in @('windows_release_x86_64.exe','windows_debug_x86_64.exe')) {
        Copy-Item -LiteralPath (Join-Path $Templates $filename) -Destination (Join-Path $templateDir $filename)
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $templateDir 'windows_release_x86_64.exe'))) {
    throw 'Supply -Templates with the matching official Godot export template directory.'
}
& (Join-Path $PSScriptRoot 'Validate.ps1') -Godot $Godot
$projectConfig = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw -Encoding UTF8
if ($projectConfig -notmatch 'config/version="([0-9.]+)"') { throw 'Missing project version.' }
$buildVersion = $Matches[1]
$buildDir = Join-Path $projectRoot ('builds\WireRush-' + $buildVersion + '-Windows')
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$outputPath = Join-Path $buildDir 'WireRush.exe'
$result = & $Godot --headless --path $projectRoot --export-release 'Windows Desktop' $outputPath 2>&1
$code = $LASTEXITCODE
$result | Set-Content -LiteralPath (Join-Path $projectRoot 'validation\export.log') -Encoding UTF8
$result | Write-Output
if ($code -ne 0 -or ($result -match 'SCRIPT ERROR:|ERROR:')) { throw "Export failed (exit $code)" }
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\PLAY_GUIDE.md') -Destination (Join-Path $buildDir 'PLAY_GUIDE.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\THIRD_PARTY_NOTICES.md') -Destination (Join-Path $buildDir 'THIRD_PARTY_NOTICES.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\OFL.txt') -Destination (Join-Path $buildDir 'FONT_LICENSE.txt')
Compress-Archive -LiteralPath $outputPath,(Join-Path $buildDir 'PLAY_GUIDE.md'),(Join-Path $buildDir 'THIRD_PARTY_NOTICES.md'),(Join-Path $buildDir 'FONT_LICENSE.txt') -DestinationPath (Join-Path $projectRoot ('builds\WireRush-' + $buildVersion + '-Windows.zip')) -Force
Get-FileHash -LiteralPath $outputPath -Algorithm SHA256
