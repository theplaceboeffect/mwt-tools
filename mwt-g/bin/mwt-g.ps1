#!/usr/bin/env pwsh

<#!
.SYNOPSIS
  mwt-g: Minimal URL alias tool (v00.01.03)

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
    - Aliases: if ./mwt-g exists, write project-local; otherwise write to ~/.config/mwt-g/aliases.toml.
    - Configuration: on first run, if no project-local config exists at ./mwt-g/configuration.toml,
      creates ~/.config/mwt-g/configuration.toml.

.USAGE
  Add alias:
    mwt-g.ps1 <alias> <absolute-url>

  Display URL (+n is default action):
    mwt-g.ps1 <alias>
    mwt-g.ps1 +n <alias>

  Fetch via curl (+c):
    mwt-g.ps1 +c <alias>

  Open in default browser (+b):
    mwt-g.ps1 +b <alias>

  Notes:
    - Only absolute http/https URLs are supported in this version
    - +c and +b are implemented; +register (macOS) is implemented in v00.01.05
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
$script:TracePaths = $false

function Resolve-HomeDirectory {
    $candidates = @()
    if ($env:HOME)        { $candidates += [pscustomobject]@{ Source = 'HOME';        Path = [string]$env:HOME } }
    
    if ($env:USERPROFILE) { $candidates += [pscustomobject]@{ Source = 'USERPROFILE'; Path = [string]$env:USERPROFILE } }
    
    $dotNetUser = [Environment]::GetFolderPath('UserProfile')
    if (-not [string]::IsNullOrWhiteSpace($dotNetUser)) {
        $candidates += [pscustomobject]@{ Source = '.NET UserProfile'; Path = [string]$dotNetUser }
    }

    $selected = $null
    foreach ($cand in $candidates) { if (-not [string]::IsNullOrWhiteSpace($cand.Path)) { $selected = $cand; break } }
    if (-not $selected) { $selected = [pscustomobject]@{ Source = '.NET UserProfile'; Path = [string]$dotNetUser } }

    $needsSanitize = $false
    $isTestRun = ($env:MWT_G_TEST_RUN_ID -and -not [string]::IsNullOrWhiteSpace($env:MWT_G_TEST_RUN_ID))
    if (-not $isTestRun -and $selected -and $selected.Path) {
        $lower = $selected.Path.ToLowerInvariant()
        if ($lower -match 'mwt-g/testruns') { $needsSanitize = $true }
    }
    if ($needsSanitize -and $dotNetUser -and $selected.Path -ne $dotNetUser) {
        if ($script:TracePaths) { Write-Info ("[paths] HOME sanitized from {0}: {1} -> {2}" -f $selected.Source, $selected.Path, $dotNetUser) }
        $selected = [pscustomobject]@{ Source = '.NET UserProfile'; Path = [string]$dotNetUser }
    }

    if ($script:TracePaths) {
        foreach ($cand in $candidates) { Write-Info ("[paths] HOME candidate {0}: {1}" -f $cand.Source, $cand.Path) }
        Write-Info ("[paths] HOME selected: {0} ({1})" -f $selected.Path, $selected.Source)
    }
    return [string]$selected.Path
}

function Get-ProjectAliasesPath {
    $projectDir = Join-Path -Path (Get-Location) -ChildPath 'mwt-g'
    return Join-Path -Path $projectDir -ChildPath 'aliases.toml'
}

function Get-UserAliasesPath {
    $homeDir = Resolve-HomeDirectory
    $userConfigDir = Join-Path -Path $homeDir -ChildPath '.config/mwt-g'
    return Join-Path -Path $userConfigDir -ChildPath 'aliases.toml'
}

function Get-ProjectConfigPath {
    $projectDir = Join-Path -Path (Get-Location) -ChildPath 'mwt-g'
    return Join-Path -Path $projectDir -ChildPath 'configuration.toml'
}

function Get-UserConfigPath {
    $homeDir = Resolve-HomeDirectory
    $userConfigDir = Join-Path -Path $homeDir -ChildPath '.config/mwt-g'
    return Join-Path -Path $userConfigDir -ChildPath 'configuration.toml'
}

function Get-LocalConfigPath { }

