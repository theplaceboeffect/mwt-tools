#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)] [string] $Expected,
        [Parameter(Mandatory = $true)] [string] $Actual,
        [string] $Message = 'Values are not equal'
    )
    if ($Expected -ne $Actual) {
        Write-Error "ASSERTION FAILED: $Message`nExpected: [$Expected]`nActual:   [$Actual]"
        exit 1
    }
}

$toolPath = Join-Path -Path (Get-Location) -ChildPath 'mwt-g/bin/mwt-g.ps1'
if (-not (Test-Path -LiteralPath $toolPath)) {
    Write-Error "Tool not found at $toolPath"
    exit 1
}

$settingsPath = Join-Path -Path (Get-Location) -ChildPath 'mwt-g/settings.json'
$backupPath = "$settingsPath.bak"

if (Test-Path -LiteralPath $settingsPath) {
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force
}

try {
    if (Test-Path -LiteralPath $settingsPath) { Remove-Item -LiteralPath $settingsPath -Force }

    $alias = 'g'
    $url = 'https://www.google.com'

    # Add alias
    & $toolPath $alias $url | Out-Null

    # +n action
    $outN = & $toolPath '+n' $alias
    Assert-Equal -Expected $url -Actual $outN -Message '+n should print exact URL'

    # default action
    $outDefault = & $toolPath $alias
    Assert-Equal -Expected $url -Actual $outDefault -Message 'default action should print exact URL'

    Write-Host 'All tests passed for v00.01.01'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $backupPath) {
        Move-Item -LiteralPath $backupPath -Destination $settingsPath -Force
    }
}


