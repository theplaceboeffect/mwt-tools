# Review and execute implementation tasks
_Exported on 8/10/2025 at 01:33:47 CDT from Cursor (1.4.3)_

---

**User**

Review prompt v00.01.md and execute all implementation tasks marked with [R]

---

**Cursor**

Quick status: I’m going to open `mwt-g/prompts/v00.01.md` to find all tasks marked with [R], then implement them in the appropriate files under `mwt-g/`. I'll also peek at `mwt-g/README.md` to understand how tests are run on macOS. Proceeding to read the files now.

Plan: I’ll scan the core script `mwt-g/bin/mwt-g.ps1` and the test files to see how options are currently implemented, then add support for `+b` (open in browser) alongside existing `+n` behavior. After implementing, I’ll run the test suite from `mwt-g/` using PowerShell 7 via zsh, and then update the prompt to mark the task complete if tests pass. Proceeding to read the relevant files in parallel.

Status: I’m going to implement `+b` in `mwt-g/bin/mwt-g.ps1`, add three Pester tests for it in `mwt-g/tests/test-pester.Tests.ps1` using a dry-run env var to avoid actually launching a browser, update usage/README, then run the test suite from `mwt-g/`. Proceeding with edits now.

Status: Implementing +b in `mwt-g/bin/mwt-g.ps1`, adding an `Invoke-OpenBrowser` function with dry-run and custom command support, updating usage text, then adding three Pester tests to `mwt-g/tests/test-pester.Tests.ps1`. After edits, I’ll run the full test suite from `mwt-g/`.

```powershell
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

  Fetch via curl (+c):
    mwt-g.ps1 +c <alias>

  Open in default browser (+b):
    mwt-g.ps1 +b <alias>

  Notes:
    - Only absolute http/https URLs are supported in this version
    - +c and +b are implemented; +register is not implemented yet
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

  Fetch via curl (+c):
    mwt-g.ps1 +c <alias>

  Open in default browser (+b):
    mwt-g.ps1 +b <alias>

  List aliases:
    mwt-g.ps1 +list

Notes:
  - Only absolute http/https URLs are supported
  - +register is not implemented yet
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
        & $openCmd.Path $url | Out-Null
        return
    }
    # Linux/other
    $xdgCmd = Get-Command xdg-open -ErrorAction SilentlyContinue
    if ($xdgCmd) {
        if (-not $script:QuietMode) { Write-Info "xdg-open $url" }
        & $xdgCmd.Path $url | Out-Null
        return
    }

    Write-Error "No suitable method found to open URL in browser. Tried: custom cmd, Start-Process, open, xdg-open."
    exit 13
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
        if ($first -eq '+b') {
            if ($ArgList.Length -lt 2) { Show-UsageAndExit }
            $alias = $ArgList[1]
            Invoke-OpenBrowser -Alias $alias
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



```

```powershell
*** Begin Patch
*** Update File: /Users/mwt/projects/mwt-tools/mwt-g/tests/test-pester.Tests.ps1
@@
 Describe 'mwt-g core behaviors [T0000]' {
@@
     It 'performs fetch with +c and exits 0 [T0009]' {
@@
         $LASTEXITCODE | Should -Be 0
     }
+
+    It 'opens in browser with +b via dry-run mode [T0013]' {
+        $alias = 'gb'
+        $url = 'https://example.com/b'
+        Push-Location $script:CurrentTestDir
+        try {
+            & $script:CurrentToolPath '+quiet' $alias $url | Out-Null
+            $env:MWT_G_BROWSER_DRYRUN = '1'
+            try {
+                (& $script:CurrentToolPath '+b' $alias) | Should -Be $url
+            } finally {
+                Remove-Item Env:MWT_G_BROWSER_DRYRUN -ErrorAction SilentlyContinue
+            }
+        }
+        finally { Pop-Location }
+    }
+
+    It 'uses custom browser command when MWT_G_BROWSER_CMD is set [T0014]' {
+        $alias = 'gb2'
+        $url = 'https://example.com/b2'
+        Push-Location $script:CurrentTestDir
+        try {
+            & $script:CurrentToolPath '+quiet' $alias $url | Out-Null
+            $env:MWT_G_BROWSER_CMD = (Get-Command echo).Path
+            try {
+                $out = & $script:CurrentToolPath '+b' $alias
+                # echo outputs the URL on most platforms
+                @($out) -contains $url | Should -BeTrue
+            } finally {
+                Remove-Item Env:MWT_G_BROWSER_CMD -ErrorAction SilentlyContinue
+            }
+        }
+        finally { Pop-Location }
+    }
+
+    It 'errors when +b on unknown alias [T0015]' {
+        Push-Location $script:CurrentTestDir
+        try { { & $script:CurrentToolPath '+b' 'nope' | Out-Null } | Should -Throw }
+        finally { Pop-Location }
+    }
 }
*** End Patch
```

