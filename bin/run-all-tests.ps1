#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent -Path $PSCommandPath
$projectDir = Split-Path -Parent -Path $scriptDir

Push-Location $projectDir
try {
    & (Join-Path $scriptDir 'tests.ps1') --run-all
} finally {
    Pop-Location
}