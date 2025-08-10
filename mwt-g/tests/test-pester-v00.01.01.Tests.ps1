#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:ToolPath = Join-Path -Path (Get-Location) -ChildPath 'mwt-g/bin/mwt-g.ps1'
    if (-not (Test-Path -LiteralPath $script:ToolPath)) { throw "Tool not found at $script:ToolPath" }
    $script:AliasesPath = Join-Path -Path (Get-Location) -ChildPath 'mwt-g/aliases.toml'
    $script:ConfigPath  = Join-Path -Path (Get-Location) -ChildPath 'mwt-g/configuration.toml'
    $script:AliasesBackup = "$script:AliasesPath.bak"
    $script:ConfigBackup  = "$script:ConfigPath.bak"
    if (Test-Path -LiteralPath $script:AliasesPath) { Copy-Item -LiteralPath $script:AliasesPath -Destination $script:AliasesBackup -Force }
    if (Test-Path -LiteralPath $script:ConfigPath)  { Copy-Item -LiteralPath $script:ConfigPath -Destination  $script:ConfigBackup -Force }
}

AfterAll {
    if (Test-Path -LiteralPath $script:AliasesBackup) {
        Move-Item -LiteralPath $script:AliasesBackup -Destination $script:AliasesPath -Force
    } else {
        if (Test-Path -LiteralPath $script:AliasesPath) { Remove-Item -LiteralPath $script:AliasesPath -Force }
    }
    if (Test-Path -LiteralPath $script:ConfigBackup) {
        Move-Item -LiteralPath $script:ConfigBackup -Destination $script:ConfigPath -Force
    } else {
        if (Test-Path -LiteralPath $script:ConfigPath) { Remove-Item -LiteralPath $script:ConfigPath -Force }
    }
}

Describe 'mwt-g v00.01.01 core behaviors' {
    It 'adds alias to aliases.toml' {
        if (Test-Path -LiteralPath $script:AliasesPath) { Remove-Item -LiteralPath $script:AliasesPath -Force }
        $alias = 'g'
        $url = 'https://www.google.com'
        & $script:ToolPath '+quiet' $alias $url | Out-Null
        Test-Path -LiteralPath $script:AliasesPath | Should -BeTrue
        $text = Get-Content -LiteralPath $script:AliasesPath -Raw
        $pattern = '(?ms)^\s*g\s*=\s*"https://www\.google\.com"\s*$'
        $text | Should -Match $pattern
    }

    It 'displays URL for alias (default and +n)' {
        $alias = 'g'
        $url = 'https://www.google.com'
        (& $script:ToolPath '+n' $alias) | Should -Be $url
        (& $script:ToolPath $alias) | Should -Be $url
    }

    It 'throws for unknown alias' {
        { & $script:ToolPath 'gg' | Out-Null } | Should -Throw
    }

    It 'lists aliases with +list' {
        $output = & $script:ToolPath '+list'
        ($output | Where-Object { $_ -match '^g\s+https://www\.google\.com$' }).Count | Should -BeGreaterThan 0
    }

    It 'overwrites alias when provided +overwrite-alias always' {
        $alias = 'g'
        & $script:ToolPath '+quiet' '+overwrite-alias' 'always' $alias 'https://www.google2.com' | Out-Null
        (& $script:ToolPath $alias) | Should -Be 'https://www.google2.com'
    }

    It 'respects +overwrite-alias never' {
        $alias = 'g'
        & $script:ToolPath '+quiet' '+overwrite-alias' 'never' $alias 'https://www.google3.com' | Out-Null
        (& $script:ToolPath $alias) | Should -Be 'https://www.google2.com'
    }

    It 'produces no output when +quiet is set' {
        $alias = 'q'
        $url = 'https://example.com'
        $out = & $script:ToolPath '+quiet' $alias $url
        ($out | Measure-Object).Count | Should -Be 0
    }

    It 'creates configuration.toml with defaults when missing' {
        if (Test-Path -LiteralPath $script:ConfigPath) { Remove-Item -LiteralPath $script:ConfigPath -Force }
        & $script:ToolPath '+quiet' 'cfg' 'https://example.com' | Out-Null
        Test-Path -LiteralPath $script:ConfigPath | Should -BeTrue
        $conf = Get-Content -LiteralPath $script:ConfigPath -Raw
        $conf | Should -Match '(?m)^\s*overwrite_alias\s*=\s*"always"' 
        $conf | Should -Match '(?m)^\s*quiet\s*=\s*false' 
    }
}