```powershell
#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'mwt-g core behaviors [T0000]' {
    BeforeAll {
        # Place testruns under the mwt-g project directory
        $script:SourceProjectDir = Split-Path -Parent -Path $PSScriptRoot  # repo/mwt-g
        $runId = if ($env:MWT_G_TEST_RUN_ID) { $env:MWT_G_TEST_RUN_ID } else { (Get-Date -Format 'yyyyMMdd-HHmmss') }
        $script:TestRoot = Join-Path -Path $script:SourceProjectDir -ChildPath (Join-Path 'testruns' $runId)
        $script:SourceToolPath = Join-Path -Path $script:SourceProjectDir -ChildPath 'bin/mwt-g.ps1'
        if (-not (Test-Path -LiteralPath $script:SourceToolPath)) { throw "Tool not found at $script:SourceToolPath" }
        $script:TestCounter = 0
    }

    BeforeEach {
        $script:TestCounter++
        $id = ('T{0}' -f ($script:TestCounter.ToString('0000')))
        $script:CurrentTestDir = Join-Path -Path $script:TestRoot -ChildPath $id
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:CurrentTestDir 'mwt-g/bin')
        Copy-Item -LiteralPath $script:SourceToolPath -Destination (Join-Path $script:CurrentTestDir 'mwt-g/bin/mwt-g.ps1') -Force

        $script:CurrentToolPath   = Join-Path $script:CurrentTestDir 'mwt-g/bin/mwt-g.ps1'
        $script:CurrentAliases    = Join-Path $script:CurrentTestDir 'mwt-g/aliases.toml'
        $script:CurrentConfig     = Join-Path $script:CurrentTestDir 'mwt-g/configuration.toml'
    }
    It 'adds alias to aliases.toml [T0001]' {
        if (Test-Path -LiteralPath $script:CurrentAliases) { Remove-Item -LiteralPath $script:CurrentAliases -Force }
        $alias = 'g'
        $url = 'https://www.google.com'
        Push-Location $script:CurrentTestDir
        try { & $script:CurrentToolPath '+quiet' $alias $url | Out-Null }
        finally { Pop-Location }
        Test-Path -LiteralPath $script:CurrentAliases | Should -BeTrue
        $text = Get-Content -LiteralPath $script:CurrentAliases -Raw
        $pattern = '(?ms)^\s*g\s*=\s*"https://www\.google\.com"\s*$'
        $text | Should -Match $pattern
    }

    It 'displays URL for alias (default and +n) [T0002]' {
        $alias = 'g'
        $url = 'https://www.google.com'
        Push-Location $script:CurrentTestDir
        try {
            (& $script:CurrentToolPath '+quiet' $alias $url) | Out-Null
            (& $script:CurrentToolPath '+n' $alias) | Should -Be $url
            (& $script:CurrentToolPath $alias) | Should -Be $url
        }
        finally { Pop-Location }
    }

    It 'throws for unknown alias [T0003]' {
        Push-Location $script:CurrentTestDir
        try { { & $script:CurrentToolPath 'gg' | Out-Null } | Should -Throw }
        finally { Pop-Location }
    }

    It 'lists aliases with +list [T0004]' {
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' 'g' 'https://www.google.com' | Out-Null
            $output = & $script:CurrentToolPath '+list'
            @($output | Where-Object { $_ -match '^g\s+https://www\.google\.com$' }).Count | Should -BeGreaterThan 0
        }
        finally { Pop-Location }
    }

    It 'overwrites alias when provided +overwrite-alias always [T0005]' {
        $alias = 'g'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias 'https://www.google.com' | Out-Null
            & $script:CurrentToolPath '+quiet' '+overwrite-alias' 'always' $alias 'https://www.google2.com' | Out-Null
            (& $script:CurrentToolPath $alias) | Should -Be 'https://www.google2.com'
        }
        finally { Pop-Location }
    }

    It 'respects +overwrite-alias never [T0006]' {
        $alias = 'g'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias 'https://www.google2.com' | Out-Null
            & $script:CurrentToolPath '+quiet' '+overwrite-alias' 'never' $alias 'https://www.google3.com' | Out-Null
            (& $script:CurrentToolPath $alias) | Should -Be 'https://www.google2.com'
        }
        finally { Pop-Location }
    }

    It 'produces no output when +quiet is set [T0007]' {
        $alias = 'q'
        $url = 'https://example.com'
        Push-Location $script:CurrentTestDir
        try { $out = & $script:CurrentToolPath '+quiet' $alias $url }
        finally { Pop-Location }
        ($out | Measure-Object).Count | Should -Be 0
    }

    It 'creates configuration.toml with defaults when missing [T0008]' {
        if (Test-Path -LiteralPath $script:CurrentConfig) { Remove-Item -LiteralPath $script:CurrentConfig -Force }
        Push-Location $script:CurrentTestDir
        try { & $script:CurrentToolPath '+quiet' 'cfg' 'https://example.com' | Out-Null }
        finally { Pop-Location }
        Test-Path -LiteralPath $script:CurrentConfig | Should -BeTrue
        $conf = Get-Content -LiteralPath $script:CurrentConfig -Raw
        $conf | Should -Match '(?m)^\s*overwrite_alias\s*=\s*"always"' 
        $conf | Should -Match '(?m)^\s*quiet\s*=\s*false' 
    }

    It 'performs fetch with +c and exits 0 [T0009]' {
        $alias = 'gc'
        $url = 'https://example.com'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias $url | Out-Null
            & $script:CurrentToolPath '+c' $alias | Out-Null
        }
        finally { Pop-Location }
        $LASTEXITCODE | Should -Be 0
    }

    It 'opens in browser with +b via dry-run mode [T0013]' {
        $alias = 'gb'
        $url = 'https://example.com/b'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias $url | Out-Null
            $env:MWT_G_BROWSER_DRYRUN = '1'
            try {
                (& $script:CurrentToolPath '+b' $alias) | Should -Be $url
            } finally {
                Remove-Item Env:MWT_G_BROWSER_DRYRUN -ErrorAction SilentlyContinue
            }
        }
        finally { Pop-Location }
    }

    It 'uses custom browser command when MWT_G_BROWSER_CMD is set [T0014]' {
        $alias = 'gb2'
        $url = 'https://example.com/b2'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias $url | Out-Null
            $env:MWT_G_BROWSER_CMD = (Get-Command echo).Path
            try {
                $out = & $script:CurrentToolPath '+b' $alias
                @($out) -contains $url | Should -BeTrue
            } finally {
                Remove-Item Env:MWT_G_BROWSER_CMD -ErrorAction SilentlyContinue
            }
        }
        finally { Pop-Location }
    }

    It 'errors when +b on unknown alias [T0015]' {
        Push-Location $script:CurrentTestDir
        try { { & $script:CurrentToolPath '+b' 'nope' | Out-Null } | Should -Throw }
        finally { Pop-Location }
    }

    It 'overwrites alias when adding g https://news.google.com/ [T0010]' {
        $alias = 'g'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias 'https://news.google.com/' | Out-Null
            (& $script:CurrentToolPath $alias) | Should -Be 'https://news.google.com/'
        }
        finally { Pop-Location }
    }

    It 'overwrites alias with +overwrite-alias always to https://www.gmail.com [T0011]' {
        $alias = 'g'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias 'https://news.google.com/' | Out-Null
            & $script:CurrentToolPath '+quiet' '+overwrite-alias' 'always' $alias 'https://www.gmail.com' | Out-Null
            (& $script:CurrentToolPath $alias) | Should -Be 'https://www.gmail.com'
        }
        finally { Pop-Location }
    }

    It 'throws for unknown alias gx when visiting [T0012]' {
        Push-Location $script:CurrentTestDir
        try { { & $script:CurrentToolPath 'gx' | Out-Null } | Should -Throw }
        finally { Pop-Location }
    }
}




```

