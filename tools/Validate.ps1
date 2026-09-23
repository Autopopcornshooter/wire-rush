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
Invoke-Check 'upgrades' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/upgrades.gd','--','--test')
Invoke-Check 'difficulty' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/difficulty.gd','--','--test')
Invoke-Check 'city-boss' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/city_boss.gd','--','--test')
Invoke-Check 'city-completion' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/city_completion.gd','--','--test')
Invoke-Check 'wasteland' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/wasteland.gd','--','--test')
Invoke-Check 'wasteland-routes' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/wasteland_routes.gd','--','--test')
Invoke-Check 'traversal' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/traversal.gd','--','--test')
Invoke-Check 'settings-aim' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/settings_aim.gd','--','--test')
Invoke-Check 'range-obstacle' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/range_obstacle.gd','--','--test')
Invoke-Check 'jump-abilities' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/jump_abilities.gd','--','--test')
Invoke-Check 'comfort' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/comfort.gd','--','--test')
Invoke-Check 'character-animation' @('--headless','--fixed-fps','60','--path',$projectRoot,'--script','res://tests/character_animation.gd','--','--test')
Write-Output 'All validation gates passed.'
