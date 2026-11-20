# Changelog

All notable changes to this kit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the kit uses
[Semantic Versioning](https://semver.org/) (`Docs/VERSIONING.md`).

## [Unreleased]

### Added

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

### Fixed

- `Templates/bitbucket-pipelines.yml` runs the gate with `-Unit`, as the GitHub
  workflow does, so GK11 runs in Bitbucket CI when `Checks.Unit` is on.

### Security

- gitleaks and PowerShell downloads checked against pinned SHA-256 hashes.
- Agent permission files checked against their documented rules (PM-001, PM-002).
