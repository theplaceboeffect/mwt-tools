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

v00.01.04

- Tasks executed
  - Implemented `bin/tests.ps1` test runner with:
    - `-l|--list` to enumerate tests and descriptions by `[T0000]`
    - `-r|--run <T0000>` to run a single test by ID
    - `--runall-all` to run the full suite
  - Adopted approved PowerShell verbs in function names
  - Output NUnit XML to `mwt-g/testruns/<runId>/testResults.xml`

- Test results
  - Pester: 15/15 tests passing (invoked via `bin/tests.ps1`)

- Commit message
  - chore(mwt-g): add tests.ps1 runner (list, run one, run all) with NUnit XML output; conform function verbs

- Feature summary
  - Testing: ergonomics improved with simple list/run commands

