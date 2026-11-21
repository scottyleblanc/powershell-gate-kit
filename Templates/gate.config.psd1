@{
    # Gate configuration for this repository. Copy to the repository root as
    # gate.config.psd1. Read by tools/gate/Scripts/Invoke-Gate.ps1 (check GK01, rules
    # CF-001 to CF-005). Every path is relative to the repository root and uses /
    # separators. A key left out takes the default shown here.

    SchemaVersion = 1

    # The optional checks. The core checks (GK01 to GK08) always run.
    Checks = @{
        Review  = $true    # GK10, with -Base: the second-model review record
        Version = $false   # GK09: one version everywhere, and the tag rule with -Base
        Unit    = $false   # GK11, with -Unit: the repository's unit test script
    }

    # GK03. The folders analyzed, recursively. Files matching Exclude are skipped.
    # ExcludeRules turns off analyzer rules for this repository; each one is a gap, so
    # say why beside it. ExcludeRulesByPath turns rules off under one folder only, as
    # folder = rule names; say why beside each. Baseline names the file
    # Update-AnalyzerBaseline.ps1 writes, or '' for none.
    Analyzer = @{
        Paths              = @()     # for example @('source', 'scripts')
        Exclude            = @('*.Tests.ps1')
        ExcludeRules       = @()
        ExcludeRulesByPath = @{}     # for example @{ 'scripts' = @('PSAvoidUsingWriteHost') }
        Baseline           = ''      # for example 'gate/analyzer-baseline.psd1'
    }

    # GK04. A folder of Pester tests that read source text, or '' for none.
    StaticTests = ''

    # GK05 to GK07. This repository's gitleaks config, or '' for the kit's default
    # (tools/gate/Config/gitleaks.toml). Start from tools/gate/Templates/gitleaks.toml.
    Gitleaks = ''

    # GK07. This repository's commit message patterns, or '' for the kit's default
    # (tools/gate/Config/message-patterns.psd1). Start from
    # tools/gate/Templates/message-patterns.psd1.
    MessagePatterns = ''

    # GK08. The documented agent permission rules, or '' when no agent settings file is
    # committed. Start from tools/gate/Templates/agent-permissions.psd1.
    Permissions = ''

    # GK10. Record is the file Invoke-ModelReview.ps1 writes. Exempt lists files whose
    # change alone needs no review, such as a test-evidence file committed last.
    Review = @{
        Record = 'Review/LastReview.json'
        Exempt = @()
    }

    # GK09. Manifest holds ModuleVersion; Changelog has '## [x.y.z]' release headings;
    # NotesFiles each hold a 'Version : x.y.z' line. With -Base, tags are TagPrefix plus
    # the version, and a change to a PackageInputs path (a file, or a folder ending in /)
    # under a version already tagged fails until the version is bumped.
    Version = @{
        Manifest      = ''
        Changelog     = ''
        NotesFiles    = @()
        TagPrefix     = 'v'
        PackageInputs = @()
    }

    # GK11. A script that runs the unit tests and exits 0 only when they pass. It owns
    # its own coverage floor.
    Unit = @{
        Script = ''
    }
}
