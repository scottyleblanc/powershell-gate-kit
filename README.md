# powershell-gate-kit

## Overview

A gate for PowerShell repositories: one command that runs every check a change must
pass before it is pushed or merged. It runs PSScriptAnalyzer with nine house rules,
the repository's static tests, gitleaks over the working tree, the unpushed commits and
their messages, a check of committed AI-agent permission files, and a check that the
branch carries an answered second-model review. Optional checks hold one version
number everywhere and run the unit tests. The same command runs in the pre-push hook
and in CI, so a change that fails locally also fails the pull request.

A repository takes the kit as a git subtree in its `tools/gate/` folder and configures
it with one data file, `gate.config.psd1`, in its root folder.

## Prerequisites

PowerShell 7.6, git, PSScriptAnalyzer 1.25.0, Pester 5.7.1 and gitleaks 8.30.1.
`tools/gate/Scripts/Install-GateTool.ps1` installs the last three. Details in
[tools/gate/Docs/PREREQUISITES.md](Docs/PREREQUISITES.md).

## Installation

The repository you add the gate to is called the target here. Every path below is
relative to the target's root folder, and every command is run from there, in a shell
that has git and `pwsh` (Git Bash on Windows for the `cp` and `mkdir` lines).
`<kit-remote>` is the clone URL of this kit's repository.

### 1. Add the kit to the target

```sh
git subtree add --prefix=tools/gate <kit-remote> main --squash
```

This copies the kit's files into the target's `tools/gate/` folder and commits them as
one commit. The files are then part of the target itself, so its CI and anyone who
clones it need no access to the kit's repository.

### 2. Install the tools (once per machine)

```powershell
& ./tools/gate/Scripts/Install-GateTool.ps1 -Destination (Join-Path -Path $HOME -ChildPath 'gate-tools')
```

Run this in `pwsh`. It installs PSScriptAnalyzer and Pester for your user, and
downloads gitleaks into the `-Destination` folder, here `$HOME/gate-tools`, after
checking its hash. gitleaks is added to `PATH` for that PowerShell session only. The
pre-push hook starts a new session, so add `$HOME/gate-tools` to your user `PATH`
permanently (on Windows: Settings, "Edit environment variables for your account"; on
Linux: a line in `~/.profile`), then open a new terminal. Run `gitleaks version` to
confirm it is found.

### 3. Create the config file

```sh
cp tools/gate/Templates/gate.config.psd1 gate.config.psd1
```

`gate.config.psd1` in the target's root folder tells the gate where the code is and
which optional checks to run. Every key is commented in the file. The kit also has a
`tools/gate/gate.config.psd1`: that one configures the gate for the kit itself, and
the gate in the target ignores it. Most repositories change two things in
`gate.config.psd1`.

**Where the code is.** `Analyzer.Paths` lists the folders PSScriptAnalyzer checks,
relative to the target's root folder and written with `/`. Each folder is read with
everything under it; files named `*.Tests.ps1` are skipped. In the file copied from
`tools/gate/Templates/gate.config.psd1` the list is empty, `Paths = @()`. Until you
add your folders, GK03 checks no code at all: it reports "no files to analyze" and
passes.

For a module whose code is in `source/Public/` and `source/Private/`, with helper
scripts in `scripts/`:

```powershell
Analyzer = @{
    Paths        = @('source', 'scripts')
    Exclude      = @('*.Tests.ps1')
    ExcludeRules = @()
    Baseline     = ''
}
```

**Which optional checks run.** The core checks GK01 to GK08 always run. The `Checks`
table at the top of `gate.config.psd1` turns the other three on (`$true`) or off
(`$false`). As copied from `tools/gate/Templates/gate.config.psd1`:

```powershell
Checks = @{
    Review  = $true    # GK10, with -Base: the second-model review record
    Version = $false   # GK09: one version everywhere, and the tag rule with -Base
    Unit    = $false   # GK11, with -Unit: the repository's unit test script
}
```

Each gate run shows the current settings: the GK01 line lists the optional checks that
are on, and a check that is off prints `[OFF]`.

| Key | Check | What it does | Starts | Turn it on when | Also set |
|---|---|---|---|---|---|
| `Review` | GK10 | On a pull request, requires a second-model review record covering the branch, with every finding answered ([tools/gate/Docs/REVIEW.md](Docs/REVIEW.md)) | on | You use the review step; it needs Claude Code installed. Set `$false` if you do not | — |
| `Version` | GK09 | The module version is the same in the manifest, the newest CHANGELOG release and the listed notes files | off | The target is a module with a CHANGELOG | `Version.Manifest`, `Version.Changelog` |
| `Unit` | GK11 | Runs the target's unit test script when the gate is run with `-Unit` | off | The target has a script that runs its tests and exits 0 only when they pass | `Unit.Script` |

The other keys (`StaticTests`, `Gitleaks`, `MessagePatterns`, `Permissions`) can stay
`''`, which uses the kit's defaults or turns the check's extra input off.

### 4. Turn on the pre-push hook

```sh
mkdir -p .githooks && cp tools/gate/Templates/pre-push .githooks/pre-push
git config core.hooksPath .githooks
```