```markdown
# mwt-g

Minimal URL alias helper.

Features:
- Add alias: `pwsh bin/mwt-g.ps1 <alias> <absolute-url>`
- Display URL: `pwsh bin/mwt-g.ps1 <alias>` or `pwsh bin/mwt-g.ps1 +n <alias>`
- Fetch via curl: `pwsh bin/mwt-g.ps1 +c <alias>`
- Open in browser: `pwsh bin/mwt-g.ps1 +b <alias>`

Storage:
- Read precedence: `./mwt-g/settings.json` then `~/.config/mwt-g/settings.json`
- Writes prefer project-local `./mwt-g/settings.json`

Notes:
- Only absolute http/https URLs are supported in this version.
- `+register` is not implemented yet.

Testing:
- From `mwt-g/` run: `pwsh tests/run-tests.ps1`
- This writes `testruns/<runId>/testResults.xml` and runs all Pester tests.



```

```powershell
#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'mwt-g core behaviors [T0000]' {
    BeforeAll {
        # Place testruns under the mwt-g project directory
        $script:SourceProjectDir = Split-Path -Parent -Path $PSScriptRoot  # repo/mwt-g
        $runId = if ($env:MWT_G_TEST_RUN_ID) { $env:MWT_G_TEST_RUN_ID } else { (Get-Date -Format 'yyyyMMdd-HHmmss') }
        $script:TestRoot = Join-Path -Path $script:SourceProjectDir -ChildPath (Join-Path 'testruns' $runId)
        $script:SourceToolPath = Join-Path -Path $script:SourceProjectDir -ChildPath 'bin/mwt-g.ps1'
        if (-not (Test-Path -LiteralPath $script:SourceToolPath)) { throw "Tool not found at $script:SourceToolPath" }
        $script:TestCounter = 0
    }

    BeforeEach {
        $script:TestCounter++
        $id = ('T{0}' -f ($script:TestCounter.ToString('0000')))
        $script:CurrentTestDir = Join-Path -Path $script:TestRoot -ChildPath $id
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:CurrentTestDir 'mwt-g/bin')
        Copy-Item -LiteralPath $script:SourceToolPath -Destination (Join-Path $script:CurrentTestDir 'mwt-g/bin/mwt-g.ps1') -Force

        $script:CurrentToolPath   = Join-Path $script:CurrentTestDir 'mwt-g/bin/mwt-g.ps1'
        $script:CurrentAliases    = Join-Path $script:CurrentTestDir 'mwt-g/aliases.toml'
        $script:CurrentConfig     = Join-Path $script:CurrentTestDir 'mwt-g/configuration.toml'
    }
    It 'adds alias to aliases.toml [T0001]' {
        if (Test-Path -LiteralPath $script:CurrentAliases) { Remove-Item -LiteralPath $script:CurrentAliases -Force }
        $alias = 'g'
        $url = 'https://www.google.com'
        Push-Location $script:CurrentTestDir
        try { & $script:CurrentToolPath '+quiet' $alias $url | Out-Null }
        finally { Pop-Location }
        Test-Path -LiteralPath $script:CurrentAliases | Should -BeTrue
        $text = Get-Content -LiteralPath $script:CurrentAliases -Raw
        $pattern = '(?ms)^\s*g\s*=\s*"https://www\.google\.com"\s*$'
        $text | Should -Match $pattern
    }

    It 'displays URL for alias (default and +n) [T0002]' {
        $alias = 'g'
        $url = 'https://www.google.com'
        Push-Location $script:CurrentTestDir
        try {
            (& $script:CurrentToolPath '+quiet' $alias $url) | Out-Null
            (& $script:CurrentToolPath '+n' $alias) | Should -Be $url
            (& $script:CurrentToolPath $alias) | Should -Be $url
        }
        finally { Pop-Location }
    }

    It 'throws for unknown alias [T0003]' {
        Push-Location $script:CurrentTestDir
        try { { & $script:CurrentToolPath 'gg' | Out-Null } | Should -Throw }
        finally { Pop-Location }
    }

    It 'lists aliases with +list [T0004]' {
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' 'g' 'https://www.google.com' | Out-Null
            $output = & $script:CurrentToolPath '+list'
            @($output | Where-Object { $_ -match '^g\s+https://www\.google\.com$' }).Count | Should -BeGreaterThan 0
        }
        finally { Pop-Location }
    }

    It 'overwrites alias when provided +overwrite-alias always [T0005]' {
        $alias = 'g'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias 'https://www.google.com' | Out-Null
            & $script:CurrentToolPath '+quiet' '+overwrite-alias' 'always' $alias 'https://www.google2.com' | Out-Null
            (& $script:CurrentToolPath $alias) | Should -Be 'https://www.google2.com'
        }
        finally { Pop-Location }
    }

    It 'respects +overwrite-alias never [T0006]' {
        $alias = 'g'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias 'https://www.google2.com' | Out-Null
            & $script:CurrentToolPath '+quiet' '+overwrite-alias' 'never' $alias 'https://www.google3.com' | Out-Null
            (& $script:CurrentToolPath $alias) | Should -Be 'https://www.google2.com'
        }
        finally { Pop-Location }
    }

    It 'produces no output when +quiet is set [T0007]' {
        $alias = 'q'
        $url = 'https://example.com'
        Push-Location $script:CurrentTestDir
        try { $out = & $script:CurrentToolPath '+quiet' $alias $url }
        finally { Pop-Location }
        ($out | Measure-Object).Count | Should -Be 0
    }

    It 'creates configuration.toml with defaults when missing [T0008]' {
        if (Test-Path -LiteralPath $script:CurrentConfig) { Remove-Item -LiteralPath $script:CurrentConfig -Force }
        Push-Location $script:CurrentTestDir
        try { & $script:CurrentToolPath '+quiet' 'cfg' 'https://example.com' | Out-Null }
        finally { Pop-Location }
        Test-Path -LiteralPath $script:CurrentConfig | Should -BeTrue
        $conf = Get-Content -LiteralPath $script:CurrentConfig -Raw
        $conf | Should -Match '(?m)^\s*overwrite_alias\s*=\s*"always"' 
        $conf | Should -Match '(?m)^\s*quiet\s*=\s*false' 
    }

    It 'performs fetch with +c and exits 0 [T0009]' {
        $alias = 'gc'
        $url = 'https://example.com'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias $url | Out-Null
            & $script:CurrentToolPath '+c' $alias | Out-Null
        }
        finally { Pop-Location }
        $LASTEXITCODE | Should -Be 0
    }

    It 'opens in browser with +b via dry-run mode [T0013]' {
        $alias = 'gb'
        $url = 'https://example.com/b'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias $url | Out-Null
            $env:MWT_G_BROWSER_DRYRUN = '1'
            try {
                (& $script:CurrentToolPath '+b' $alias) | Should -Be $url
            } finally {
                Remove-Item Env:MWT_G_BROWSER_DRYRUN -ErrorAction SilentlyContinue
            }
        }
        finally { Pop-Location }
    }

    It 'uses custom browser command when MWT_G_BROWSER_CMD is set [T0014]' {
        $alias = 'gb2'
        $url = 'https://example.com/b2'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias $url | Out-Null
            $echoApp = $null
            try { $echoApp = (Get-Command echo -CommandType Application -ErrorAction SilentlyContinue).Path } catch { }
            if (-not $echoApp) {
                if (Test-Path -LiteralPath '/bin/echo') { $echoApp = '/bin/echo' }
            }
            if (-not $echoApp) { throw 'No external echo found for test' }
            $env:MWT_G_BROWSER_CMD = $echoApp
            try {
                $out = & $script:CurrentToolPath '+b' $alias
                @($out) -contains $url | Should -BeTrue
            } finally {
                Remove-Item Env:MWT_G_BROWSER_CMD -ErrorAction SilentlyContinue
            }
        }
        finally { Pop-Location }
    }

    It 'errors when +b on unknown alias [T0015]' {
        Push-Location $script:CurrentTestDir
        try { { & $script:CurrentToolPath '+b' 'nope' | Out-Null } | Should -Throw }
        finally { Pop-Location }
    }

    It 'overwrites alias when adding g https://news.google.com/ [T0010]' {
        $alias = 'g'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias 'https://news.google.com/' | Out-Null
            (& $script:CurrentToolPath $alias) | Should -Be 'https://news.google.com/'
        }
        finally { Pop-Location }
    }

    It 'overwrites alias with +overwrite-alias always to https://www.gmail.com [T0011]' {
        $alias = 'g'
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' $alias 'https://news.google.com/' | Out-Null
            & $script:CurrentToolPath '+quiet' '+overwrite-alias' 'always' $alias 'https://www.gmail.com' | Out-Null
            (& $script:CurrentToolPath $alias) | Should -Be 'https://www.gmail.com'
        }
        finally { Pop-Location }
    }

    It 'throws for unknown alias gx when visiting [T0012]' {
        Push-Location $script:CurrentTestDir
        try { { & $script:CurrentToolPath 'gx' | Out-Null } | Should -Throw }
        finally { Pop-Location }
    }
}




```

