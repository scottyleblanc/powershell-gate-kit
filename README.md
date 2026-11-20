# powershell-gate-kit

## Overview

A gate for PowerShell repositories: one command that runs every check a change must
pass before it is pushed or merged. It runs PSScriptAnalyzer with nine house rules,
the repository's static tests, gitleaks over the working tree, the unpushed commits and
their messages, a check of committed AI-agent permission files, and a check that the
branch carries an answered second-model review. Optional checks hold one version
number everywhere and run the unit tests. The same command runs in the pre-push hook
and in CI, so a change that fails locally also fails the pull request.

A repository takes the kit as a git subtree at `tools/gate` and configures it with one
data file, `gate.config.psd1`.

## Prerequisites

PowerShell 7.6, git, PSScriptAnalyzer 1.25.0, Pester 5.7.1 and gitleaks 8.30.1.
`Scripts/Install-GateTool.ps1` installs the last three. Details in
[Docs/PREREQUISITES.md](Docs/PREREQUISITES.md).

## Installation

In the target repository:

```sh
git subtree add --prefix=tools/gate <kit-remote> main --squash
cp tools/gate/Templates/gate.config.psd1 gate.config.psd1
mkdir -p .githooks && cp tools/gate/Templates/pre-push .githooks/pre-push
git config core.hooksPath .githooks
```

Then:

1. Edit `gate.config.psd1`: set `Analyzer.Paths` to the source folders, and turn on
   the optional checks the repository needs.
2. For CI, copy `Templates/github/gate.yml` to `.github/workflows/gate.yml`, or
   `Templates/bitbucket-pipelines.yml` to the root, and make the `gate` job a required
   check on the target branch.
3. Copy `Templates/pull_request_template.md` to where the host reads it.
4. A repository with existing analyzer findings sets `Analyzer.Baseline` and runs
   `pwsh -NoProfile -File ./tools/gate/Scripts/Update-AnalyzerBaseline.ps1` once.
5. Run the gate: `pwsh -NoProfile -File ./tools/gate/Scripts/Invoke-Gate.ps1`.

Update the kit with `git subtree pull --prefix=tools/gate <kit-remote> main --squash`.

## Scripts

| Script | What it does |
|---|---|
| `Scripts/Invoke-Gate.ps1` | Runs the checks GK01 to GK11; exits 0 when all pass |
| `Scripts/Install-GateTool.ps1` | Installs the pinned tool versions; gitleaks is hash-checked |
| `Scripts/Invoke-ModelReview.ps1` | Runs the second-model review once and writes the review record |
| `Scripts/Update-AnalyzerBaseline.ps1` | Records the current analyzer findings as the baseline |
| `Scripts/Invoke-StaticTest.ps1` | Runs the static test folder for GK04 |

The checks and the rules each enforces are in [Docs/rules.md](Docs/rules.md); the
review path is in [Docs/REVIEW.md](Docs/REVIEW.md).

## Output Contract

The scripts are command-line tools, not module functions, so they do not return the
`Success / Data / Message` object. The gate prints one line per check and exits with a
code:

```
[PASS] GK05 secrets : no leaks in the working tree
[FAIL] GK07 messages : messages of 2 unpushed commit(s), 1 problem(s)
       commit 1a2b3c4: CM-001 no private key block: -----***
[OFF]  GK09 version : off in gate.config.psd1
[FAIL] gate: 1 of 8 checks failed: GK07 messages
```

Exit code 0 means every check that ran passed; 1 means at least one failed, or the
config is invalid. Every check runs even after one fails, except that an invalid config
stops the gate. A check that cannot run (a tool missing, git unable to list the
change) fails; it never passes by default.

## Logging and Diagnostics

The gate writes to standard output only, and writes no file. Found values are never
printed in full: gitleaks runs with `--redact`, and a pattern match shows only its first
six characters. `Invoke-ModelReview.ps1` writes only the review record named in the
config.

## Current Security State

| Item | Value |
|---|---|
| Version | unreleased (first tag pending) |
| Last audit | not yet audited |
| Tests | 82 static tests: 21 gate behaviour cases, 16 analyzer rule cases, 45 unbranded file checks |
| Open items | See [Docs/SECURITY.md](Docs/SECURITY.md#open-items) |

## Contributing

Work is listed in [Docs/TODO.md](Docs/TODO.md), released changes in
[Docs/CHANGELOG.md](Docs/CHANGELOG.md), and commit and version rules in
[Docs/VERSIONING.md](Docs/VERSIONING.md). Decisions are in
[Docs/decisions.md](Docs/decisions.md). The kit is gated by itself: turn on the hook
with `git config core.hooksPath .githooks`.
# powershell-gate-kit
