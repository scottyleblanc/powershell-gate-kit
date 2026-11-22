# Versioning

## Commit message format

Conventional Commits: `type(scope): description`, in the imperative, lower case.

```
feat(gate): add the permissions check
fix(review): read the record path from the config
```

Commit messages are part of the kit's history and are listed in a target repository's
squashed subtree commit, so they follow DEC-002: no owner names and no rule IDs from
another repository.

## Commit types

| Type | Use |
|---|---|
| `feat` | A new check, rule, script or template |
| `fix` | A check that passes or fails the wrong thing |
| `sec` | A change to a security mechanism in `Docs/SECURITY.md`; maps to `[SEC]` items in `TODO.md` |
| `docs` | Documents only |
| `test` | Tests only |
| `chore` | Housekeeping with no effect on behaviour |

## SemVer

The commit types set the bump; GK09 checks it (VR-003, DEC-025):

| Commits since the latest tag | Bump |
|---|---|
| A `type!:` subject or a `BREAKING CHANGE:` footer | Major; minor while the major number is 0 |
| `feat` | Minor |
| `fix` or `sec` | Patch |
| Only `docs`, `test` or `chore` | No release; their CHANGELOG entries wait under `[Unreleased]` |

What each bump means:

- **Patch**: a check that passed or failed the wrong thing, or a security fix.
- **Minor**: a new check, rule, config key or template, off by default or passing on
  every repository that passed before.
- **Major**: a change that can fail a repository that passed before: a new core check,
  a stricter rule, a renamed or removed config key, a new `SchemaVersion`. Before 1.0
  it moves the minor number.

A breaking change carries a `BREAKING CHANGE:` footer and a CHANGELOG entry saying what
a target repository must change. The footer is the only way the bump can see it: a
stricter rule committed as a plain `feat` or `fix` is numbered as one.

## Branching

One branch per piece of work off `main`, merged with `--no-ff`. Tags `vMAJOR.MINOR.PATCH`
go on `main` after the merge. A target repository pulls a tag:
`git subtree pull --prefix=tools/gate <kit-remote> v0.1.0 --squash`.

## Releasing

Every pull request with a `feat`, `fix`, `sec` or breaking commit is a release:

1. Record the changes under `## [Unreleased]` in `Docs/CHANGELOG.md`, as usual.
2. After the branch's last commit, run
   `pwsh -NoProfile -File ./Scripts/Update-ReleaseVersion.ps1`. It sets
   `Gate/version.psd1` and gives the `[Unreleased]` entries their
   `## [x.y.z] - date` heading. Set the `Version` row in `README.md` and
   `Docs/SECURITY.md` to the same number. Commit all four files.
3. Open the pull request. GK09 fails, in the hook and in CI, while the version is not
   the one the commits call for.
4. After the merge, `.github/workflows/release.yml` tags `main` with the version.

A commit that raises the bump after step 2 (a `feat` after a `fix`) means running the
script again; it renames the release section.

## Version, commit and changelog

Each release has a `## [x.y.z] - date` CHANGELOG section, the same number in
`Gate/version.psd1`, and a tag of that number on `main`. The number follows from the
latest tag and the commit types since it. `TODO.md` and `CHANGELOG.md` change in the
same commit as the code they describe.
