# Decisions

Each decision: what was decided, why, and what it rules out. IDs are never reused; a
decision that is replaced is marked superseded and names the one that replaces it.

## DEC-001 — Consumed by git subtree, squashed

A repository takes the kit with
`git subtree add --prefix=tools/gate <kit-remote> main --squash` and updates it with
`git subtree pull`.

**Why:** the kit's repository is private, and the people and CI runners of a target
repository may not reach it. A subtree copies the files into the target, so nothing
outside the target is needed to run the gate. `--squash` keeps the kit's history out
of the target's history.

**Rules out:** git submodules, and a package feed.

## DEC-002 — Unbranded

The kit holds no owner name, copyright line or licence file, and no rule IDs or
decision numbers from another repository. Commit messages in the kit follow the same
rule, because a squashed subtree commit lists them.

**Why:** the kit is copied into repositories owned by others.

**Enforced by:** KT-001 (`Tests/Unbranded.Tests.ps1`).

## DEC-003 — What the kit holds

The kit holds the checks any PowerShell repository can use: config, tools, analyzer,
static tests, secrets, commits, messages, agent permissions and the second-model
review (on by default), plus two optional checks, version and unit tests. It also holds
the scripts behind them, the templates a repository copies in (config, hook, CI
wrappers, pull request template) and the review guide.

**Why:** these checks need nothing from a repository but paths. Checks that depend on
one repository's build, database or test layout stay in that repository.

**Rules out:** a package-contents check, integration-test evidence, an invariant
linter, mutation tests, seeded-defect runs and an agent-instruction generator.

## DEC-004 — One config file, data only

A repository configures the gate in one file, `gate.config.psd1` at its root. It is
read with `Import-PowerShellDataFile`, so no code in it runs. Every path comes from the
config; the kit never assumes a folder name. The core checks cannot be turned off;
only review, version and unit can.

**Why:** a gate whose core checks can be switched off by one line is not a gate. Data
files cannot run commands, so a config change cannot run code during the gate.

## DEC-005 — Numbering

Checks are `GK01` onward in run order; rules are a two-letter area and three digits
(`AN-001`); decisions are `DEC-001` onward. A number is never reused.

**Why:** a finding, a commit message or a review can cite a rule without ambiguity.
The scheme differs from those of the repositories the kit came from, so an ID always
says which rule set it belongs to.

## DEC-006 — The kit is gated by itself

The kit's root holds its own `gate.config.psd1`, and its pre-push hook runs its own
`Scripts/Invoke-Gate.ps1`. Its static tests run the gate against throwaway
repositories, one case per rule.

**Why:** a gate script that is not itself held to the gate drifts first.

## DEC-007 — Analyzer baseline, counted per file and rule

A repository that adopts the gate with existing analyzer findings records them with
`Update-AnalyzerBaseline.ps1`. GK03 then fails only on findings beyond the recorded
count for each file and rule. A config that names a baseline file that does not exist
fails GK01.

**Why:** a repository with hundreds of findings cannot fix them before it adopts the
gate, and must not add more after. Counting by file and rule survives line moves; a
count by line would fail every edit.

**Rules out:** suppressing existing findings in the code, and excluding whole rules to
get to green.

## DEC-008 — Bitbucket wrapper on Linux, PowerShell from the release tarball

`Templates/bitbucket-pipelines.yml` runs on a plain Ubuntu image and installs
PowerShell from its release tarball, checked against a pinned SHA-256.

**Why:** hosted Bitbucket runners are Linux. No current, stable PowerShell 7.6 image
was found in the Microsoft container registry's legacy repository, and a pinned
tarball is checked the same way gitleaks is.

## DEC-009 — One second-model review per pull request

The review record covers the branch from its merge base. Fixes after it are answered,
not reviewed again.

**Why:** each new review is a fresh session that finds a different subset of problems
and never settles; the cost of re-reviewing every fix is unbounded.