```markdown
# v00.01 - mwt-g

-----------------------------------------------------------
## AI INSTRUCTIONS

1. Only execute tasks marked with `[R]`.
  - `[ ]` indicates backlog (not yet ready to implement).
  - `[R]` indicates ready to implement in the current session.
  - `[x]` indicates the AI has implemented the code; set this once the work is completed in this session.
  - `[x]` indicates the user has signed off on the implementation.
1. Feature tracking is done using the format `Feature-00[ ]`
  - `[ ]` means that the feature has not been implemented.
  - `[x]` means that the feature is implemented. The AI shall annotate the feature description with the version that it was implemented in.
  - `[x]` is the human sign-off
1. Only mark a task or feature as done AFTER tests have passed
1. Do not excecute features without at least three tests to verify the implementation.

The prompt to execute the sequence will be
```
Review prompt v00.01.md and execute all implementation tasks marked with [R]
```

-----------------------------------------------------------
## APPLICATION SPECIFICATION

This section describes the application; it is not for execution purposes.

### Overview

mwt-g is a command-line tool for creating and launching URL aliases. It can be used within a project or installed globally.

### Features

- Custom URL scheme: `g:/<alias>` → `https://www.google.com/` (example)
- Settings are stored in:
  - A JSON file
  - Searched in the following order (first match wins):
    - Project-local: `./mwt-g/settings.json`
    - User-level: `~/.config/mwt-g/settings.json`

