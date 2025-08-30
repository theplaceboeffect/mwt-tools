#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-Usage {
    Write-Host 'Usage:'
    Write-Host '  pwsh bin/tests.ps1 -l|--list'
    Write-Host '  pwsh bin/tests.ps1 -r <T0000> | --run <T0000>'
    Write-Host '  pwsh bin/tests.ps1 --run-all'
}

function Get-ProjectDir {
    param([string]$ScriptRoot)
    return (Split-Path -Parent -Path $ScriptRoot)
}

function Get-TestsDir {
    param([string]$ProjectDir)
    return (Join-Path -Path $ProjectDir -ChildPath 'tests')
}

function Get-RunId { (Get-Date -Format 'yyyyMMdd-HHmmss') }

function New-ResultsDir {
    param([string]$ProjectDir, [string]$RunId)
    $resultsDir = Join-Path $ProjectDir (Join-Path 'testruns' $RunId)
    if (-not (Test-Path -LiteralPath $resultsDir)) {
        New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
    }
    return $resultsDir
}

function Get-TestList {
    param([string]$TestsDir)
    $files = Get-ChildItem -LiteralPath $TestsDir -Filter '*.Tests.ps1' -File -ErrorAction Stop
    $found = @()
    foreach ($f in $files) {
        $text = Get-Content -LiteralPath $f.FullName -Raw
        $regex = [regex]"(?m)\bIt\s*'([^']*?)\s*\[(T\d{4})\]'\s*\{"
        foreach ($m in $regex.Matches($text)) {
            $found += [pscustomobject]@{
                Id          = $m.Groups[2].Value
                Description = $m.Groups[1].Value.Trim()
                File        = $f.Name
            }
        }
    }
    if ($found.Count -eq 0) {
        Write-Host 'No tests found.'
        return
    }
    $found = $found | Sort-Object Id
    foreach ($t in $found) {
        Write-Host ("{0} - {1} ({2})" -f $t.Id, $t.Description, $t.File)
    }
}

function New-PesterConfig {
    param(
        [string]$TestsDir,
        [string]$FilterFullName
    )
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $TestsDir
    $cfg.Output.Verbosity = 'Detailed'
    $cfg.Run.PassThru = $true
    if ($FilterFullName) { $cfg.Filter.FullName = "*${FilterFullName}*" }
    return $cfg
}

function Write-TestResultsXml {
    param(
        [Parameter(Mandatory=$true)] $PesterResult,
        [Parameter(Mandatory=$true)] [string] $OutputPath
    )
    try {
        if (Get-Command New-PesterReport -ErrorAction SilentlyContinue) {
            New-PesterReport -Result $PesterResult -OutputFormat NUnitXml -OutputPath $OutputPath | Out-Null
            return
        }
    } catch { }
    Set-Content -LiteralPath $OutputPath -Value '<test-results generated="manual" />' -Encoding UTF8
}

function Invoke-AllTests {
    param([string]$ProjectDir)
    $testsDir = Get-TestsDir -ProjectDir $ProjectDir
    $runId = Get-RunId
    $env:MWT_G_TEST_RUN_ID = $runId
    $resultsDir = New-ResultsDir -ProjectDir $ProjectDir -RunId $runId
    $resultsFile = Join-Path $resultsDir 'testResults.xml'
    Push-Location $ProjectDir
    try {
        $cfg = New-PesterConfig -TestsDir $testsDir
        $result = Invoke-Pester -Configuration $cfg
        Write-TestResultsXml -PesterResult $result -OutputPath $resultsFile
        if ($result.FailedCount -gt 0) { exit 1 } else { exit 0 }
    } finally {
        Pop-Location
    }
}

function Invoke-TestById {
    param([string]$ProjectDir, [string]$TestId)
    if ($TestId -notmatch '^(?i)T\d{4}$') { throw "Invalid test id '$TestId'. Expected format: T0000" }
    $testsDir = Get-TestsDir -ProjectDir $ProjectDir
    $runId = Get-RunId
    $env:MWT_G_TEST_RUN_ID = $runId
    $resultsDir = New-ResultsDir -ProjectDir $ProjectDir -RunId $runId
    $resultsFile = Join-Path $resultsDir 'testResults.xml'
    Push-Location $ProjectDir
    try {
        $cfg = New-PesterConfig -TestsDir $testsDir -FilterFullName $TestId
        $result = Invoke-Pester -Configuration $cfg
        Write-TestResultsXml -PesterResult $result -OutputPath $resultsFile
        if ($result.FailedCount -gt 0) { exit 1 } else { exit 0 }
    } finally {
        Pop-Location
    }
}

# Argument parsing to support the exact flags requested in the prompt
$mode = $null
$testId = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    switch -Regex ($arg) {
        '^(--list|-l)$' { $mode = 'list' }
        '^(?:-r|--run)$' {
            if ($i + 1 -ge $args.Count) { throw 'Missing argument after -r/-run' }
            $mode = 'runOne'
            $testId = [string]$args[$i + 1]
            $i++
        }
        '^--run-all' { $mode = 'runAll' }
        '^-h$|^--help$' { Show-Usage; exit 0 }
        default { }
    }
}

$projectDir = Get-ProjectDir -ScriptRoot $PSScriptRoot

switch ($mode) {
    'list'   { Get-TestList -TestsDir (Get-TestsDir -ProjectDir $projectDir); break }
    'runOne' { Invoke-TestById -ProjectDir $projectDir -TestId $testId; break }
    'runAll' { Invoke-AllTests -ProjectDir $projectDir; break }
    default  { Show-Usage; exit 2 }
}


