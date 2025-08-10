# Review and execute implementation tasks
_Exported on 8/9/2025 at 22:43:29 CDT from Cursor (1.4.3)_

---

**User**

Review prompt v00.01.md and execute all implementation tasks marked with [R]

---

**Cursor**

I'm going to scan the prompt and related meta/script files to find every task marked with [R] and understand what's required. Then I'll implement the changes directly.

I'll create the proper `mwt-g/bin` and `mwt-g/tests` structure, add a clean `mwt-g/bin/mwt-g.ps1` implementing add alias and +n/default, write a simple PowerShell test script for +n, add a concise `mwt-g/README.md`, update `mwt-g/prompts/v00.01.md` to mark the [R] items as [I], remove the duplicate root `bin/mwt-g.ps1`, and then run the tests.

```powershell
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
        [Console]::Write($url)
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
        [Console]::Write($url)
        exit 0
    }

    default {
        Show-UsageAndExit
    }
}


```

Creating tests, README, and updating the prompt status. Then I'll remove the duplicate top-level script and run the tests via zsh.

```powershell
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

$toolPath = Join-Path -Path (Get-Location) -ChildPath 'mwt-g/bin/mwt-g.ps1'
if (-not (Test-Path -LiteralPath $toolPath)) {
    Write-Error "Tool not found at $toolPath"
    exit 1
}

$settingsPath = Join-Path -Path (Get-Location) -ChildPath 'mwt-g/settings.json'
$backupPath = "$settingsPath.bak"

if (Test-Path -LiteralPath $settingsPath) {
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force
}

try {
    if (Test-Path -LiteralPath $settingsPath) { Remove-Item -LiteralPath $settingsPath -Force }

    $alias = 'g'
    $url = 'https://www.google.com'

    # Add alias
    & $toolPath $alias $url | Out-Null

    # +n action
    $outN = & $toolPath '+n' $alias
    Assert-Equal -Expected $url -Actual $outN -Message '+n should print exact URL'

    # default action
    $outDefault = & $toolPath $alias
    Assert-Equal -Expected $url -Actual $outDefault -Message 'default action should print exact URL'

    Write-Host 'All tests passed for v00.01.01'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $backupPath) {
        Move-Item -LiteralPath $backupPath -Destination $settingsPath -Force
    }
}


```

```markdown
*** Begin Patch
*** Update File: /Users/mwt/projects/mwt-tools/README.md
@@
 # mwt-tools
 
+This repository contains tools under active development. See `mwt-g/` for the URL alias helper.
+
+Quick start for `mwt-g`:
+
+- Add an alias: `pwsh mwt-g/bin/mwt-g.ps1 g https://www.google.com`
+- Show URL (default or `+n`):
+  - `pwsh mwt-g/bin/mwt-g.ps1 g`
+  - `pwsh mwt-g/bin/mwt-g.ps1 +n g`
+
+Settings precedence (read):
+- Project: `./mwt-g/settings.json`
+- User: `~/.config/mwt-g/settings.json`
+
*** End Patch
```

```markdown
# mwt-tools

Tools for MWT.

This repository contains tools under active development. See `mwt-g/` for the URL alias helper.

Quick start for `mwt-g`:

- Add an alias: `pwsh mwt-g/bin/mwt-g.ps1 g https://www.google.com`
- Show URL (default or `+n`):
  - `pwsh mwt-g/bin/mwt-g.ps1 g`
  - `pwsh mwt-g/bin/mwt-g.ps1 +n g`

Settings precedence (read):
- Project: `./mwt-g/settings.json`
- User: `~/.config/mwt-g/settings.json`

```

```markdown
# mwt-g

Minimal URL alias helper.

Features in v00.01.01:
- Add alias: `pwsh bin/mwt-g.ps1 <alias> <absolute-url>`
- Display URL: `pwsh bin/mwt-g.ps1 <alias>` or `pwsh bin/mwt-g.ps1 +n <alias>`

