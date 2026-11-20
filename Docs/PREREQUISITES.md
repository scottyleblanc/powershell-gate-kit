# Prerequisites

## Language version

PowerShell 7.6 minimum (7.6 LTS); tested on 7.6.10. Every script starts with
`#Requires -Version 7.6`.

## External tools

| Tool | Version | Source | Needed by |
|---|---|---|---|
| git | any current | the platform's package manager | every check that reads history (GK06, GK07, GK08, GK09, GK10) |
| PSScriptAnalyzer | 1.25.0 exactly | PSGallery | GK03, `Update-AnalyzerBaseline.ps1` |
| Pester | 5.x (5.7.1 installed) | PSGallery | GK04, the kit's own tests |
| gitleaks | 8.30.1 exactly | GitHub release, hash-checked | GK05, GK06, GK07 |
| Claude Code (`claude`) | current, signed in | Anthropic | `Invoke-ModelReview.ps1` only |

`Scripts/Install-GateTool.ps1 -Destination <folder>` installs PSScriptAnalyzer, Pester
and gitleaks. gitleaks goes on PATH for that session only.

## Environment setup

- `gate.config.psd1` at the repository root (see `Templates/gate.config.psd1`).
- The pre-push hook: copy `Templates/pre-push` to `.githooks/pre-push`, then
  `git config core.hooksPath .githooks` once per clone.
- No environment variables are read.

## Test framework

Pester 5. The kit's tests are all static tier: `Tests/` holds the analyzer rule tests,
the gate behaviour tests (each builds throwaway git repositories under `TestDrive`)
and the unbranded check. Run them through the kit's own gate:

```sh
pwsh -NoProfile -File ./Scripts/Invoke-Gate.ps1
```

or directly: `pwsh -NoProfile -File ./Scripts/Invoke-StaticTest.ps1 -Path ./Tests`.
The gate behaviour tests take about a minute and a half.

## Execution policy

| Context | Minimum policy |
|---|---|
| Developer workstation (Windows) | RemoteSigned |
| CI runner, GitHub Actions on Windows | the runner default (Unrestricted) |
| CI runner, Linux | not applicable |
| Locked-down host requiring signed scripts | AllSigned, with every `.ps1` and `.psm1` in `Scripts/` and `Analyzer/Rules/` signed |

## Platform support

| Platform | Status |
|---|---|
| Windows x64 | Supported: the kit's tests pass on Windows 11 |
| Linux x64 | Expected: `Install-GateTool.ps1` and the Bitbucket template target it; not yet run |
| macOS | Untested; `Install-GateTool.ps1` refuses it (no gitleaks hash pinned) |

## Known limitations

- The Linux path (`Install-GateTool.ps1` on Linux, `Templates/bitbucket-pipelines.yml`)
  has not run yet.
- Only x64 gitleaks hashes are pinned.
- GK11 trusts the unit script's exit code; it does not check what the script ran.