function Ensure-ConfigDefaultFile {
    # On startup, prefer an existing project-local config at ./mwt-g/configuration.toml.
    # If none exists, ensure a user-level config exists at ~/.config/mwt-g/configuration.toml.
    $projectConfig = Get-ProjectConfigPath
    if (Test-Path -LiteralPath $projectConfig) { return }

    $userConfig = Get-UserConfigPath
    $userDir = Split-Path -Parent -Path $userConfig
    if (-not (Test-Path -LiteralPath $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $userConfig)) {
        $default = @(
            '# mwt-g configuration',
            '# Default values used when not overridden by +flags',
            'overwrite_alias = "always"',
            'quiet = false'
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $userConfig -Value $default -Encoding UTF8
        if ($script:TracePaths) { Write-Info ("[paths] Created user config: {0}" -f $userConfig) }
    }
}

function Get-EffectiveAliasesPathForRead {
    $projectPath = Get-ProjectAliasesPath
    $userPath = Get-UserAliasesPath
    $projExists = Test-Path -LiteralPath $projectPath
    $userExists = Test-Path -LiteralPath $userPath
    if ($script:TracePaths) {
        Write-Info ("[paths] Aliases candidates:\n  project: {0} (exists={1})\n  user:    {2} (exists={3})" -f $projectPath, $projExists, $userPath, $userExists)
    }
    if ($projExists) { if ($script:TracePaths) { Write-Info ("[paths] Aliases selected: {0}" -f $projectPath) } return $projectPath }
    if ($userExists) { if ($script:TracePaths) { Write-Info ("[paths] Aliases selected: {0}" -f $userPath) } return $userPath }
    if ($script:TracePaths) { Write-Info "[paths] Aliases selected: <none> (no file found)" }
    return $null
}

function Get-EffectiveAliasesPathForWrite {
    $projectPath = Get-ProjectAliasesPath
    $projectDir = Split-Path -Parent -Path $projectPath
    # Prefer HOME when ./mwt-g does not exist
    if (Test-Path -LiteralPath $projectDir) { if ($script:TracePaths) { Write-Info ("[paths] Aliases write target: {0}" -f $projectPath) } return $projectPath }
    $userPath = Get-UserAliasesPath
    $userDir = Split-Path -Parent -Path $userPath
    if (-not (Test-Path -LiteralPath $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
    if ($script:TracePaths) { Write-Info ("[paths] Aliases write target: {0}" -f $userPath) }
    return $userPath
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
    $projExists  = Test-Path -LiteralPath $proj
    $userExists  = Test-Path -LiteralPath $user
    if ($script:TracePaths) {
        Write-Info ("[paths] Config candidates:\n  project: {0} (exists={1})\n  user:    {2} (exists={3})" -f $proj, $projExists, $user, $userExists)
    }
    if ($projExists) { $path = $proj }
    elseif ($userExists) { $path = $user }
    if ($script:TracePaths) { Write-Info ("[paths] Config selected: {0}" -f ($path ? $path : '<none>')) }

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

  Fetch via curl (+c):
    mwt-g.ps1 +c <alias>

  Open in default browser (+b):
    mwt-g.ps1 +b <alias>

  List aliases:
    mwt-g.ps1 +list

  Register URL scheme handler (+register):
    mwt-g.ps1 +register

Notes:
  - Only absolute http/https URLs are supported
  - Flags:
      +quiet                       Suppress non-essential output
      +overwrite-alias <mode>      Mode is one of: always | never | ask
      +paths                       Show where aliases/config are searched and selected
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
        Write-Output "Alias '$Alias' not found. Use '+list' to view available aliases or add one with: mwt-g.ps1 <alias> <url>"
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
        $curlPath = if ($curlExe | Get-Member -Name Path -MemberType NoteProperty,Property -ErrorAction SilentlyContinue) { $curlExe.Path } else { 'curl' }
        & $curlPath -sSL --retry 2 --max-time 15 --connect-timeout 5 --fail-with-body $url
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

function Invoke-OpenBrowser {
    param([string] $Alias)
    $url = Resolve-AliasOrFail -Alias $Alias

    # If in test/dry-run mode, emit the URL and do not launch
    if ($env:MWT_G_BROWSER_DRYRUN) {
        Write-Output $url
        return
    }

    # Allow overriding the browser command for testing or customization
    $customCmd = $env:MWT_G_BROWSER_CMD
    if ($customCmd) {
        if (-not $script:QuietMode) { Write-Info "$customCmd $url" }
        & $customCmd $url
        return
    }

    # Default behavior by platform
    if ($IsWindows) {
        if (-not $script:QuietMode) { Write-Info "Start-Process $url" }
        Start-Process -FilePath $url | Out-Null
        return
    }
    # macOS
    $openCmd = Get-Command open -ErrorAction SilentlyContinue
    if ($openCmd) {
        if (-not $script:QuietMode) { Write-Info "open $url" }
        $openPath = if ($openCmd | Get-Member -Name Path -MemberType NoteProperty,Property -ErrorAction SilentlyContinue) { $openCmd.Path } else { 'open' }
        & $openPath $url | Out-Null
        return
    }
    # Linux/other
    $xdgCmd = Get-Command xdg-open -ErrorAction SilentlyContinue
    if ($xdgCmd) {
        if (-not $script:QuietMode) { Write-Info "xdg-open $url" }
        $xdgPath = if ($xdgCmd | Get-Member -Name Path -MemberType NoteProperty,Property -ErrorAction SilentlyContinue) { $xdgCmd.Path } else { 'xdg-open' }
        & $xdgPath $url | Out-Null
        return
    }

    Write-Error "No suitable method found to open URL in browser. Tried: custom cmd, Start-Process, open, xdg-open."
    exit 13
}

function Register-UrlSchemeHandler {
    # macOS-only implementation for v00.01.05
    if (-not $IsMacOS) {
        Write-Error "+register is currently supported on macOS only."
        exit 20
    }

    function Resolve-CommandPathOrName {
        param([string]$Name)
        $ci = Get-Command $Name -ErrorAction SilentlyContinue
        if (-not $ci) { return $null }
        if ($ci | Get-Member -Name Path -MemberType NoteProperty,Property -ErrorAction SilentlyContinue) {
            if ($ci.Path) { return [string]$ci.Path }
        }
        if ($ci | Get-Member -Name Source -MemberType NoteProperty,Property -ErrorAction SilentlyContinue) {
            if ($ci.Source) { return [string]$ci.Source }
        }
        return [string]$Name
    }

    $osacompileExe = Resolve-CommandPathOrName 'osacompile'
    if (-not $osacompileExe) {
        Write-Error "Required tool 'osacompile' not found."
        exit 21
    }

    $plistBuddy = '/usr/libexec/PlistBuddy'
    if (-not (Test-Path -LiteralPath $plistBuddy)) {
        Write-Error "Required tool PlistBuddy not found at $plistBuddy"
        exit 22
    }

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $scriptDir  = Split-Path -Parent -Path $scriptPath
    $appName    = 'mwt-g-url-handler.app'
    $appPath    = Join-Path -Path $scriptDir -ChildPath $appName
    $contentsPlist = Join-Path -Path $appPath -ChildPath 'Contents/Info.plist'

    if (Test-Path -LiteralPath $appPath) {
        try { Remove-Item -LiteralPath $appPath -Recurse -Force -ErrorAction Stop } catch { }
    }

    $applescriptPath = Join-Path -Path $scriptDir -ChildPath 'mwt-g-url-handler.applescript'
    $projectRoot = Split-Path -Parent -Path (Split-Path -Parent -Path $scriptPath)

    ## Copy from mwt-g-url-handler.applescript.template
    $appleScript = @"
on open location theURL
  set urlText to (theURL as text)
  try
    if urlText starts with "goto://" then
      set delimPos to offset of "://" in urlText
      set theAlias to text (delimPos + 3) thru -1 of urlText
      set projectDirQ to quoted form of "/Users/mwt/projects/mwt-tools/mwt-g"
      set ps1PathQ to quoted form of "/Users/mwt/projects/mwt-tools/mwt-g/bin/mwt-g.ps1"
      set aliasQ to quoted form of theAlias
      set shellCmd to "cd " & projectDirQ & " && /usr/bin/env pwsh -NoProfile -File " & ps1PathQ & " +b " & aliasQ 
      # display dialog ("About to run:\n" & shellCmd) buttons {"OK"} default button "OK" with icon note
      do shell script shellCmd
    end if
  on error errMsg number errNum
    display dialog ("ERROR: " & errMsg & " (" & errNum & ")") buttons {"OK"} default button "OK" with icon stop
  end try
end open location
"@
    Set-Content -LiteralPath $applescriptPath -Value $appleScript -Encoding UTF8

    & $osacompileExe -o $appPath $applescriptPath | Out-Null

    # Augment Info.plist with URL scheme declaration
    & $plistBuddy -c 'Add :CFBundleIdentifier string com.mwt.mwt-g.urlhandler' $contentsPlist 2>$null
    & $plistBuddy -c 'Add :CFBundleURLTypes array' $contentsPlist 2>$null
    & $plistBuddy -c 'Add :CFBundleURLTypes:0 dict' $contentsPlist 2>$null
    & $plistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' $contentsPlist 2>$null
    & $plistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string goto' $contentsPlist 2>$null

    # Launch once to register with LaunchServices
    $openExe = Resolve-CommandPathOrName 'open'
    if (-not $openExe) { Write-Error "macOS 'open' command not found"; exit 23 }
    & $openExe $appPath | Out-Null
    Start-Sleep -Milliseconds 500

    Write-Info "+register: Installed URL handler for scheme 'goto' at $appPath targeting $scriptPath"
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

    # Trace paths
    { $first -eq '+paths' } {
        $script:TracePaths = $true
        if ($ArgList.Length -lt 2) { Show-UsageAndExit }
        $ArgList = $ArgList[1..($ArgList.Length-1)]
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
        if ($first -eq '+b') {
            if ($ArgList.Length -lt 2) { Show-UsageAndExit }
            $alias = $ArgList[1]
            Invoke-OpenBrowser -Alias $alias
            exit 0
        }
        if ($first -eq '+register') {
            Register-UrlSchemeHandler
            exit 0
        }
        Write-Error "Action '$first' is not implemented"
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


