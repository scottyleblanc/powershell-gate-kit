#Requires -Version 7.6

# The gate's behaviour, run against throwaway repositories. Each fixture is a new git
# repository under TestDrive with the kit copied in at tools/gate, as a target
# repository holds it. Each case proves a check passes clean input and fails the
# defect it exists for.
#
# Values that look like secrets are built at run time, so this file holds none and the
# kit's own secret scan stays clean.

BeforeAll {
    $script:kitRoot = Split-Path -Path $PSScriptRoot -Parent

    # Runs git in a fixture with a fixed test identity and no signing or hooks.
    function Invoke-FixtureGit {
        param([string]$Repo, [string[]]$Argument)
        $common = @('-C', $Repo, '-c', 'user.name=gate-test', '-c', 'user.email=gate-test@example.com', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null')
        $out = & git @common @Argument 2>&1
        if ($LASTEXITCODE -ne 0) { throw "git $($Argument -join ' ') failed: $out" }
        $out
    }

    # Creates a fixture repository with the kit at tools/gate and the given config.
    function New-FixtureRepo {
        param([string]$Name, [string]$Config, [switch]$NoConfig)
        $repo = Join-Path -Path $TestDrive -ChildPath $Name
        $null = New-Item -Path $repo -ItemType Directory
        $null = Invoke-FixtureGit -Repo $repo -Argument @('init', '--quiet', '-b', 'main')
        $kit = Join-Path -Path $repo -ChildPath 'tools' -AdditionalChildPath 'gate'
        $null = New-Item -Path $kit -ItemType Directory -Force
        foreach ($folder in 'Scripts', 'Analyzer', 'Config', 'Review', 'Docs') {
            Copy-Item -Path (Join-Path -Path $script:kitRoot -ChildPath $folder) -Destination $kit -Recurse
        }
        if (-not $NoConfig) { Set-FixtureFile -Repo $repo -Path 'gate.config.psd1' -Text $Config }
        $repo
    }

    function Set-FixtureFile {
        param([string]$Repo, [string]$Path, [string]$Text)
        $full = Join-Path -Path $Repo -ChildPath $Path
        $null = New-Item -Path (Split-Path -Path $full -Parent) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($full, $Text, [System.Text.UTF8Encoding]::new($false))
    }

    function Save-FixtureCommit {
        param([string]$Repo, [string]$Message)
        $null = Invoke-FixtureGit -Repo $Repo -Argument @('add', '--all')
        $null = Invoke-FixtureGit -Repo $Repo -Argument @('commit', '--quiet', '-m', $Message)
        (Invoke-FixtureGit -Repo $Repo -Argument @('rev-parse', 'HEAD')) | Select-Object -First 1
    }

    # Runs the fixture's gate in its own process and returns its output and exit code.
    function Invoke-FixtureGate {
        param([string]$Repo, [string[]]$Argument = @())
        $gate   = Join-Path -Path $Repo -ChildPath 'tools' -AdditionalChildPath 'gate', 'Scripts', 'Invoke-Gate.ps1'
        $output = @(& pwsh -NoProfile -File $gate @Argument 2>&1 | ForEach-Object { "$PSItem" -replace '\x1b\[[0-9;]*m', '' })
        [PSCustomObject]@{ Output = $output; ExitCode = $LASTEXITCODE; Text = $output -join "`n" }
    }

    $script:minimal = "@{ SchemaVersion = 1 }"
}

Describe 'Invoke-Gate' -Tag 'Static' {

    Context 'A fresh, empty repository' {

        It 'GK01 to GK08 pass on a repository with no commits and the minimal config' {
            $repo   = New-FixtureRepo -Name 'fresh' -Config $script:minimal
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match '\[PASS\] gate: all 8 checks passed'
            $result.Text | Should -Match 'GK06 commits : no commits yet; nothing to scan'
            $result.ExitCode | Should -Be 0
        }
    }

    Context 'GK01 config' {

        It 'CF-001 fails and stops when gate.config.psd1 is missing' {
            $repo   = New-FixtureRepo -Name 'noconfig' -NoConfig
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match '\[FAIL\] GK01 config'
            $result.Text | Should -Match 'CF-001'
            $result.Text | Should -Not -Match 'GK02'
            $result.ExitCode | Should -Be 1
        }

        It 'CF-003 fails an unknown key' {
            $repo   = New-FixtureRepo -Name 'unknownkey' -Config "@{ SchemaVersion = 1; Analyser = @{} }"
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match "unknown key 'Analyser' \(CF-003\)"
            $result.ExitCode | Should -Be 1
        }

        It 'CF-004 fails a path that leaves the repository' {
            $repo   = New-FixtureRepo -Name 'escape' -Config "@{ SchemaVersion = 1; StaticTests = '../elsewhere' }"
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match 'CF-004'
            $result.ExitCode | Should -Be 1
        }

        It 'CF-005 fails an optional check turned on without its settings' {
            $repo   = New-FixtureRepo -Name 'unitnoscript' -Config "@{ SchemaVersion = 1; Checks = @{ Unit = `$true } }"
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match 'CF-005'
            $result.ExitCode | Should -Be 1
        }
    }

    Context 'GK03 analyzer' {

        BeforeAll {
            $script:analyzerRepo = New-FixtureRepo -Name 'analyzer' -Config "@{ SchemaVersion = 1; Analyzer = @{ Paths = @('source') } }"
            Set-FixtureFile -Repo $script:analyzerRepo -Path 'source/Get-Thing.ps1' -Text "function Get-Thing { param([string]`$Name) 1..3 | ForEach-Object { `$_ } }`n"
        }

        It 'AN-001 fails a finding the baseline does not hold, including a kit rule' {
            $result = Invoke-FixtureGate -Repo $script:analyzerRepo
            $result.Text | Should -Match '\[FAIL\] GK03 analyzer'
            $result.Text | Should -Match 'Measure-AN008UsePSItem'
            $result.ExitCode | Should -Be 1
        }

        It 'AN-001 passes once Update-AnalyzerBaseline.ps1 records the findings' {
            Set-FixtureFile -Repo $script:analyzerRepo -Path 'gate.config.psd1' -Text "@{ SchemaVersion = 1; Analyzer = @{ Paths = @('source'); Baseline = 'gate/analyzer-baseline.psd1' } }"
            $update = Join-Path -Path $script:analyzerRepo -ChildPath 'tools' -AdditionalChildPath 'gate', 'Scripts', 'Update-AnalyzerBaseline.ps1'
            $null   = & pwsh -NoProfile -File $update 2>&1
            $LASTEXITCODE | Should -Be 0
            $result = Invoke-FixtureGate -Repo $script:analyzerRepo
            $result.Text | Should -Match '\[PASS\] GK03 analyzer : 0 new finding\(s\) over 1 files; \d+ held by the baseline'
        }

        It 'AN-001 fails a new finding added after the baseline' {
            Set-FixtureFile -Repo $script:analyzerRepo -Path 'source/Get-Other.ps1' -Text "function Get-Other { [OutputType([int])] param([int]`$N) `$N }`nif (`$env:OS) { 1 }`n"
            $result = Invoke-FixtureGate -Repo $script:analyzerRepo
            $result.Text | Should -Match 'source/Get-Other.ps1:\d+ Measure-AN003PlatformFromAutomaticVariable'
            $result.ExitCode | Should -Be 1
        }
    }

    Context 'GK05 to GK07 secrets, commits and messages' {

        It 'SE-001 fails a secret in the working tree' {
            $repo  = New-FixtureRepo -Name 'secret' -Config $script:minimal
            $token = 'gh' + 'p_' + ('aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3z5A' )
            Set-FixtureFile -Repo $repo -Path 'notes.txt' -Text "token = $token`n"
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match '\[FAIL\] GK05 secrets'
            $result.Text | Should -Not -Match $token
            $result.ExitCode | Should -Be 1
        }

        It 'SE-002 fails a secret in an unpushed commit that a later commit removed' {
            $repo  = New-FixtureRepo -Name 'history' -Config $script:minimal
            $token = 'gh' + 'p_' + ('aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3z5A')
            Set-FixtureFile -Repo $repo -Path 'notes.txt' -Text "token = $token`n"
            $null = Save-FixtureCommit -Repo $repo -Message 'add notes'
            Set-FixtureFile -Repo $repo -Path 'notes.txt' -Text "no token`n"
            $null = Save-FixtureCommit -Repo $repo -Message 'remove the token'
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match '\[PASS\] GK05 secrets'
            $result.Text | Should -Match '\[FAIL\] GK06 commits'
            $result.ExitCode | Should -Be 1
        }

        It 'CM-001 fails a commit message that holds a private key header' {
            $repo = New-FixtureRepo -Name 'message' -Config $script:minimal
            Set-FixtureFile -Repo $repo -Path 'readme.txt' -Text "hello`n"
            $null = Save-FixtureCommit -Repo $repo -Message ("add readme`n`n" + '-----BEGIN ' + 'RSA PRIVATE KEY-----')
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match '\[FAIL\] GK07 messages'
            $result.Text | Should -Match 'no private key block'
            $result.ExitCode | Should -Be 1
        }
    }

    Context 'GK08 permissions' {

        BeforeAll {
            $script:settings = '{ "permissions": { "allow": ["Bash(git status *)"], "deny": ["Bash(git push *)"] } }'
            $script:documented = @'
@{ Files = @( @{ Path = '.claude/settings.json'; Keys = @('permissions'); PermissionKeys = @('allow', 'deny'); Allow = @('Bash(git status *)'); Deny = @('Bash(git push *)') } ) }
'@
        }

        It 'PM-002 fails a committed agent settings file that is not documented' {
            $repo = New-FixtureRepo -Name 'pmundocumented' -Config $script:minimal
            Set-FixtureFile -Repo $repo -Path '.claude/settings.json' -Text $script:settings
            $null   = Save-FixtureCommit -Repo $repo -Message 'add settings'
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match 'PM-002'
            $result.ExitCode | Should -Be 1
        }

        It 'PM-001 passes a file that matches its documented rules' {
            $repo = New-FixtureRepo -Name 'pmmatch' -Config "@{ SchemaVersion = 1; Permissions = 'gate/agent-permissions.psd1' }"
            Set-FixtureFile -Repo $repo -Path '.claude/settings.json' -Text $script:settings
            Set-FixtureFile -Repo $repo -Path 'gate/agent-permissions.psd1' -Text $script:documented
            $null   = Save-FixtureCommit -Repo $repo -Message 'add settings'
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match '\[PASS\] GK08 permissions : 1 agent settings file\(s\) match'
        }

        It 'PM-001 fails a removed deny rule, a new allow rule and a new setting' {
            $repo = New-FixtureRepo -Name 'pmloosened' -Config "@{ SchemaVersion = 1; Permissions = 'gate/agent-permissions.psd1' }"
            Set-FixtureFile -Repo $repo -Path '.claude/settings.json' -Text '{ "defaultMode": "bypassPermissions", "permissions": { "allow": ["Bash(git status *)", "Bash(git push *)"], "deny": [] } }'
            Set-FixtureFile -Repo $repo -Path 'gate/agent-permissions.psd1' -Text $script:documented
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match "undocumented setting 'defaultMode'"
            $result.Text | Should -Match 'documented deny rule missing'
            $result.Text | Should -Match 'undocumented allow rule'
            $result.ExitCode | Should -Be 1
        }
    }

    Context 'GK09 version' {

        BeforeAll {
            $script:versionConfig = "@{ SchemaVersion = 1; Checks = @{ Version = `$true }; Version = @{ Manifest = 'source/Thing.psd1'; Changelog = 'CHANGELOG.md'; PackageInputs = @('source/') } }"
        }

        It 'VR-001 fails when the manifest and the changelog disagree' {
            $repo = New-FixtureRepo -Name 'vrmismatch' -Config $script:versionConfig
            Set-FixtureFile -Repo $repo -Path 'source/Thing.psd1' -Text "@{ ModuleVersion = '1.2.0' }"
            Set-FixtureFile -Repo $repo -Path 'CHANGELOG.md' -Text "# Changelog`n`n## [1.1.0] - 2026-01-01`n"
            $result = Invoke-FixtureGate -Repo $repo
            $result.Text | Should -Match 'newest release 1.1.0 \(VR-001\)'
            $result.ExitCode | Should -Be 1
        }

        It 'VR-002 fails a package change under a version already tagged' {
            $repo = New-FixtureRepo -Name 'vrtagged' -Config $script:versionConfig
            Set-FixtureFile -Repo $repo -Path 'source/Thing.psd1' -Text "@{ ModuleVersion = '1.2.0' }"
            Set-FixtureFile -Repo $repo -Path 'CHANGELOG.md' -Text "# Changelog`n`n## [1.2.0] - 2026-01-01`n"
            $null = Save-FixtureCommit -Repo $repo -Message 'release 1.2.0'
            $null = Invoke-FixtureGit -Repo $repo -Argument @('tag', 'v1.2.0')
            $null = Invoke-FixtureGit -Repo $repo -Argument @('switch', '--quiet', '-c', 'feature')
            Set-FixtureFile -Repo $repo -Path 'source/Thing.ps1' -Text "# changed`n"
            $null   = Save-FixtureCommit -Repo $repo -Message 'change the package'
            $result = Invoke-FixtureGate -Repo $repo -Argument @('-Base', 'main')
            $result.Text | Should -Match 'a package input changed since main but v1.2.0 is already released'
            $result.ExitCode | Should -Be 1
        }
    }

    Context 'GK10 review' {

        BeforeAll {
            # A repository with one commit on main and a branch that changes a file.
            $script:reviewRepo = New-FixtureRepo -Name 'review' -Config $script:minimal
            Set-FixtureFile -Repo $script:reviewRepo -Path 'readme.txt' -Text "one`n"
            $script:mainCommit = Save-FixtureCommit -Repo $script:reviewRepo -Message 'first'
            $null = Invoke-FixtureGit -Repo $script:reviewRepo -Argument @('switch', '--quiet', '-c', 'feature')
            Set-FixtureFile -Repo $script:reviewRepo -Path 'readme.txt' -Text "two`n"
            $script:changeCommit = Save-FixtureCommit -Repo $script:reviewRepo -Message 'change the readme'

            function Set-ReviewRecord {
                param([string]$Response)
                $record = [ordered]@{
                    SchemaVersion = 1
                    Commit        = $script:changeCommit
                    BaseCommit    = $script:mainCommit
                    Completed     = $true
                    Findings      = @([ordered]@{ Id = 'F1'; Severity = 'Low'; Response = $Response })
                }
                Set-FixtureFile -Repo $script:reviewRepo -Path 'Review/LastReview.json' -Text (ConvertTo-Json -InputObject $record -Depth 4)
                $null = Save-FixtureCommit -Repo $script:reviewRepo -Message 'record the review'
            }
        }

        It 'is off without -Base' {
            $result = Invoke-FixtureGate -Repo $script:reviewRepo
            $result.Text | Should -Match '\[OFF\]  GK10 review : runs only with -Base'
        }

        It 'RV-001 fails a branch with no review record' {
            $result = Invoke-FixtureGate -Repo $script:reviewRepo -Argument @('-Base', 'main')
            $result.Text | Should -Match '\[FAIL\] GK10 review'
            $result.Text | Should -Match 'Review/LastReview.json is not in HEAD'
        }

        It 'RV-001 fails a finding with no answer' {
            Set-ReviewRecord -Response ''
            $result = Invoke-FixtureGate -Repo $script:reviewRepo -Argument @('-Base', 'main')
            $result.Text | Should -Match 'finding F1 is not answered'
        }

        It 'RV-001 passes a record that covers the branch with every finding answered' {
            Set-ReviewRecord -Response 'Accepted: a test record'
            $result = Invoke-FixtureGate -Repo $script:reviewRepo -Argument @('-Base', 'main')
            $result.Text | Should -Match '\[PASS\] GK10 review'
            $result.ExitCode | Should -Be 0
        }
    }

    Context 'GK11 unit' {

        It 'UT-001 fails when the unit script exits 1, and is off without -Unit' {
            $repo = New-FixtureRepo -Name 'unit' -Config "@{ SchemaVersion = 1; Checks = @{ Unit = `$true }; Unit = @{ Script = 'scripts/Invoke-UnitTest.ps1' } }"
            Set-FixtureFile -Repo $repo -Path 'scripts/Invoke-UnitTest.ps1' -Text "Write-Output '[FAIL] unit: 1 failed'`nexit 1`n"
            (Invoke-FixtureGate -Repo $repo).Text | Should -Match '\[OFF\]  GK11 unit : runs only with -Unit'
            $result = Invoke-FixtureGate -Repo $repo -Argument @('-Unit')
            $result.Text | Should -Match '\[FAIL\] GK11 unit'
            $result.ExitCode | Should -Be 1
        }
    }
}
