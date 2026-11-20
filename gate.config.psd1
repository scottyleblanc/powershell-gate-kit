@{
    # The kit's own gate configuration: the kit is gated by itself (Docs/decisions.md,
    # DEC-006). See Templates/gate.config.psd1 for every key.

    SchemaVersion = 1

    Checks = @{
        Review  = $true
        Version = $false
        Unit    = $false
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
    Permissions     = ''

    Review = @{
        Record = 'Review/LastReview.json'
        Exempt = @()
    }
}
