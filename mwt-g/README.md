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


