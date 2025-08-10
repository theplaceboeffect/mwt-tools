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