### Usage
- Feature-01[ ]: Adding an alias
  ```
  g g https://www.google.com
  ```


- Feature-02[ ]: Visiting the alias
  ```
  g y
  ```
  - Opens the user's default browser to `https://www.yahoo.com/`

- Feature-03[ ]: Adding an alias smartly
  ```
  g y yahoo
  ```
  - `y` is the alias name
  - If the second parameter is a bare keyword (no scheme), it resolves to `https://www.<param2>.com`

- Feature-04[ ]: Deep links
  ```
  g yn yahoo/news
  ```
  - `yn` is the alias name
  - Expands to `https://www.<param2>.com/news` → `https://www.yahoo.com/news`

- Feature-05[ ]: List aliases
  ```
  g +list
  ```
  - Lists all known aliases

- Feature-06[ ]: Choose navigation end-points
  ```
  g +b yn
  ```
  - `+b` will launch the URL into the registered browser.
  - `+c` will launch using Curl 
  - `+n` will display the URL for the user to click on.

- Feature-07[ ]: Register URL scheme
  ```
  g +register
  ```
  - Registers the custom `g:/` URL scheme with the OS so links like `g:/y` open via this tool

-----------------------------------------------------------
## Technical requirements

### MANDATORY

1. Only use PowerShell 7 for all scripting, whether it's the app or the tests.
2. The directory tree is $PROJECT_ROOT/mwt-g.
    - Create the following directories 
        - $PROJECT_ROOT/mwt-g/bin
        - $PROJECT_ROOT/mwt-g/tests
    - A separate promotion script will later move necessary content to the parent directory.

