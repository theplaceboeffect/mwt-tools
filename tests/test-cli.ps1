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

$projectDir = Split-Path -Parent -Path $PSScriptRoot
$toolPath = Join-Path -Path $projectDir -ChildPath 'bin/mwt-g.ps1'
if (-not (Test-Path -LiteralPath $toolPath)) {
    Write-Error "Tool not found at $toolPath"
    exit 1
}

$aliasesPath = Join-Path -Path $projectDir -ChildPath 'aliases.toml'
$backupPath = "$aliasesPath.bak"

if (Test-Path -LiteralPath $aliasesPath) {
    Copy-Item -LiteralPath $aliasesPath -Destination $backupPath -Force
}

try {
    if (Test-Path -LiteralPath $aliasesPath) { Remove-Item -LiteralPath $aliasesPath -Force }

    $alias = 'g'
    $url = 'https://www.google.com'

    # Add alias
    & $toolPath $alias $url | Out-Null

    # +n action
    $outN = & $toolPath '+n' $alias
    Assert-Equal -Expected $url -Actual $outN -Message '+n should print exact URL'

    # default action should open browser; use dry-run to capture URL
    $env:MWT_G_BROWSER_DRYRUN = '1'
    try {
        $outDefault = & $toolPath $alias
        Assert-Equal -Expected $url -Actual $outDefault -Message 'default action should open browser (dry-run emits URL)'
    } finally {
        Remove-Item Env:MWT_G_BROWSER_DRYRUN -ErrorAction SilentlyContinue
    }

    Write-Host 'All CLI tests passed'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $backupPath) {
        Move-Item -LiteralPath $backupPath -Destination $aliasesPath -Force
    }
}


