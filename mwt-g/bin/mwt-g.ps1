#!/usr/bin/env pwsh

<#!
.SYNOPSIS
  mwt-g: Minimal URL alias tool (v00.01.01)

.DESCRIPTION
  Stores simple alias -> URL mappings in JSON and resolves them.
  Storage precedence when reading:
    1) Project-local: ./mwt-g/settings.json
    2) User-level:    ~/.config/mwt-g/settings.json

  Writing (adding aliases):
    - Prefers project-local. Creates ./mwt-g/settings.json if missing.

.USAGE
  Add alias:
    mwt-g.ps1 <alias> <absolute-url>

  Display URL (+n is default action):
    mwt-g.ps1 <alias>
    mwt-g.ps1 +n <alias>

  Notes:
    - Only absolute http/https URLs are supported in v00.01.01
    - Other actions (+c, +b, +list, +register) are not implemented yet
!#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $ArgList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectSettingsPath {
    $projectSettingsDirectory = Join-Path -Path (Get-Location) -ChildPath 'mwt-g'
    return Join-Path -Path $projectSettingsDirectory -ChildPath 'settings.json'
}

function Get-UserSettingsPath {
    $homeDir = $env:HOME
    if ([string]::IsNullOrWhiteSpace($homeDir)) {
        $homeDir = $env:USERPROFILE
    }
    if ([string]::IsNullOrWhiteSpace($homeDir)) {
        $homeDir = [Environment]::GetFolderPath('UserProfile')
    }
    $userConfigDir = Join-Path -Path $homeDir -ChildPath '.config/mwt-g'
    return Join-Path -Path $userConfigDir -ChildPath 'settings.json'
}

function Get-EffectiveSettingsPathForRead {
    $projectPath = Get-ProjectSettingsPath
    $userPath = Get-UserSettingsPath

    if (Test-Path -LiteralPath $projectPath) { return $projectPath }
    if (Test-Path -LiteralPath $userPath)    { return $userPath }
    return $null
}

function Get-EffectiveSettingsPathForWrite {
    # Prefer project-local file for writes. Create directory if needed.
    $projectPath = Get-ProjectSettingsPath
    $projectDir = Split-Path -Parent -Path $projectPath
    if (-not (Test-Path -LiteralPath $projectDir)) {
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
    }
    return $projectPath
}

function Load-Aliases {
    $path = Get-EffectiveSettingsPathForRead
    if (-not $path) { return @{} }

    $raw = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    $json = $raw | ConvertFrom-Json -ErrorAction Stop

    $map = @{}
    $json.psobject.Properties | ForEach-Object { $map[$_.Name] = [string]$_.Value }
    return $map
}

function Save-Aliases {
    param(
        [hashtable] $Aliases
    )
    $path = Get-EffectiveSettingsPathForWrite
    $json = ($Aliases | ConvertTo-Json -Depth 5)
    $json | Set-Content -LiteralPath $path -NoNewline
    return $path
}

function Show-UsageAndExit {
    Write-Host @"
Usage:
  Add alias:
    mwt-g.ps1 <alias> <absolute-url>

  Display URL (+n is default):
    mwt-g.ps1 <alias>
    mwt-g.ps1 +n <alias>

Notes:
  - Only absolute http/https URLs are supported in v00.01.01
  - Other actions (+c, +b, +list, +register) are not implemented yet
"@
    exit 64
}

function Is-AbsoluteHttpUrl {
    param([string] $Url)
    return ($Url -match '^(?i)https?://')
}

function Add-AliasMapping {
    param(
        [string] $Alias,
        [string] $Url
    )

    if ([string]::IsNullOrWhiteSpace($Alias)) {
        Write-Error "Alias must not be empty."
        exit 2
    }
    if ($Alias.StartsWith('+')) {
        Write-Error "Alias must not start with '+'."
        exit 2
    }
    if ($Alias -match '\s') {
        Write-Error "Alias must not contain whitespace."
        exit 2
    }
    if (-not (Is-AbsoluteHttpUrl -Url $Url)) {
        Write-Error "Only absolute http/https URLs are supported in v00.01.01. Received: $Url"
        exit 2
    }

    $aliases = Load-Aliases
    $aliases[$Alias] = $Url
    $path = Save-Aliases -Aliases $aliases
    Write-Host "Saved alias '$Alias' -> '$Url' at '$path'"
}

function Resolve-AliasOrFail {
    param([string] $Alias)
    $aliases = Load-Aliases
    if (-not $aliases.ContainsKey($Alias)) {
        Write-Error "Alias not found: $Alias"
        exit 3
    }
    return [string]$aliases[$Alias]
}

# Entry
if (-not $ArgList -or $ArgList.Length -eq 0) {
    Show-UsageAndExit
}

$first = $ArgList[0]

switch ($true) {
    # Explicit +n action
    { $first -eq '+n' } {
        if ($ArgList.Length -lt 2) { Show-UsageAndExit }
        $alias = $ArgList[1]
        $url = Resolve-AliasOrFail -Alias $alias
        # Print URL only
        Write-Output $url
        exit 0
    }

    # Unknown +action placeholders (not implemented yet)
    { $first -like '+*' } {
        Write-Error "Action '$first' is not implemented in v00.01.01"
        exit 10
    }

    # Add alias: <alias> <url>
    { $ArgList.Length -eq 2 } {
        $alias = $ArgList[0]
        $url = $ArgList[1]
        Add-AliasMapping -Alias $alias -Url $url
        exit 0
    }

    # Default action: display URL (+n) for <alias>
    { $ArgList.Length -eq 1 } {
        $alias = $ArgList[0]
        $url = Resolve-AliasOrFail -Alias $alias
        Write-Output $url
        exit 0
    }

    default {
        Show-UsageAndExit
    }
}