### Build Tool instructions
1. Build the tool using PowerShell 7, which should be available everywhere — Windows, macOS, and Linux.
1. Create the tool using best practices for portability — use Context7 to ensure that the most current documentation and best practices are adhered to.
1. Create the script as `mwt-g.ps1` in the `bin/` directory for this project.



-----------------------------------------------------------
## APPLICATION IMPLEMENTATION

### ALWAYS ###
- Maintain a `README.md` for the tool.
- Always write a test and always run the test after each session sequence.
- Only mark a task as `[x]` after the tests have been executed and passed.
- Perform syntax validation as a standard test.
- Maintain an application history prompts/HISTORY.md during each session
  - Note any tasks executed.
  - Note results of all tests.
  - Generate a commit message.
  - Summarize features.
- Testing:
  - Use Pester for all tests.
  - Ensure every test has a unique number T0000
  - Ensure that tests run indenpdently
  - For each test, assume a clean HOMEDIR with the following folder structure - testruns/YYYYMMDD-HHMMSS/TESTNUMBER/
  - For each test requested, annotate with the corresponding TESTNUMBER
  - All tests should be run from the mwt-g directory. testResults.xml should be in the testruns directory for that test run: testruns/YYYYMMDD-HHMMSS

### v00.01.01 
Create the initial version of the application as follows:

1. [x] Implement the ability to add a basic URL (`g g https://www.google.com`). [Feature-01] Implemented in v00.01.01
   - [x] add `+overwrite-alias` with `always`,`never`,`ask` options. Implemented in v00.01.01
   - [x] add `+quiet` to supress any messages. Implemented in v00.01.01
   - [x] app should display what it's doing (and why, if there are flags involved.) Implemented in v00.01.01
1. [x] Implement `+n` (display URL) and make it the default. [Feature-06] Implemented in v00.01.01
1. [x] Implement alias listing with `+list`. [Feature-05] Implemented in v00.01.01
1. [x] Rework the files:
       - [x] All configurations should be in configuration.toml (defaults respected by tool)
       - [x] All `+` options should be stored with defaults
           - [x] +overwrite-alias always
       - [x] Move the aliases to aliases.toml
        - [x] Create the configuration.toml file if it doesn't exist. Implemented in v00.01.01
1. [x] Implement tests using Pester
      - [x] `mwt-g g https://www.google.com` should add the alias to the settings file. [T0001]
      - [x] `mwt-g g` should display https://www.google.com [T0002]
      - [x] `mwt-g gg` throws an error [T0003]
      - [x] `mwt-g +list` should list all the aliases added [T0004]
      - [I] `mwt-g g https://news.google.com/` should overwrite the alias. Implemented in v00.01.01 [T0010]
       - [x] `mwt-g +quiet` should output nothing. [T0007]
       - [x] `mwt-g +overwrite-alias never g https://www.google.com` should refuse to overwrite the alias `g`. [T0006]
       - [I] `mwt-g +overwrite-alias always g https://www.gmail.com` should overwrite the alias `g`. Implemented in v00.01.01 [T0011]
       - [x] Test that the configuration file exists. Implemented in v00.01.01 [T0008]
      - [I] `mwt-g gx https://xxx.google.com/` should throw errors when trying to visit with 'mwt-g gx'. Implemented in v00.01.01 [T0012]

