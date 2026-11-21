# Changelog

All notable changes to this kit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the kit uses
[Semantic Versioning](https://semver.org/) (`Docs/VERSIONING.md`).

## [Unreleased]

### Added

- `Analyzer.ExcludeRulesByPath` in `gate.config.psd1` turns analyzer rules off under
  one folder, for example `@{ 'scripts' = @('PSAvoidUsingWriteHost') }` (DEC-012). GK01
  checks each folder exists (CF-004) and lists at least one rule name (CF-003).
- `Invoke-Gate.ps1 -Quick` skips GK03 and reports it `[OFF]`. `Templates/pre-push`
  passes it, so a push no longer waits for the analyzer; CI runs without it (DEC-011).
  The kit's own hook keeps GK03, because the kit has no CI. A target repository
  refreshes its `.githooks/pre-push` from the template to pick this up.
- `LICENSE`: the MIT licence (DEC-010), and a Licence section in the README. KT-001
  skips `LICENSE`, the one file that names the copyright holder.
- Three optional checks, off by default (DEC-013):
  - GK12 evidence (EV-001), with `-Base`: when a branch changes a path under
    `Evidence.Paths`, the committed record must show a passing run of
    `Evidence.Script` on a clean tree, current for the branch.
    `Scripts/Invoke-EvidenceRun.ps1` runs the script and writes the record.
  - GK13 package (PK-001), with `-Base`: the package `Compress-PSResource` builds from
    `Package.Manifest`'s folder holds exactly the files its `FileList` names.
    `Package.Build` names a build script to run first.
  - GK14 instructions (AG-001): `AGENTS.md` matches what
    `Scripts/Export-AgentInstruction.ps1` builds from `Instructions.Sources`.
- `Scripts/Invoke-Gate.ps1`: checks GK01 to GK11, configured by `gate.config.psd1`.
- `Scripts/Install-GateTool.ps1` for Windows x64 and Linux x64.
- `Scripts/Invoke-ModelReview.ps1`, `Scripts/Update-AnalyzerBaseline.ps1`,
  `Scripts/Invoke-StaticTest.ps1`.
- Custom analyzer rules AN-002 to AN-009.
- Templates: config, pre-push hook, GitHub Actions and Bitbucket Pipelines wrappers,
  pull request template, gitleaks config, message patterns, agent permissions.
- `Docs/rules.md`, `Docs/decisions.md` (DEC-001 to DEC-009), `Docs/REVIEW.md`.
- The kit's own tests: gate behaviour, analyzer rules, unbranded files (KT-001).

### Changed

- The README, `Docs/REVIEW.md` and the GitHub template state that a required check
  needs a public repository or a paid GitHub plan; on GitHub Free a private
  repository's gate only advises, and the human confirms it passed before merging.
- README installation rewritten for a first-time reader: one numbered step per task,
  each saying what it does; the tool install and the permanent `PATH` entry for
  gitleaks; a worked `Analyzer.Paths` example and the `Checks` table; every path given
  in full, relative to the target's root folder.
- GK10 exempts the evidence record, as it does the review record (RV-001).
- DEC-003 no longer rules out test evidence, package contents or agent instructions.
- README installation adds a step for the AI agent permission files: copying
  `Templates/claude-settings.json` to `.claude/settings.json` and
  `Templates/agent-permissions.psd1` into the target, checked by GK08.

### Fixed

- GK03 tries a file again, up to three times, when PSScriptAnalyzer 1.25.0 throws
  while loading the custom rules ("more than one dynamic module in each dynamic
  assembly", or a null reference); the throw was intermittent and stopped the whole
  gate. A third throw fails GK03 with the file named, and the later checks still run.

- `Templates/bitbucket-pipelines.yml` installs `libicu74`, `libssl3t64` and
  `libgssapi-krb5-2`. On the bare `ubuntu:24.04` image PowerShell stopped at start-up
  with "Couldn't find a valid ICU package installed on the system".
- GK05 scans the working tree as `.` from the repository root, so gitleaks
  fingerprints are relative paths and a fingerprint in `.gitleaksignore` matches.
  Scanning the absolute root path gave absolute fingerprints, so no `.gitleaksignore`
  entry ever matched. A test case covers it.
- `Templates/bitbucket-pipelines.yml` runs the gate with `-Unit`, as the GitHub
  workflow does, so GK11 runs in Bitbucket CI when `Checks.Unit` is on.
- AN-002 no longer reports class methods and constructors. `[OutputType()]` cannot be
  applied to them, so every one was a finding that could only be baselined. A test
  case covers it.

### Security

- gitleaks and PowerShell downloads checked against pinned SHA-256 hashes.
- Agent permission files checked against their documented rules (PM-001, PM-002).
- GK13 fails a module package that would ship a file its `FileList` does not name.
