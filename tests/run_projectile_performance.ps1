param(
    [ValidateSet('cpu', 'render', 'baseline', 'integration')][string]$Mode = 'cpu'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$godotExecutable = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$outputDirectory = Join-Path $PSScriptRoot 'tmp'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$logPath = Join-Path $outputDirectory ('projectile_' + $Mode + '.log')
$testScript = if ($Mode -eq 'baseline') { 'tests/frame_budget_test.gd' } else { 'tests/projectile_performance_test.gd' }
if ($Mode -eq 'integration') { $testScript = 'tests/projectile_integration_performance_test.gd' }
$arguments = @('--path', ('"' + $projectRoot + '"'), '--script', $testScript, '--log-file', ('"' + $logPath + '"'))
if ($Mode -eq 'render') { $arguments += @('--', '--render-only') } else { if ($Mode -eq 'integration') { $testScript = 'tests/projectile_integration_performance_test.gd' }
$arguments = @('--headless') + $arguments }
$testProcess = Start-Process -FilePath $godotExecutable -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
if (-not $testProcess.WaitForExit(1800000)) {
    $testProcess.Kill()
    throw 'Godot benchmark exceeded its 1800-second watchdog.'
}
$testProcess.Refresh()
Get-Content -LiteralPath $logPath -Encoding UTF8
if ($testProcess.ExitCode -ne 0) { throw "Godot exited with code $($testProcess.ExitCode)" }
$passMarker = if ($Mode -eq 'baseline') { 'FRAME_BUDGET_PASS' } else { 'PROJECTILE_PERF_PASS' }
if ($Mode -eq 'integration') { $passMarker = 'PROJECTILE_INTEGRATION_PASS' }
if (-not (Select-String -LiteralPath $logPath -Pattern $passMarker -Quiet)) { throw "Missing completion marker: $passMarker" }
if (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|Parse Error:|PROJECTILE_PERF_FAIL|FRAME_BUDGET_FAIL|PROJECTILE_INTEGRATION_FAIL' -Quiet) { throw 'Godot reported a script or benchmark failure.' }
