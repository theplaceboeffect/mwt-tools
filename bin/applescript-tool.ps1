#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Simple arg parsing to avoid requiring advanced function context
$ClearCache = $false
$Recompile = $false
$OpenAlias = $null
$VerboseOutput = $false
$TestScript = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    switch -Regex ($a) {
        '^-Recompile$' { $Recompile = $true }
        '^-ClearCache$' { $ClearCache = $true }
        '^-OpenAlias$' {
            if ($i + 1 -ge $args.Count) { Write-Error 'Missing value after -OpenAlias'; exit 64 }
            $OpenAlias = [string]$args[$i + 1]
            $i++
        }
        '^-VerboseOutput$' { $VerboseOutput = $true }
        '^-TestScript$' { $TestScript = $true }
        '^-h$|^--help$|^-Help$' { Show-Usage; exit 0 }
        default { }
    }
}

function Write-Info([string]$msg) { if ($VerboseOutput) { Write-Host $msg } }

function Show-Usage {
    Write-Host @"
Usage:
  pwsh bin/applescript-tool.ps1 -Recompile [-VerboseOutput]
  pwsh bin/applescript-tool.ps1 -ClearCache [-VerboseOutput]
  pwsh bin/applescript-tool.ps1 -OpenAlias <alias> [-VerboseOutput]
  pwsh bin/applescript-tool.ps1 -TestScript [-OpenAlias <alias>] [-VerboseOutput]

Notes:
  - macOS only. Requires osacompile, open, and lsregister.
  - -OpenAlias uses 'open goto://<alias>'.
"@
}

if (-not $IsMacOS) {
    Write-Error 'This tool is supported on macOS only.'
    exit 2
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

$applescriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'mwt-g-url-handler.applescript'
$appPath = Join-Path -Path $PSScriptRoot -ChildPath 'mwt-g-url-handler.app'

if (-not ($ClearCache -or $Recompile -or $OpenAlias -or $TestScript)) {
    Show-Usage
    exit 64
}

if ($Recompile) {
    $osacompile = Resolve-CommandPathOrName 'osacompile'
    if (-not $osacompile) { Write-Error "osacompile not found"; exit 11 }
    if (-not (Test-Path -LiteralPath $applescriptPath)) { Write-Error "AppleScript source not found: $applescriptPath"; exit 12 }
    Write-Info "Compiling AppleScript to $appPath"
    & $osacompile -o $appPath $applescriptPath | Out-Null
    if (-not (Test-Path -LiteralPath $appPath)) { Write-Error "Compilation did not produce app: $appPath"; exit 13 }
    # Force-register with LaunchServices
    $openExe = Resolve-CommandPathOrName 'open'
    if ($openExe) { & $openExe $appPath | Out-Null }
}

if ($ClearCache) {
    $lsreg = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    if (-not (Test-Path -LiteralPath $lsreg)) { Write-Error "lsregister not found at $lsreg"; exit 21 }
    Write-Info 'Clearing LaunchServices registration cache (this may take a moment)'
    & $lsreg -kill -r -domain local -domain system -domain user | Out-Null

    # Re-register our app bundle to ensure the custom URL scheme is immediately recognized
    if (Test-Path -LiteralPath $appPath) {
        Write-Info "Re-registering app with LaunchServices: $appPath"
        & $lsreg -f -R $appPath | Out-Null
        $openExe = Resolve-CommandPathOrName 'open'
        if ($openExe) { & $openExe $appPath | Out-Null }
    }
    else {
        Write-Info "App bundle not found at $appPath; run -Recompile to build it before registering."
    }
}

if ($OpenAlias) {
    $openExe = Resolve-CommandPathOrName 'open'
    if (-not $openExe) { Write-Error "open command not found"; exit 31 }
    $uri = 'goto://{0}' -f $OpenAlias
    Write-Info "open $uri"
    & $openExe $uri | Out-Null
}

if ($TestScript) {
    $osascript = Resolve-CommandPathOrName 'osascript'
    $osacompile = Resolve-CommandPathOrName 'osacompile'
    if (-not $osascript) { Write-Error 'osascript not found'; exit 41 }
    if (-not $osacompile) { Write-Error 'osacompile not found'; exit 42 }
    if (-not (Test-Path -LiteralPath $applescriptPath)) { Write-Error "AppleScript source not found: $applescriptPath"; exit 43 }
    $aliasToUse = if ($OpenAlias) { $OpenAlias } else { 'y' }
    $tempScpt = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("mwt-g-url-handler-{0}.scpt" -f ([guid]::NewGuid().ToString('N')))
    Write-Info "Compiling source to temporary script: $tempScpt"
    & $osacompile -o $tempScpt $applescriptPath | Out-Null
    if (-not (Test-Path -LiteralPath $tempScpt)) { Write-Error "Failed to compile temporary script: $tempScpt"; exit 44 }
    $expr = 'tell script (load script POSIX file "{0}") to open location "goto://{1}"' -f $tempScpt, $aliasToUse
    Write-Info "osascript -e [open location goto://$aliasToUse via compiled temp]"
    try { & $osascript -e $expr | Out-Null } finally {
        try { Remove-Item -LiteralPath $tempScpt -Force -ErrorAction SilentlyContinue } catch { }
    }
}

exit 0


