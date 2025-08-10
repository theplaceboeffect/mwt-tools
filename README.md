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
