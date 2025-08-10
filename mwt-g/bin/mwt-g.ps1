#!/usr/bin/env pwsh

<#!
.SYNOPSIS
  mwt-g: Minimal URL alias tool (v00.01.01)

.DESCRIPTION
  Stores simple alias -> URL mappings in TOML and resolves them.
  Storage precedence when reading:
    1) Project-local:
       - Aliases:       ./mwt-g/aliases.toml
       - Configuration: ./mwt-g/configuration.toml
    2) User-level:
       - Aliases:       ~/.config/mwt-g/aliases.toml
       - Configuration: ~/.config/mwt-g/configuration.toml

  Writing:
    - Prefers project-local files. Creates ./mwt-g/*.toml if missing.

.USAGE
  Add alias:
    mwt-g.ps1 <alias> <absolute-url>

  Display URL (+n is default action):
    mwt-g.ps1 <alias>
    mwt-g.ps1 +n <alias>

  Notes:
    - Only absolute http/https URLs are supported in v00.01.01
    - Other actions (+c, +b, +register) are not implemented yet
!#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $ArgList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:QuietMode = $false
$script:OverwriteMode = 'always'
 

function Get-ProjectAliasesPath {
    $projectDir = Join-Path -Path (Get-Location) -ChildPath 'mwt-g'
    return Join-Path -Path $projectDir -ChildPath 'aliases.toml'
}

function Get-UserAliasesPath {
    $homeDir = $env:HOME
    if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = $env:USERPROFILE }
    if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = [Environment]::GetFolderPath('UserProfile') }
    $userConfigDir = Join-Path -Path $homeDir -ChildPath '.config/mwt-g'
    return Join-Path -Path $userConfigDir -ChildPath 'aliases.toml'
}

function Get-ProjectConfigPath {
    $projectDir = Join-Path -Path (Get-Location) -ChildPath 'mwt-g'
    return Join-Path -Path $projectDir -ChildPath 'configuration.toml'
}

function Get-UserConfigPath {
    $homeDir = $env:HOME
    if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = $env:USERPROFILE }
    if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = [Environment]::GetFolderPath('UserProfile') }
    $userConfigDir = Join-Path -Path $homeDir -ChildPath '.config/mwt-g'
    return Join-Path -Path $userConfigDir -ChildPath 'configuration.toml'
}

function Get-EffectiveConfigPathForWrite {
    $projectPath = Get-ProjectConfigPath
    $projectDir = Split-Path -Parent -Path $projectPath
    if (-not (Test-Path -LiteralPath $projectDir)) {
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
    }
    return $projectPath
}

function Ensure-ConfigDefaultFile {
    $projectConfig = Get-EffectiveConfigPathForWrite
    if (-not (Test-Path -LiteralPath $projectConfig)) {
        $default = @(
            '# mwt-g configuration',
            '# Default values used when not overridden by +flags',
            'overwrite_alias = "always"',
            'quiet = false'
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $projectConfig -Value $default -Encoding UTF8
    }
}

function Get-EffectiveAliasesPathForRead {
    $projectPath = Get-ProjectAliasesPath
    $userPath = Get-UserAliasesPath
    if (Test-Path -LiteralPath $projectPath) { return $projectPath }
    if (Test-Path -LiteralPath $userPath)    { return $userPath }
    return $null
}

function Get-EffectiveAliasesPathForWrite {
    $projectPath = Get-ProjectAliasesPath
    $projectDir = Split-Path -Parent -Path $projectPath
    if (-not (Test-Path -LiteralPath $projectDir)) {
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
    }
    return $projectPath
}

function Load-Aliases {
    $path = Get-EffectiveAliasesPathForRead
    if (-not $path) { return @{} }
    $lines = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
    if ($null -eq $lines) { return @{} }
    $aliases = @{}
    foreach ($line in $lines) {
        $trim = ($line.Trim())
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        if ($trim.StartsWith('#')) { continue }
        $eqIndex = $trim.IndexOf('=')
        if ($eqIndex -lt 1) { continue }
        $key = $trim.Substring(0, $eqIndex).Trim()
        $val = $trim.Substring($eqIndex + 1).Trim()
        # strip quotes if present
        if ($val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Trim('"') }
        elseif ($val.StartsWith("'") -and $val.EndsWith("'")) { $val = $val.Trim("'") }
        if (-not [string]::IsNullOrWhiteSpace($key)) { $aliases[$key] = [string]$val }
    }
    return $aliases
}

function Save-Aliases {
    param([hashtable] $Aliases)
    $path = Get-EffectiveAliasesPathForWrite
    $content = "# Aliases" + [Environment]::NewLine
    foreach ($key in ($Aliases.Keys | Sort-Object)) {
        $valueEscaped = ($Aliases[$key] -replace '"','`"')
        $content += ('{0} = "{1}"' -f $key, $valueEscaped) + [Environment]::NewLine
    }
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    return $path
}

function Load-Config {
    $path = $null
    $proj = Get-ProjectConfigPath
    $user = Get-UserConfigPath
    if (Test-Path -LiteralPath $proj) { $path = $proj }
    elseif (Test-Path -LiteralPath $user) { $path = $user }

    $config = @{ overwrite_alias = 'always'; quiet = $false }
    if (-not $path) { return $config }
    $lines = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
    if ($null -eq $lines) { return $config }
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        if ($trim.StartsWith('#')) { continue }
        $eqIndex = $trim.IndexOf('=')
        if ($eqIndex -lt 1) { continue }
        $key = $trim.Substring(0, $eqIndex).Trim()
        $val = $trim.Substring($eqIndex + 1).Trim()
        if ($val -match '^(true|false)$') {
            $valParsed = [bool]::Parse($val)
        }
        else {
            if ($val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Trim('"') }
            elseif ($val.StartsWith("'") -and $val.EndsWith("'")) { $val = $val.Trim("'") }
            $valParsed = $val
        }
        $config[$key] = $valParsed
    }
    return $config
}

function Write-Info {
    param([string] $Message)
    if (-not $script:QuietMode) {
        Write-Host $Message
    }
}

function Show-UsageAndExit {
    Write-Host @"
Usage:
  Add alias:
    mwt-g.ps1 <alias> <absolute-url>

  Display URL (+n is default):
    mwt-g.ps1 <alias>
    mwt-g.ps1 +n <alias>

  List aliases:
    mwt-g.ps1 +list

Notes:
  - Only absolute http/https URLs are supported in v00.01.01
  - Other actions (+c, +b, +register) are not implemented yet
  - Flags:
      +quiet                       Suppress non-essential output
      +overwrite-alias <mode>      Mode is one of: always | never | ask
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
        [string] $Url,
        [ValidateSet('always','never','ask')]
        [string] $Overwrite = 'always'
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

    $config = Load-Config
    if ($PSBoundParameters.ContainsKey('Overwrite') -and $Overwrite) {
        $effectiveOverwrite = $Overwrite
    } else {
        $effectiveOverwrite = [string]$config['overwrite_alias']
    }
    $aliases = Load-Aliases
    if ($aliases.ContainsKey($Alias)) {
        switch ($effectiveOverwrite) {
            'never' {
                Write-Info "Alias '$Alias' already exists. Skipping due to +overwrite-alias never."
                return
            }
            'ask' {
                # Non-interactive default: do not overwrite
                Write-Info "Alias '$Alias' exists. +overwrite-alias ask -> not overwriting in non-interactive mode."
                return
            }
            default { }
        }
    }
    $aliases[$Alias] = $Url
    $path = Save-Aliases -Aliases $aliases
    Write-Info "Saved alias '$Alias' -> '$Url' at '$path'"
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

function Invoke-CurlFetch {
    param([string] $Alias)
    $url = Resolve-AliasOrFail -Alias $Alias

    $curlExe = Get-Command curl -CommandType Application -ErrorAction SilentlyContinue
    if ($curlExe) {
        if (-not $script:QuietMode) { Write-Info "curl -sSL $url" }
        & $curlExe.Path -sSL --retry 2 --max-time 15 --connect-timeout 5 --fail-with-body $url
        return
    }

    # Fallback to PowerShell's web client
    if (-not $script:QuietMode) { Write-Info "Invoke-WebRequest $url" }
    try {
        $resp = Invoke-WebRequest -Uri $url -Method Get -MaximumRedirection 5 -TimeoutSec 15 -ErrorAction Stop
        if ($null -ne $resp -and $null -ne $resp.Content) { Write-Output $resp.Content }
    }
    catch {
        Write-Error "Fetch failed: $($_.Exception.Message)"
        exit 12
    }
}

# Entry
if (-not $ArgList -or $ArgList.Length -eq 0) {
    Show-UsageAndExit
}

$null = Ensure-ConfigDefaultFile

$first = $ArgList[0]

switch ($true) {
    # Silent mode
    { $first -eq '+quiet' } {
        $script:QuietMode = $true
        if ($ArgList.Length -lt 2) { Show-UsageAndExit }
        $ArgList = $ArgList[1..($ArgList.Length-1)]
        $first = $ArgList[0]
        # fallthrough to process new $first
    }

    # Overwrite mode prefix
    { $first -eq '+overwrite-alias' } {
        if ($ArgList.Length -lt 2) { Write-Error "+overwrite-alias requires a mode: always|never|ask"; exit 11 }
        $mode = $ArgList[1].ToLowerInvariant()
        if (@('always','never','ask') -notcontains $mode) { Write-Error "Invalid overwrite mode: $mode"; exit 11 }
        $script:OverwriteMode = $mode
        if ($ArgList.Length -lt 3) { Show-UsageAndExit }
        $ArgList = $ArgList[2..($ArgList.Length-1)]
        $first = $ArgList[0]
        # fallthrough to process new $first
    }

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
        if ($first -eq '+list') {
            $aliases = Load-Aliases
            if ($aliases.Count -eq 0) { return }
            $aliases.Keys | Sort-Object | ForEach-Object {
                $k = $_
                $v = [string]$aliases[$k]
                Write-Output "$k $v"
            }
            exit 0
        }
        if ($first -eq '+c') {
            if ($ArgList.Length -lt 2) { Show-UsageAndExit }
            $alias = $ArgList[1]
            Invoke-CurlFetch -Alias $alias
            exit 0
        }
        Write-Error "Action '$first' is not implemented in v00.01.01"
        exit 10
    }

    # Add alias: <alias> <url>
    { $ArgList.Length -eq 2 } {
        $alias = $ArgList[0]
        $url = $ArgList[1]
        $overwrite = if ($script:OverwriteMode) { $script:OverwriteMode } else { 'always' }
        Add-AliasMapping -Alias $alias -Url $url -Overwrite $overwrite
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


