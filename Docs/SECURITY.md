# Security

| Item | Value |
|---|---|
| Version | unreleased (first tag pending) |
| Last audit | not yet audited |
| Findings resolved | none recorded |
| Tests | 82 static tests |

## 1. Secret scanning

**Status:** implemented (GK05, GK06, GK07).
**Why:** a secret that reaches a remote has to be treated as leaked.
**How:** gitleaks 8.30.1 scans the working tree, every commit not yet on a remote (or
the commits a branch adds, with `-Base`), and every one of those commit messages
through `gitleaks stdin`. The messages are also matched against the message patterns.
**Contract:** a found value is never printed in full: gitleaks runs with `--redact`,
and a pattern match shows its first six characters only.

## 2. Pinned, hash-checked tools

**Status:** implemented (`Install-GateTool.ps1`, `Templates/bitbucket-pipelines.yml`).
**Why:** a tool fetched by name at run time can change underneath the gate.
**How:** PSScriptAnalyzer and Pester are installed at exact versions from PSGallery.
gitleaks and, in the Bitbucket template, PowerShell are downloaded from their GitHub
releases and checked against a pinned SHA-256 before they are unpacked; a mismatch
deletes the download and stops.
**Contract:** GK02 fails unless the exact versions are present.

## 3. Config cannot run code

**Status:** implemented (GK01).
**Why:** a gate whose config can run commands can be made to pass by its config.
**How:** `gate.config.psd1` is read with `Import-PowerShellDataFile`, which accepts only
data. Every path is checked to be relative and inside the repository (CF-004).
**Contract:** an invalid config stops the gate with exit 1.

## 4. Agent permission files

**Status:** implemented (GK08).
**Why:** a committed agent settings file decides what an AI agent may run without
asking; a loosened rule should be a visible, deliberate change.
**How:** each documented settings file is compared with its entry in the permissions
file: every deny rule present, no allow rule or setting beyond the documented ones. A
committed settings file with no entry fails.
**Contract:** loosening the rules means changing the permissions file in the same diff.

## 5. Confined reviewer session

**Status:** implemented (`Invoke-ModelReview.ps1`).
**Why:** the reviewer reads untrusted change content; it must not be able to act on it.
**How:** the review runs in a fresh git worktree holding only committed files, with
`--restricted`, `--safe-mode`, `--strict-mcp-config`, read-only tools and no session
persistence.
**Contract:** the reviewer can read the reviewed commit and nothing else, and cannot
run commands or write files.

## 6. CI least privilege

**Status:** implemented (`Templates/github/gate.yml`).
**How:** a read-only token, the `pull_request` trigger only, no secrets, credentials not
kept in the checkout, and the one action pinned to a full commit SHA.

## Open items

- The Bitbucket template uses `ubuntu:24.04` by tag, not by digest.
- The Linux path has not run yet.
- The review record is the author's attestation: the gate proves it covers the branch
  and is answered, not that the session ran as recorded.
- The message patterns catch values with a known shape only; a real name that matches
  no pattern is left to review.

## Audit record

| Date | Version | Findings | Resolution |
|---|---|---|---|
| — | — | No audit yet | — |

## Code signing guidance

| Context | Policy | Files to sign |
|---|---|---|
| Developer workstation | RemoteSigned | none for local clones |
| Host that requires signed scripts | AllSigned | every `.ps1` in `Scripts/` and `Scripts/Lib/`, every `.psm1` in `Analyzer/Rules/` |

Procedure: sign with `Set-AuthenticodeSignature -Certificate <code-signing cert>
-TimestampServer <timestamp URL>`, then confirm with `Get-AuthenticodeSignature`. Sign
in the target repository after each `git subtree pull`, since an update replaces the
files.
