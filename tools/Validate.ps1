param([Parameter(Mandatory=$true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $projectRoot 'validation'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
function Invoke-Check([string]$Name, [string[]]$EngineArgs) {
    $result = & $Godot @EngineArgs 2>&1
    $code = $LASTEXITCODE
    $result | Set-Content -LiteralPath (Join-Path $logDir ($Name + '.log')) -Encoding UTF8
    $result | Write-Output
    if ($code -ne 0 -or ($result -match 'SCRIPT ERROR:|ERROR:|FAIL ')) {
        throw "Validation failed: $Name (exit $code)"
    }
}
Invoke-Check 'import' @('--headless','--path',$projectRoot,'--editor','--import','--quit')
Invoke-Check 'behavior' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/run.gd','--','--test')
Invoke-Check 'traversal' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/traversal.gd','--','--test')
Invoke-Check 'settings-aim' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/settings_aim.gd','--','--test')
Invoke-Check 'range-obstacle' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/range_obstacle.gd','--','--test')
Invoke-Check 'launch-routes' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/launch_routes.gd','--','--test')
Invoke-Check 'comfort' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/comfort.gd','--','--test')
Write-Output 'All validation gates passed.'
