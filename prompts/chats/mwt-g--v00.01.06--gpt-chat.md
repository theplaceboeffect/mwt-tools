# PowerShell script configuration issue
_Exported on 8/10/2025 at 19:53:04 CDT from Cursor (1.4.3)_

---

**User**

review mwt-g.ps1 - why is it not creating the configuration in ~?

---

**Cursor**

Scanning the script and related config files to see how config paths are resolved and whether the code copies defaults into the home directory. Then I'll pinpoint why it isn't creating the configuration under your home (~).

- The script never creates config in `~`. It intentionally creates project-local config in `./mwt-g/configuration.toml` and only reads from `~/.config/mwt-g/configuration.toml` as a fallback.

Key places:
```149:179:/Users/mwt/projects/mwt-tools/mwt-g/bin/mwt-g.ps1
function Load-Config {
    $path = $null
    $proj = Get-ProjectConfigPath
    $user = Get-UserConfigPath
    if (Test-Path -LiteralPath $proj) { $path = $proj }
    elseif (Test-Path -LiteralPath $user) { $path = $user }

    $config = @{ overwrite_alias = 'always'; quiet = $false }
    if (-not $path) { return $config }
    ...
}
```

```76:96:/Users/mwt/projects/mwt-tools/mwt-g/bin/mwt-g.ps1
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
```

If you want it to create in `~` instead, change the default creation logic to target the user path when neither location exists (e.g., create `Get-UserConfigPath`’s directory and file rather than the project one). 

- Example adjustment: in `Ensure-ConfigDefaultFile`, check both paths; if neither exists, write to `Get-UserConfigPath()`.

- Note: alias writes are also project-local by design; only reads fall back to user-level. If you want user-level writes for aliases too, similar change is needed in `Get-EffectiveAliasesPathForWrite`.

- I can implement the home-creation behavior if you want me to change the script.

```powershell
function Load-Config {
    $path = $null
    $proj = Get-ProjectConfigPath
    $user = Get-UserConfigPath
    if (Test-Path -LiteralPath $proj) { $path = $proj }
    elseif (Test-Path -LiteralPath $user) { $path = $user }

    $config = @{ overwrite_alias = 'always'; quiet = $false }
    if (-not $path) { return $config }
    ...
}
```

```powershell
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
```

---

**User**

review prompts/v00.01.md and execute remaining tasks marked [R]

---

**Cursor**

Reviewing `mwt-g/prompts/v00.01.md` to find tasks marked [R], then I'll implement the required edits and run tests from `mwt-g` as per your project rules.

Reading the test scripts and related files to implement the [R] tasks and ensure tests move results into the correct testruns folder. Then I’ll make the necessary edits in the script to adjust config handling.

Making the config handling create in HOME if local `.config/mwt-g/` is absent, and updating the test runner to always write/move `testResults.xml` into `testruns/<runId>`. Then I’ll run the test suite from `mwt-g`.

Planning to implement the [R] tasks:
- Update `bin/mwt-g.ps1` to prefer a project-local `./.config/mwt-g/configuration.toml` on startup; if absent, create the config in `~/.config/mwt-g/configuration.toml`.
- Update `bin/run-all-tests.ps1` to delegate to `bin/tests.ps1 --run-all` so results are placed under `testruns/<runId>/testResults.xml`.
Then I'll run the test suite from `/Users/mwt/projects/mwt-tools/mwt-g` using zsh as requested.

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
       - Configuration: ./.config/mwt-g/configuration.toml (preferred) or ./mwt-g/configuration.toml (legacy)
    2) User-level:
       - Aliases:       ~/.config/mwt-g/aliases.toml
       - Configuration: ~/.config/mwt-g/configuration.toml

  Writing:
    - Aliases: prefers project-local file and creates ./mwt-g/aliases.toml if missing.
    - Configuration: on first run, if no project-local config exists at ./.config/mwt-g/configuration.toml,
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

function Get-LocalConfigPath {
    $cwd = Get-Location
    $localDir = Join-Path -Path $cwd -ChildPath '.config/mwt-g'
    return Join-Path -Path $localDir -ChildPath 'configuration.toml'
}

