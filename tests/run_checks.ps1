param(
    [string]$GodotPath = 'C:\Program Files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [string[]]$Tests = @(),
    [string]$RunName = 'complete',
    [int]$TimeoutSeconds = 45
)
$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path -Parent $PSScriptRoot
$taskGodotPath = (Get-Item -LiteralPath $GodotPath).FullName
$taskLogRoot = Join-Path $taskProjectRoot ('.godot\visual-validation\' + $RunName)
New-Item -ItemType Directory -Force -Path $taskLogRoot | Out-Null
$taskPreviousAppData = $env:APPDATA
$env:APPDATA = Join-Path $taskLogRoot 'user'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
$taskResults = @()
try {
    if ($Tests.Count -eq 0) {
        $Tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'test_*.gd' | Sort-Object Name | ForEach-Object { $_.BaseName })
    }
    foreach ($taskTest in $Tests) {
        $taskScript = 'res://tests/' + $taskTest + '.gd'
        $taskOutput = Join-Path $taskLogRoot ($taskTest + '.log')
        $taskErrors = Join-Path $taskLogRoot ($taskTest + '-errors.log')
        $taskClock = [System.Diagnostics.Stopwatch]::StartNew()
        $taskProcess = Start-Process -FilePath $taskGodotPath -WorkingDirectory $taskProjectRoot -ArgumentList @('--headless','--path',$taskProjectRoot,'--script',$taskScript) -WindowStyle Hidden -PassThru -RedirectStandardOutput $taskOutput -RedirectStandardError $taskErrors
        $taskTimedOut = -not $taskProcess.WaitForExit([Math]::Min(60, $TimeoutSeconds) * 1000)
        if ($taskTimedOut) {
            $taskProcess.Kill($true)
            $taskProcess.WaitForExit()
        }
        $taskProcess.Refresh()
        $taskText = (Get-Content -LiteralPath $taskOutput -Raw) + (Get-Content -LiteralPath $taskErrors -Raw)
        $taskSummary = [regex]::Matches($taskText, '(?im)^.*?:\s*(\d+)\s*checks[^\r\n]*')
        $taskCount = if ($taskSummary.Count -gt 0) { [int]$taskSummary[$taskSummary.Count-1].Groups[1].Value } else { 0 }
        $taskSuccess = -not $taskTimedOut -and $taskProcess.ExitCode -eq 0 -and $taskCount -gt 0 -and $taskText -notmatch '(?im)SCRIPT ERROR|Parse Error|^ERROR:|FAIL:|[1-9]\d* failures'
        $taskRow = [ordered]@{ test = $taskTest; passed = $taskSuccess; checks = $taskCount; exitCode = $taskProcess.ExitCode; timedOut = $taskTimedOut; seconds = [Math]::Round($taskClock.Elapsed.TotalSeconds, 2) }
        $taskResults += [pscustomobject]$taskRow
        Write-Output ($taskTest + ': ' + $taskCount + ' checks, ' + $(if ($taskSuccess) { 'PASS' } else { 'FAIL (see logs)' }))
    }
} finally {
    $env:APPDATA = $taskPreviousAppData
}
$taskResults | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskLogRoot 'results.json') -Encoding utf8
$taskFailed = @($taskResults | Where-Object { -not $_.passed })
$taskTotal = ($taskResults | Measure-Object -Property checks -Sum).Sum
Write-Output ('TOTAL: ' + $taskResults.Count + ' suites, ' + $taskTotal + ' checks, ' + $taskFailed.Count + ' failed suites')
if ($taskFailed.Count -gt 0) { exit 1 }