This copies the hook to `.githooks/pre-push`. git then runs the gate with `-Quick`
before every push and refuses the push when a check fails. `-Quick` skips GK03, the
analyzer, which is the slowest check; CI still runs it on every pull request (DEC-011).
`core.hooksPath` is a local git setting, so everyone who clones the target runs the
`git config` line once.

### 5. Run the gate

```sh
pwsh -NoProfile -File ./tools/gate/Scripts/Invoke-Gate.ps1
```

Each check prints one line: `[PASS]`, `[FAIL]`, or `[OFF]` for a check turned off. On
a new repository every check should pass. On a repository with existing code, the
analyzer check (GK03) will usually fail; step 6 handles that.

### 6. Existing findings (only when GK03 fails in step 5)

In `gate.config.psd1`, set `Analyzer.Baseline` to the path of a baseline file, for
example `'gate/analyzer-baseline.psd1'` (the file `gate/analyzer-baseline.psd1` in the
target's root folder), then run:

```sh
pwsh -NoProfile -File ./tools/gate/Scripts/Update-AnalyzerBaseline.ps1
```

This records the current findings in that file, counted per file and per rule. From
then on GK03 fails only when a file has more findings for a rule than the baseline
holds, so old findings can be fixed over time and new ones cannot be added. Commit the
baseline file.

### 7. Run the gate in CI

- **GitHub:** copy `tools/gate/Templates/github/gate.yml` to
  `.github/workflows/gate.yml`.
- **Bitbucket:** copy `tools/gate/Templates/bitbucket-pipelines.yml` to
  `bitbucket-pipelines.yml` and turn on Pipelines for the repository.

Both run the gate on every pull request against its target branch. To stop a failing
pull request from merging, make the `gate` job a required check on that branch: a
branch protection rule or ruleset on GitHub, a merge check on Bitbucket. On GitHub
this needs a public repository or a paid plan; on GitHub Free a private repository
runs the gate but cannot block the merge, so a failing check only advises.

### 8. Add the pull request template

On GitHub, copy `tools/gate/Templates/pull_request_template.md` to
`.github/pull_request_template.md`; GitHub then fills every new pull request with its
checklist. On Bitbucket, use the text of
`tools/gate/Templates/pull_request_template.md` as the pull request description.

### 9. Commit and push

Commit `gate.config.psd1`, `.githooks/pre-push`, the CI file
(`.github/workflows/gate.yml` or `bitbucket-pipelines.yml`),
`.github/pull_request_template.md` and any baseline file, then push. The hook runs
the gate on that push.

### For each pull request

When `Review` is on, run the review once before opening the pull request:

```sh
pwsh -NoProfile -File ./tools/gate/Scripts/Invoke-ModelReview.ps1
```

It writes the review record to `Review/LastReview.json` (the `Review.Record` key in
`gate.config.psd1`). Answer each finding in that file and commit it. Without it, GK10
fails in CI. The full path is in [tools/gate/Docs/REVIEW.md](Docs/REVIEW.md).

### Updating the kit

```sh
git subtree pull --prefix=tools/gate <kit-remote> main --squash
```

This brings the kit's newer files into `tools/gate/` as one commit.
`gate.config.psd1`, the baseline file and the review record are outside that folder
and are not touched.

## Scripts

Paths as they are in a target.

| Script | What it does |
|---|---|
| `tools/gate/Scripts/Invoke-Gate.ps1` | Runs the checks GK01 to GK11; exits 0 when all pass |
| `tools/gate/Scripts/Install-GateTool.ps1` | Installs the pinned tool versions; gitleaks is hash-checked |
| `tools/gate/Scripts/Invoke-ModelReview.ps1` | Runs the second-model review once and writes the review record |
| `tools/gate/Scripts/Update-AnalyzerBaseline.ps1` | Records the current analyzer findings as the baseline |
| `tools/gate/Scripts/Invoke-StaticTest.ps1` | Runs the static test folder for GK04 |

The checks and the rules each enforces are in
[tools/gate/Docs/rules.md](Docs/rules.md); the review path is in
[tools/gate/Docs/REVIEW.md](Docs/REVIEW.md).

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
six characters. `tools/gate/Scripts/Invoke-ModelReview.ps1` writes only the review
record named in `gate.config.psd1` (default `Review/LastReview.json`).

## Current Security State

| Item | Value |
|---|---|
| Version | unreleased (first tag pending) |
| Last audit | not yet audited |
| Tests | 84 static tests: 23 gate behaviour cases, 16 analyzer rule cases, 45 unbranded file checks |
| Open items | See [Docs/SECURITY.md](Docs/SECURITY.md#open-items) |

## Licence

MIT; see [LICENSE](LICENSE). Anyone may use, change and redistribute the kit. It is
provided as is, without warranty, and the authors and the copyright holder accept no
liability for its use. `LICENSE` travels into `tools/gate/LICENSE` in every target and
must stay there.

## Contributing

This section is for work on the kit itself, in its own repository, where paths have no
`tools/gate/` prefix. Work is listed in [Docs/TODO.md](Docs/TODO.md), released changes
in [Docs/CHANGELOG.md](Docs/CHANGELOG.md), and commit and version rules in
[Docs/VERSIONING.md](Docs/VERSIONING.md). Decisions are in
[Docs/decisions.md](Docs/decisions.md). The kit is gated by itself, configured by its
own `gate.config.psd1`: turn on the hook with `git config core.hooksPath .githooks`.