function Ensure-ConfigDefaultFile {
    # On startup, prefer an existing project-local config at ./.config/mwt-g/configuration.toml.
    # If none exists, ensure a user-level config exists at ~/.config/mwt-g/configuration.toml.
    $localConfig = Get-LocalConfigPath
    if (Test-Path -LiteralPath $localConfig) { return }

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
    $local = Get-LocalConfigPath
    $proj = Get-ProjectConfigPath
    $user = Get-UserConfigPath
    if (Test-Path -LiteralPath $local) { $path = $local }
    elseif (Test-Path -LiteralPath $proj) { $path = $proj }
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

  Register URL scheme handler (+register):
    mwt-g.ps1 +register

Notes:
  - Only absolute http/https URLs are supported
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



```

I'll update the test scripts to ensure results end up under `testruns/<runId>/testResults.xml`, and adjust the runner to delegate to the centralized test script. Then I'll run the full test suite from `mwt-g` using zsh as requested [[memory:5728624]].

```powershell
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
```

Adjusting tests to reflect the new config behavior by isolating HOME per test and validating the config under `.config/mwt-g/`. Then I'll update the prompt checklist to [I], and run the full test suite from `mwt-g` using zsh as requested.

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
        # Config is expected under local .config/mwt-g/ or user ~/.config/mwt-g/.
        # For test isolation, force HOME and USERPROFILE to the test dir so user-level writes land under the test root.
        $env:HOME = $script:CurrentTestDir
        $env:USERPROFILE = $script:CurrentTestDir
        $script:CurrentConfig     = Join-Path $script:CurrentTestDir '.config/mwt-g/configuration.toml'
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

    It 'registers goto:// scheme with +register on macOS [T0016]' -Skip:(-not $IsMacOS) {
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+register' | Out-Null
            $LASTEXITCODE | Should -Be 0
            $handlerApp = Join-Path -Path (Split-Path -Parent -Path $script:CurrentToolPath) -ChildPath 'mwt-g-url-handler.app'
            Test-Path -LiteralPath $handlerApp | Should -BeTrue
            $plist = Join-Path -Path $handlerApp -ChildPath 'Contents/Info.plist'
            Test-Path -LiteralPath $plist | Should -BeTrue
            $plistBuddy = '/usr/libexec/PlistBuddy'
            if (Test-Path -LiteralPath $plistBuddy) {
                $scheme = & $plistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' $plist
                $scheme | Should -Be 'goto'
            } else {
                $raw = Get-Content -LiteralPath $plist -Raw
                $raw | Should -Match '(?s)CFBundleURLSchemes.*goto'
            }
        }
        finally { Pop-Location }
    }

    It 'open goto://y does not error after registration on macOS [T0017]' -Skip:(-not $IsMacOS) {
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' 'y' 'https://www.yahoo.com/' | Out-Null
            & $script:CurrentToolPath '+register' | Out-Null
            $openCmd = Get-Command open -ErrorAction SilentlyContinue
            if (-not $openCmd) { throw 'open not found' }
            $code = 0
            try {
                & $openCmd.Path 'goto://y' | Out-Null
                $code = 0
            } catch { $code = 1 }
            $code | Should -Be 0
        }
        finally { Pop-Location }
    }

    It 'T0018: open goto://y produces no stdout noise [T0018]' -Skip:(-not $IsMacOS) {
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' 'y' 'https://www.yahoo.com/' | Out-Null
            & $script:CurrentToolPath '+register' | Out-Null
            $openCmd = Get-Command open -ErrorAction SilentlyContinue
            if (-not $openCmd) { throw 'open not found' }
            $out = & $openCmd.Path 'goto://y'
            (@($out).Count) | Should -Be 0
        }
        finally { Pop-Location }
    }

    It 'recompiles handler via applescript-tool and can open goto://y [T0019]' -Skip:(-not $IsMacOS) {
        Push-Location $script:CurrentTestDir
        try {
            & $script:CurrentToolPath '+quiet' 'y' 'https://www.yahoo.com/' | Out-Null
            $tool = Join-Path -Path (Join-Path $script:SourceProjectDir 'bin') -ChildPath 'applescript-tool.ps1'
            Test-Path -LiteralPath $tool | Should -BeTrue
            pwsh $tool -Recompile | Out-Null
            pwsh $tool -TestScript -OpenAlias y | Out-Null
            $openCmd = Get-Command open -ErrorAction SilentlyContinue
            if (-not $openCmd) { throw 'open not found' }
            $code = 0
            try { & $openCmd.Path 'goto://y' | Out-Null; $code = 0 } catch { $code = 1 }
            $code | Should -Be 0
        }
        finally { Pop-Location }
    }
}




```

Running the full test suite from `mwt-g` to validate the config changes and confirm `testResults.xml` is placed under `testruns/<runId>/`.

Updating the prompt checklist to mark the [R] tasks as implemented, adjusting the README to reflect new config handling, and appending a v00.01.06 entry to `prompts/HISTORY.md`. Then I’ll lint the changed files.

```markdown
# v00.01 - mwt-g

-----------------------------------------------------------
## AI INSTRUCTIONS

1. Only execute tasks marked with `[R]`.
  - `[ ]` indicates backlog (not yet ready to implement).
  - `[R]` indicates ready to implement in the current session.
  - `[I]` indicates the AI has implemented the code; set this once the work is completed in this session.
  - `[x]` indicates the user has signed off on the implementation.
1. Feature tracking is done using the format `Feature-00[ ]`
  - `[ ]` means that the feature has not been implemented.
  - `[I]` means that the feature is implemented. The AI shall annotate the feature description with the version that it was implemented in.
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
      - [x] `mwt-g g https://news.google.com/` should overwrite the alias. Implemented in v00.01.01 [T0010]
       - [x] `mwt-g +quiet` should output nothing. [T0007]
       - [x] `mwt-g +overwrite-alias never g https://www.google.com` should refuse to overwrite the alias `g`. [T0006]
       - [I] `mwt-g +overwrite-alias always g https://www.gmail.com` should overwrite the alias `g`. Implemented in v00.01.01 [T0011]
       - [x] Test that the configuration file exists. Implemented in v00.01.01 [T0008]
      - [x] `mwt-g gx https://xxx.google.com/` should throw errors when trying to visit with 'mwt-g gx'. Implemented in v00.01.01 [T0012]

### v00.01.02
1. [x] Implement `+c` (fetch via curl). [Feature-06] Implemented in v00.01.02
1. [x] Implement tests using Pester
  - [x] Provide the tests a unique code T0000
    - `+c` fetch test: [T0009]


### v00.01.03
1. [X] Implement `+b` (open in browser). [Feature-06] 

### v00.01.04
1. [x] Implement bin/tests.ps1. Implemented in v00.01.04
    - [x] `-l --list`  list each test and what it does. Implemented in v00.01.04
    - [x] `-r --run <T1000>` run a specific by TESTNUMBER T0000. Implemented in v00.01.04
    - [x] `--runall-all` will run all tests. Implemented in v00.01.04

### v00.01.05
1. [x] Implement OS URL handler registration with `+register`. [Feature-07] Implemented in v00.01.05
  - [x] Once registered, a URL with the format `goto://<alias>` will invoke `mwt-g +b` to launch the underlying URL in the browser. Implemented in v00.01.05
  - [x] The registration path should be the path of the script, wherever it is. Implemented in v00.01.05
  - [x] Implement the tests using Pester. Implemented in v00.01.05
1. [x] Create bin/applescript-tool.ps1. Implemented in v00.01.05
      - [x] `-ClearCache` clear the cache. Implemented in v00.01.05
      - [x] `-Recompile` recompile the applescript. Implemented in v00.01.05
      - [x] `-OpenAlias` open goto://y. Implemented in v00.01.05
      - [x] `-TestScript` which will run `mwt-g-url-handler.applescript` from source.
1. [x] Update `mwt-g-url-handler.applescript`
      - [x] display a dialog showing the input parameters to the script.
1. [x] update Register-UrlSchemeHandler() in mwt-g.ps1 with the AppleScript template file "mwt-g-url-handler.applescript.template"
1. Implement tests using Pester
    - [x] Verify with the OS that `goto://` is indeed registered. Implemented in v00.01.05
    - [x] Verify that on a Mac, `open goto://y` does not return an error. Implemented in v00.01.05
    - [x] Fix T0018 - it should not be returning any text at all. Implemented in v00.01.05

### v00.01.06
1. [I] Update configuration file handling (Implemented in v00.01.06):
    - [I] On start up, look for configuration in the local directory in .config/mwt-g/
    - [I] If it doesn't exist, create it in $HOME
1. [I] Ensure that testResults.xml is moved into the appropriate testruns/ after each run. (Implemented in v00.01.06)

 
### Future

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

v00.01.05

- Tasks executed
  - Implemented `+register` for macOS: creates an AppleScript app bundle adjacent to the script registering `goto://` scheme and invoking `+b`
  - Added Pester tests T0016–T0018 covering registration, `open goto://` success, and no-stdout behavior
  - Added `bin/applescript-tool.ps1` to recompile the handler, clear LaunchServices cache, and open a `goto://` alias; added T0019
  - Hardened external command resolution and avoided reliance on `.Path`
  - Updated README with `+register` usage

- Test results
  - Pester: 19/19 tests passing (`mwt-g/tests/test-pester.Tests.ps1`)

- Commit message
  - feat(mwt-g): add macOS URL scheme registration (+register) with tests; add applescript-tool; improve command resolution; docs update

- Feature summary
  - Feature-07: OS URL handler registration implemented and tested (macOS)


v00.01.06

- Tasks executed
  - Updated configuration file handling:
    - On startup, prefer project-local config at `./.config/mwt-g/configuration.toml`.
    - If missing, auto-create user-level `~/.config/mwt-g/configuration.toml`.
    - Tests isolate HOME per test to validate behavior.
  - Ensured test results are written under `mwt-g/testruns/<runId>/testResults.xml` by delegating `bin/run-all-tests.ps1` to `bin/tests.ps1 --run-all`.

- Test results
  - Pester: 19/19 tests passing (`mwt-g/tests/test-pester.Tests.ps1`)

- Commit message
  - chore(mwt-g): prefer local .config for config read; create user config on first run; unify test runner output to testruns

- Feature summary
  - Config handling aligned with prompt requirements; test artifacts organized per run


```

```markdown
# mwt-g

Minimal URL alias helper.

Features:
- Add alias: `pwsh bin/mwt-g.ps1 <alias> <absolute-url>`
- Display URL: `pwsh bin/mwt-g.ps1 <alias>` or `pwsh bin/mwt-g.ps1 +n <alias>`
- Fetch via curl: `pwsh bin/mwt-g.ps1 +c <alias>`
- Open in browser: `pwsh bin/mwt-g.ps1 +b <alias>`
- Register macOS URL scheme handler: `pwsh bin/mwt-g.ps1 +register`
  - Recompile/refresh helper (macOS): `pwsh bin/applescript-tool.ps1 -Recompile`, `-ClearCache`, `-OpenAlias y`

Storage (TOML):
- Aliases: project `./mwt-g/aliases.toml`, then user `~/.config/mwt-g/aliases.toml`
- Configuration: prefer local `./.config/mwt-g/configuration.toml`, then legacy `./mwt-g/configuration.toml`, then user `~/.config/mwt-g/configuration.toml`
  - On first run, if no local config exists, the tool will create `~/.config/mwt-g/configuration.toml` with defaults.

Notes:
- Only absolute http/https URLs are supported in this version.
- `+register` (macOS) installs a lightweight URL handler app next to the script to open `goto://<alias>` via `+b`.

Testing:
- From `mwt-g/` run: `pwsh tests/run-tests.ps1` or `pwsh bin/tests.ps1 --run-all`
- Results are written to `testruns/<runId>/testResults.xml`.



```

- Status: I reviewed `mwt-g/prompts/v00.01.md`, implemented both [R] tasks for v00.01.06, updated tests/runners, and verified all tests pass from `mwt-g` [[memory:5728624]].

### What I changed
- `bin/mwt-g.ps1`:
  - Config read order now prefers `./.config/mwt-g/configuration.toml`, then legacy `./mwt-g/configuration.toml`, then `~/.config/mwt-g/configuration.toml`.
  - On startup, if no local `./.config/mwt-g/configuration.toml` exists, a default config is created in `~/.config/mwt-g/configuration.toml`.
  - Updated header doc accordingly.
- `tests/test-pester.Tests.ps1`:
  - Tests isolate HOME per test (`$env:HOME` and `$env:USERPROFILE`), and validate config at `./.config/mwt-g/configuration.toml`.
- `bin/run-all-tests.ps1`:
  - Delegates to `bin/tests.ps1 --run-all` to ensure results land in `testruns/<runId>/testResults.xml`.
- `prompts/v00.01.md`:
  - Marked v00.01.06 [R] items as [I].
- `prompts/HISTORY.md`:
  - Added v00.01.06 entry describing config handling and test runner updates.
- `README.md`:
  - Documented the new config precedence and test execution/output paths.

### Test run
- Ran from `/Users/mwt/projects/mwt-tools/mwt-g` with:
  - `pwsh bin/tests.ps1 --run-all`
- Result: 19/19 tests passed. `testResults.xml` written under `mwt-g/testruns/<runId>/testResults.xml`.

### Notes
- Current lints: warnings for non-approved verb names and one unused variable in `bin/mwt-g.ps1`. These are non-blocking; I left the function names unchanged to avoid churn.

- If you want config to always be created in HOME regardless of local presence, I can adjust the logic; currently it creates in HOME only when no local `./.config/...` exists.

- To re-run tests:
  - From `mwt-g/`: `pwsh bin/tests.ps1 --run-all`

- Files updated: `mwt-g/bin/mwt-g.ps1`, `mwt-g/bin/run-all-tests.ps1`, `mwt-g/tests/test-pester.Tests.ps1`, `mwt-g/prompts/v00.01.md`, `mwt-g/prompts/HISTORY.md`, `mwt-g/README.md`.

---

**User**

even though ~/.config/mwt-g/configuration.toml exists, why is the application creating a local mwt-g directory for aliases?

---

**Cursor**

### Why it creates a local `mwt-g` for aliases

- **By design, writes go to project-local aliases.** The script always writes aliases to `./mwt-g/aliases.toml` and will create `./mwt-g/` if missing. It only falls back to `~/.config/mwt-g/aliases.toml` for reads when no project file exists.
- The presence of `~/.config/mwt-g/configuration.toml` affects only configuration, not the alias write location.

Key spots:
```106:113:/Users/mwt/projects/mwt-tools/mwt-g/bin/mwt-g.ps1
function Get-EffectiveAliasesPathForWrite {
    $projectPath = Get-ProjectAliasesPath
    $projectDir = Split-Path -Parent -Path $projectPath
    if (-not (Test-Path -LiteralPath $projectDir)) {
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
    }
    return $projectPath
}
```

```137:147:/Users/mwt/projects/mwt-tools/mwt-g/bin/mwt-g.ps1
function Save-Aliases {
    param([hashtable] $Aliases)
    $path = Get-EffectiveAliasesPathForWrite
    ...
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    return $path
}
```

### If you want aliases in HOME instead
- Change the write path logic to prefer `~/.config/mwt-g/aliases.toml` when no project-local `./mwt-g/aliases.toml` exists, or introduce a config option (e.g., `alias_scope = "user"`). I can implement this if you want.

```powershell
function Get-EffectiveAliasesPathForWrite {
    $projectPath = Get-ProjectAliasesPath
    $projectDir = Split-Path -Parent -Path $projectPath
    if (-not (Test-Path -LiteralPath $projectDir)) {
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
    }
    return $projectPath
}
```

```powershell
function Save-Aliases {
    param([hashtable] $Aliases)
    $path = Get-EffectiveAliasesPathForWrite
    ...
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    return $path
}
```

---

**User**

Yes, HOME should be the preferred directory if mwt-g does not exist.

---

**Cursor**

Updating alias write behavior to prefer HOME when `./mwt-g` does not exist, and refreshing the script header to document this change. Then I'll run the test suite from `mwt-g` using zsh to ensure everything still passes.

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
       - Configuration: ./.config/mwt-g/configuration.toml (preferred) or ./mwt-g/configuration.toml (legacy)
    2) User-level:
       - Aliases:       ~/.config/mwt-g/aliases.toml
       - Configuration: ~/.config/mwt-g/configuration.toml

  Writing:
    - Aliases: if ./mwt-g exists, write project-local; otherwise write to ~/.config/mwt-g/aliases.toml.
    - Configuration: on first run, if no project-local config exists at ./.config/mwt-g/configuration.toml,
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

function Get-LocalConfigPath {
    $cwd = Get-Location
    $localDir = Join-Path -Path $cwd -ChildPath '.config/mwt-g'
    return Join-Path -Path $localDir -ChildPath 'configuration.toml'
}

function Ensure-ConfigDefaultFile {
    # On startup, prefer an existing project-local config at ./.config/mwt-g/configuration.toml.
    # If none exists, ensure a user-level config exists at ~/.config/mwt-g/configuration.toml.
    $localConfig = Get-LocalConfigPath
    if (Test-Path -LiteralPath $localConfig) { return }

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
    # Prefer HOME when ./mwt-g does not exist
    if (Test-Path -LiteralPath $projectDir) {
        return $projectPath
    }
    $userPath = Get-UserAliasesPath
    $userDir = Split-Path -Parent -Path $userPath
    if (-not (Test-Path -LiteralPath $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
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
    $local = Get-LocalConfigPath
    $proj = Get-ProjectConfigPath
    $user = Get-UserConfigPath
    if (Test-Path -LiteralPath $local) { $path = $local }
    elseif (Test-Path -LiteralPath $proj) { $path = $proj }
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

  Register URL scheme handler (+register):
    mwt-g.ps1 +register

Notes:
  - Only absolute http/https URLs are supported
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



```

```markdown
# mwt-g

Minimal URL alias helper.

Features:
- Add alias: `pwsh bin/mwt-g.ps1 <alias> <absolute-url>`
- Display URL: `pwsh bin/mwt-g.ps1 <alias>` or `pwsh bin/mwt-g.ps1 +n <alias>`
- Fetch via curl: `pwsh bin/mwt-g.ps1 +c <alias>`
- Open in browser: `pwsh bin/mwt-g.ps1 +b <alias>`
- Register macOS URL scheme handler: `pwsh bin/mwt-g.ps1 +register`
  - Recompile/refresh helper (macOS): `pwsh bin/applescript-tool.ps1 -Recompile`, `-ClearCache`, `-OpenAlias y`

Storage (TOML):
- Aliases: writes to project `./mwt-g/aliases.toml` if `./mwt-g` exists; otherwise writes to user `~/.config/mwt-g/aliases.toml`. Reads prefer project, then user.
- Configuration: prefer local `./.config/mwt-g/configuration.toml`, then legacy `./mwt-g/configuration.toml`, then user `~/.config/mwt-g/configuration.toml`
  - On first run, if no local config exists, the tool will create `~/.config/mwt-g/configuration.toml` with defaults.

Notes:
- Only absolute http/https URLs are supported in this version.
- `+register` (macOS) installs a lightweight URL handler app next to the script to open `goto://<alias>` via `+b`.

Testing:
- From `mwt-g/` run: `pwsh tests/run-tests.ps1` or `pwsh bin/tests.ps1 --run-all`
- Results are written to `testruns/<runId>/testResults.xml`.



```

- Implemented: Aliases now write to HOME if `./mwt-g` does not exist; otherwise they write to project-local.
- Updated docs accordingly and verified with full test run from `mwt-g`: all tests pass.

If you want to force user-level writes even when a project folder exists, I can add a config switch (e.g., alias_scope = user|project).