### v00.01.02
1. [I] Implement `+c` (fetch via curl). [Feature-06] Implemented in v00.01.02
1. [I] Implement tests using Pester
  - [I] Provide the tests a unique code T0000
    - `+c` fetch test: [T0009]


### v00.01.03
1. [x] Implement `+b` (open in browser). [Feature-06] Implemented in v00.01.03

### v00.01.04
1. [ ] Implement smart URL handling. [Feature-03]
1. [ ] Implement deep links. [Feature-04]

### Future
1. [ ] Implement visiting an alias baseline behavior (apply default action). [Feature-02]
1. [ ] Implement OS URL handler registration with `+register`. [Feature-07]


-----------------------------------------------------------
# IGNORE BELOW #



- Implement command line completions.
- Add long parameter names
- Add man page
- What other things should we be doing to make this a proper command line tool?
- Update settings handling
  - settings.json -> should contain application settings.
  - aliases should be in aliases.json or aliases.yaml
- mwt-g xxx -> instead of throwing an error should prompt for the URL. (or paste it from the copy-buffer)
- note when aliases were added or updated.
- update the parameter handling - not sure if I like the "+" syntax. also, it should be in keeping with PowerShell standards.
```

```markdown
mwt-g Session History

v00.01.01 (this session)

- Tasks executed
  - Implemented +overwrite-alias with modes always|never|ask
  - Implemented +quiet to suppress non-essential output
  - Implemented +list to display aliases in "alias url" format
  - Reworked storage from JSON to TOML:
    - Aliases: mwt-g/aliases.toml (project-first, then user ~/.config/mwt-g/aliases.toml)
    - Configuration: mwt-g/configuration.toml (project-first, then user ~/.config/mwt-g/configuration.toml)
  - Auto-create mwt-g/configuration.toml with defaults if missing
  - Added Pester test suite covering add, show (+n/default), unknown alias error, list, overwrite behaviors, quiet mode, config existence

- Test results
  - Pester: 8/8 tests passed (file: mwt-g/tests/test-pester-v00.01.01.Tests.ps1)

- Commit message
  - chore(mwt-g): add +overwrite-alias, +quiet, +list; migrate storage to TOML; auto-create configuration.toml; add Pester tests

- Feature summary
  - Feature-01: Add alias implemented and tested
  - Feature-05: List aliases implemented and tested
  - Feature-06: +n default display implemented and tested
  - Configuration defaults respected; overwrite behavior configurable; quiet mode supported


v00.01.02

- Tasks executed
  - Implemented `+c` (fetch via curl); falls back to `Invoke-WebRequest` when curl is unavailable
  - Removed all network gating; network is always enabled for `+c`
  - Renamed tests to be version-agnostic (`test-pester.Tests.ps1`, `test-cli.ps1`)
  - Made Pester tests standalone and independent:
    - Unique IDs (T0001–T0012); each test runs in isolated `testruns/YYYYMMDD-HHMMSS/TXXXX/`
    - No reliance on repo root state; copies tool into per-test sandbox
  - Added `run-tests.ps1` to execute Pester from `mwt-g/` and write `mwt-g/testruns/<runId>/testResults.xml`
  - Ensured all tests are executed from the `mwt-g` directory
  - Honored optional `MWT_G_TEST_RUN_ID` to set the run folder name

- Test results
  - Pester: 12/12 tests passing (file: `mwt-g/tests/test-pester.Tests.ps1`)
  - CLI test: passing (file: `mwt-g/tests/test-cli.ps1`)
  - Results XML: `mwt-g/testruns/<runId>/testResults.xml`

- Commit message
  - feat(mwt-g): add +c (curl) with web request fallback; make tests version-agnostic and isolated; add test runner and NUnit XML output

- Feature summary
  - Feature-06: +c implemented and tested
  - Testing: suite is isolated, repeatable, and produces testresults.xml


v00.01.03

- Tasks executed
  - Implemented `+b` (open in browser) with cross-platform support and test-friendly dry-run
  - Added env vars: `MWT_G_BROWSER_DRYRUN` and `MWT_G_BROWSER_CMD`
  - Updated usage in `bin/mwt-g.ps1` and expanded `README.md`
  - Added Pester tests T0013–T0015

- Test results
  - Pester: 15/15 tests passing (`mwt-g/tests/test-pester.Tests.ps1`)