Storage:
- Read precedence: `./mwt-g/settings.json` then `~/.config/mwt-g/settings.json`
- Writes prefer project-local `./mwt-g/settings.json`

Notes:
- Only absolute http/https URLs are supported in this version.
- Other actions (`+c`, `+b`, `+list`, `+register`) are not implemented yet.


```

```markdown
# v00.01 - mwt-g

-----------------------------------------------------------
## AI INSTRUCTIONS

1. Only execute items marked with `[R]`.
  - `[ ]` indicates backlog (not yet ready to implement).
  - `[R]` indicates ready to implement in the current session.
  - `[I]` indicates the AI has implemented the code; set this once the work is completed in this session.
  - `[x]` indicates the user has signed off on the implementation.
2. Feature tracking is done using the format `Feature-00[ ]`
  - `[ ]` means that the feature has not been implemented.
  - `[I]` means that the feature is implemented. The AI shall annotate the feature description with the version that it was implemented in.
  - `[x]` is the human sign-off

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

### Test Tool instructions
1. Create a test script under `tests/`.
1. Create tests for the `+n` option.
1. Create tests for the `+c` option.


-----------------------------------------------------------
## APPLICATION IMPLEMENTATION

### ALWAYS ###
- Maintain a `README.md` for the tool.
- Always write a test and always run the test after each session sequence.

### v00.01.01 
Create the initial version of the application as follows:

1. [I] Implement the ability to add a basic URL (`g g https://www.google.com`). [Feature-01] Implemented in v00.01.01
1. [I] Implement `+n` (display URL) and make it the default. [Feature-06] Implemented in v00.01.01

### v00.01.02
1. [ ] Implement `+c` (fetch via curl). [Feature-06]

### v00.01.03
1. [ ] Implement `+b` (open in browser). [Feature-06]

### v00.01.04
1. [ ] Implement smart URL handling. [Feature-03]
1. [ ] Implement deep links. [Feature-04]

### Future
1. [ ] Implement visiting an alias baseline behavior (apply default action). [Feature-02]
1. [ ] Implement alias listing with `+list`. [Feature-05]
1. [ ] Implement OS URL handler registration with `+register`. [Feature-07]


-----------------------------------------------------------
# IGNORE BELOW #



- Implement command line completions.
- Add long parameter names
- Add man page
- What other things should we be doing to make this a proper command line tool?
```

```powershell
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



```

- Implemented v00.01.01 tasks and verified behavior locally.

What I did:
- Added `mwt-g/bin/mwt-g.ps1` implementing:
  - Add alias: `<alias> <absolute-url>` (Feature-01)
  - Show URL via `+n` and as default action (Feature-06)
  - JSON storage with precedence: project `./mwt-g/settings.json`, then user `~/.config/mwt-g/settings.json`
  - Safe writes preferring project-local; basic validations
- Created `mwt-g/tests/test-v00.01.01.ps1` covering:
  - Add alias
  - `+n` prints exact URL
  - default action prints exact URL
- Updated docs:
  - `mwt-g/README.md` quick usage and behavior notes
  - Root `README.md` quick-start pointers
- Updated `mwt-g/prompts/v00.01.md`:
  - Marked v00.01.01 [R] items as [I], annotated “Implemented in v00.01.01”.
- Removed reliance on the old duplicate script by standardizing on `mwt-g/bin/mwt-g.ps1` (no duplicate found to delete).
- Ran tests via zsh/Pwsh; fixed output to ensure reliable capture (switched to `Write-Output`). Tests now pass.

How to run tests:
- zsh: `pwsh mwt-g/tests/test-v00.01.01.ps1`

Notes:
- Only v00.01.01 tasks were executed; `+c`, `+b`, smart URLs, deep links, etc., remain pending per plan.

- Updated files:
  - `mwt-g/bin/mwt-g.ps1`
  - `mwt-g/tests/test-v00.01.01.ps1`
  - `mwt-g/README.md`
  - `README.md`
  - `mwt-g/prompts/v00.01.md`

