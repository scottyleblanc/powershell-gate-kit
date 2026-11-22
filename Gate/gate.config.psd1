@{
    # The kit's own gate configuration: the kit is gated by itself (Docs/decisions.md,
    # DEC-006). See Templates/gate.config.psd1 for every key.

    SchemaVersion = 1

    Checks = @{
        # Off for the kit itself: its pull requests carry no model review record
        # (DEC-020). The template default stays on for target repositories.
        Review  = $false
        Version = $true
        Unit    = $false
        Files   = $true
    }

    # GK09: every merged feat, fix or sec pull request is a release. The version is the
    # one its commits call for since the latest tag (VR-003), set by
    # Scripts/Update-ReleaseVersion.ps1; .github/workflows/release.yml tags main with it
    # (DEC-025). No PackageInputs: VR-003 decides when the number moves.
    Version = @{
        Manifest    = 'Gate/version.psd1'
        Changelog   = 'Docs/CHANGELOG.md'
        TagPrefix   = 'v'
        FromCommits = $true
    }

    Analyzer = @{
        Paths        = @('Scripts', 'Analyzer')
        Exclude      = @('*.Tests.ps1')
        ExcludeRules = @()
        Baseline     = ''
    }

    StaticTests     = 'Tests'
    Gitleaks        = ''
    MessagePatterns = ''

    # GK07 (CM-002): commits carry only GitHub no-reply addresses: the maintainer's,
    # and GitHub's own for merges made on the web (DEC-022).
    CommitEmails    = @('^\d+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$', '^noreply@github\.com$')

    # GK08: the kit's own committed agent settings match this record (DEC-024).
    Permissions     = 'Gate/agent-permissions.psd1'

    Review = @{
        Record = 'Review/LastReview.json'
        Exempt = @()
    }

    # The checks the pre-push hook skips; .github/workflows/gate.yml runs them on every
    # pull request (DEC-020).
    Quick = @('GK03', 'GK04')
}