- Commit message
  - feat(mwt-g): add +b open-in-browser with cross-platform support; add tests and docs

- Feature summary
  - Feature-06: +b implemented and tested


```

```powershell
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
    - Prefers project-local files. Creates ./mwt-g/*.toml if missing.

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
    - +c and +b are implemented; +register is not implemented yet
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

  Fetch via curl (+c):
    mwt-g.ps1 +c <alias>

  Open in default browser (+b):
    mwt-g.ps1 +b <alias>

  List aliases:
    mwt-g.ps1 +list

Notes:
  - Only absolute http/https URLs are supported
  - +register is not implemented yet
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
        & $openCmd.Path $url | Out-Null
        return
    }
    # Linux/other
    $xdgCmd = Get-Command xdg-open -ErrorAction SilentlyContinue
    if ($xdgCmd) {
        if (-not $script:QuietMode) { Write-Info "xdg-open $url" }
        & $xdgCmd.Path $url | Out-Null
        return
    }

    Write-Error "No suitable method found to open URL in browser. Tried: custom cmd, Start-Process, open, xdg-open."
    exit 13
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
        if ($first -eq '+b') {
            if ($ArgList.Length -lt 2) { Show-UsageAndExit }
            $alias = $ArgList[1]
            Invoke-OpenBrowser -Alias $alias
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



```

```markdown
# mwt-g

Minimal URL alias helper.

Features:
- Add alias: `pwsh bin/mwt-g.ps1 <alias> <absolute-url>`
- Display URL: `pwsh bin/mwt-g.ps1 <alias>` or `pwsh bin/mwt-g.ps1 +n <alias>`
- Fetch via curl: `pwsh bin/mwt-g.ps1 +c <alias>`
- Open in browser: `pwsh bin/mwt-g.ps1 +b <alias>`

Storage (TOML):
- Aliases: project `./mwt-g/aliases.toml`, then user `~/.config/mwt-g/aliases.toml`
- Configuration: project `./mwt-g/configuration.toml`, then user `~/.config/mwt-g/configuration.toml`

Notes:
- Only absolute http/https URLs are supported in this version.
- `+register` is not implemented yet.

Testing:
- From `mwt-g/` run: `pwsh tests/run-tests.ps1`
- This writes `testruns/<runId>/testResults.xml` and runs all Pester tests.



```

### Status
- Implemented the only [R] task in `mwt-g/prompts/v00.01.md`: `+b` (open in browser).
- Added tests, updated docs and history, ran the full test suite from `mwt-g/` [[memory:5728624]], and committed changes. I avoided touching anything outside the `mwt-g/` project subfolder [[memory:5728627]].

### What I changed
- Implemented `+b` with cross-platform support and test-friendly env vars in `mwt-g/bin/mwt-g.ps1`.
  - `MWT_G_BROWSER_DRYRUN=1` prints the URL instead of launching.
  - `MWT_G_BROWSER_CMD=<command>` to override how the URL is opened.
- Added tests:
  - `T0013`: dry-run mode returns URL.
  - `T0014`: custom browser command is honored.
  - `T0015`: errors on unknown alias with `+b`.
- Updated usage/help text and README for `+b` and `+c`.
- Recorded the session in `mwt-g/prompts/HISTORY.md`.
- Marked the [R] item as done in `mwt-g/prompts/v00.01.md`.

### Tests
- Ran from `mwt-g/` as required: all tests passed.
- Result: 15/15 passing.

### How to use
- Open in browser: `pwsh bin/mwt-g.ps1 +b <alias>`
- Dry-run (for CI/tests): `MWT_G_BROWSER_DRYRUN=1 pwsh bin/mwt-g.ps1 +b <alias>`
- Custom command: `MWT_G_BROWSER_CMD=/bin/echo pwsh bin/mwt-g.ps1 +b <alias>`

### Commit
- feat(mwt-g): implement +b open-in-browser with cross-platform support; add tests T0013–T0015; update usage and README; record history v00.01.03

- Updated `mwt-g/bin/mwt-g.ps1` (adds `+b` with `Invoke-OpenBrowser`, usage text, version bump to v00.01.03)
- Updated `mwt-g/tests/test-pester.Tests.ps1` (adds T0013–T0015)
- Updated `mwt-g/README.md` (adds `+b`, `+c`, TOML storage details, test instructions)
- Updated `mwt-g/prompts/HISTORY.md` (records v00.01.03 changes)
- Updated `mwt-g/prompts/v00.01.md` (marks `+b` as implemented in v00.01.03)

- Note: linter shows existing verb warnings (unapproved verb names). They’re warnings only; no functional or test impact.

- All changes are scoped to `mwt-g/` as requested.

