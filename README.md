# mwt-g

Minimal URL alias helper.

Features:
- Add alias: `pwsh bin/mwt-g.ps1 <alias> <absolute-url>`
- Open in browser (default): `pwsh bin/mwt-g.ps1 <alias>` or `pwsh bin/mwt-g.ps1 +b <alias>`
- Display URL: `pwsh bin/mwt-g.ps1 +n <alias>`
- Fetch via curl: `pwsh bin/mwt-g.ps1 +c <alias>`
- Register macOS URL scheme handler: `pwsh bin/mwt-g.ps1 +register`
  - Recompile/refresh helper (macOS): `pwsh bin/applescript-tool.ps1 -Recompile`, `-ClearCache`, `-OpenAlias y`

Storage (TOML):
- Aliases: writes to project `./aliases.toml`. Reads prefer project, then user `~/.config/mwt-g/aliases.toml`.
- Configuration: prefer local `./configuration.toml`, then user `~/.config/mwt-g/configuration.toml`
  - On first run, if no local config exists, the tool will create `~/.config/mwt-g/configuration.toml` with defaults.

Notes:
- Only absolute http/https URLs are supported in this version.
- `+register` (macOS) installs a lightweight URL handler app next to the script to open `goto://<alias>` via `+b`.

Testing:
- From project root run: `pwsh tests/run-tests.ps1` or `pwsh bin/tests.ps1 --run-all`
- Results are written to `testruns/<runId>/testResults.xml`.


