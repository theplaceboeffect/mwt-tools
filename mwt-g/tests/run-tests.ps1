#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsDir = Split-Path -Parent -Path $PSCommandPath
# Run from mwt-g directory and write outputs under mwt-g/testruns/YYYYMMDD-HHMMSS
$projectDir = Split-Path -Parent -Path $testsDir
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$env:MWT_G_TEST_RUN_ID = $runId
Push-Location $projectDir
try {
    # Run once and emit NUnit XML directly to mwt-g/testruns/<runId>/testResults.xml
    $resultsDir = Join-Path $projectDir (Join-Path 'testruns' $runId)
    if (-not (Test-Path -LiteralPath $resultsDir)) { New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null }
    $resultsFile = Join-Path $resultsDir 'testResults.xml'
    # Use -CI with -Output 'Detailed' and -PassThru; then write results to file with Tee-Object
    $result = Invoke-Pester -CI -Output Detailed -Path $testsDir -PassThru
    # If available, try New-PesterReport; otherwise write minimal file header
    try {
        if (Get-Command New-PesterReport -ErrorAction SilentlyContinue) {
            New-PesterReport -Result $result -OutputFormat NUnitXml -OutputPath $resultsFile | Out-Null
        }
        else {
            Set-Content -LiteralPath $resultsFile -Value '<test-results generated="manual" />' -Encoding UTF8
        }
    } catch {
        Set-Content -LiteralPath $resultsFile -Value '<test-results generated="manual-error" />' -Encoding UTF8
    }

    # If a legacy testResults.xml exists at project root, move it into this run's directory
    $legacyResults = Join-Path $projectDir 'testResults.xml'
    if (Test-Path -LiteralPath $legacyResults) {
        try {
            Move-Item -LiteralPath $legacyResults -Destination $resultsFile -Force -ErrorAction Stop
        } catch {
            # If move fails, attempt to copy instead to avoid losing results
            try { Copy-Item -LiteralPath $legacyResults -Destination $resultsFile -Force } catch { }
            # Best-effort cleanup of legacy file
            try { Remove-Item -LiteralPath $legacyResults -Force } catch { }
        }
    }
}
finally {
    Pop-Location
}


