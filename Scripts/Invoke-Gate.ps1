#Requires -Version 7.6
<#
.SYNOPSIS
    Runs every check in one command: the gate.

.DESCRIPTION
    Reads gate.config.psd1 at the repository root, runs each check in turn, reports
    [PASS], [FAIL] or [OFF] for each, and exits 1 if any check failed. Every check runs
    even after an earlier one fails, so one run shows every problem. The one exception
    is GK01: a config that fails its check stops the gate, because no other check can
    be trusted to read it. The rules each check enforces are in Docs\rules.md.

      GK01 config       gate.config.psd1 is present and valid (CF-001 to CF-005)
      GK02 tools        PSScriptAnalyzer 1.25.0, gitleaks 8.30.1, Pester 5 and git
      GK03 analyzer     PSScriptAnalyzer with the kit's settings and rules over the
                        folders in Analyzer.Paths. A finding the repository's baseline
                        does not hold fails (AN-001 to AN-009)
      GK04 static       The Pester tests in the StaticTests folder (ST-001)
      GK05 secrets      gitleaks over the working tree (SE-001)
      GK06 commits      gitleaks over every commit not yet on a remote (SE-002)
      GK07 messages     The messages of those commits, through gitleaks and the
                        message patterns. gitleaks does not read commit messages, so
                        they are checked separately (CM-001)
      GK08 permissions  The committed agent permission files match the documented
                        rules (PM-001, PM-002)
      GK09 version      Optional. The manifest, the newest CHANGELOG release and every
                        listed .NOTES block name the same version; with -Base, the tags
                        too (VR-001, VR-002)
      GK10 review       On by default; only with -Base. The second-model review record
                        covers the branch and every finding is answered (RV-001)
      GK11 unit         Optional; only with -Unit. The repository's unit test script
                        passes (UT-001)

    "Not yet on a remote" means not reachable from any remote-tracking branch, as git
    last saw it. A branch never pushed has all its commits checked. A check with
    nothing to scan passes and says so.

    In CI every commit is already on a remote, so "not yet on a remote" would check
    nothing. -Base names the branch a pull request merges into; with it, GK06 and GK07
    check the commits in Base..HEAD instead, GK09 also checks the tags, and GK10 runs.

    Found values are never printed in full: gitleaks runs with --redact, and a pattern
    match shows only its first characters.

.PARAMETER Base
    The branch a pull request merges into, as a git revision (for example
    origin/main). CI passes it; the pre-push hook does not.

.PARAMETER Unit
    Also run GK11, when gate.config.psd1 turns it on.

.PARAMETER Quick
    Skip GK03, the slowest check, and report it [OFF]. The pre-push hook passes it;
    CI does not, so every pull request is still analyzed (DEC-011).

.EXAMPLE
    pwsh -NoProfile -File ./tools/gate/Scripts/Invoke-Gate.ps1

    Runs the gate. Exits 0 when every check passes.

.EXAMPLE
    pwsh -NoProfile -File ./tools/gate/Scripts/Invoke-Gate.ps1 -Quick

    Runs every check except GK03. This is what the pre-push hook runs.

.EXAMPLE
    pwsh -NoProfile -File ./tools/gate/Scripts/Invoke-Gate.ps1 -Unit -Base origin/main

    Runs the gate over the commits a pull request adds to main, with the tag rule and
    the review check, then the unit tests. This is what CI runs.

.NOTES
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Runs from
    any working directory: the repository is the git checkout that holds this script.
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_./-]*$')]
    [string]$Base,

    [Parameter()]
    [switch]$Unit,

    [Parameter()]
    [switch]$Quick
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'Lib' -AdditionalChildPath 'GateLib.ps1')

$kitRoot  = Split-Path -Path $PSScriptRoot -Parent
$repoRoot = Get-GateRepoRoot -Path $PSScriptRoot
$kitPath  = [System.IO.Path]::GetRelativePath($repoRoot, $kitRoot).Replace('\', '/')
$kitPath  = if ($kitPath -eq '.') { '.' } else { "./$kitPath" }

$requiredAnalyzer = [version]'1.25.0'
$requiredGitleaks = '8.30.1'

$results = [System.Collections.Generic.List[object]]::new()

# Records one check. $Detail lines are printed under a failure.
function Add-Result {
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [bool] $Passed,
        [Parameter(Mandatory)] [string] $Summary,
        [Parameter()] [string[]] $Detail = @()
    )
    $results.Add([PSCustomObject]@{ Id = $Id; Name = $Name; Passed = $Passed })
    $label = if ($Passed) { '[PASS]' } else { '[FAIL]' }
    Write-Output "$label $Id $Name : $Summary"
    if (-not $Passed) { foreach ($line in $Detail) { Write-Output "       $line" } }
}

# Reports a check that gate.config.psd1, or a missing switch, leaves out.
function Write-Off {
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Reason
    )
    Write-Output "[OFF]  $Id $Name : $Reason"
}

# Shows the first characters of a value and hides the rest.
function Get-Prefix {
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Value)
    $Value.Substring(0, [Math]::Min(6, $Value.Length)) + '***'
}

# Runs a PowerShell script in its own process and returns its output lines and exit code.
function Invoke-ChildScript {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [string] $Script,
        [Parameter()] [string[]] $Argument = @()
    )
    # Colour codes are stripped so the [-] and [FAIL] lines can be matched.
    $output = @(& pwsh -NoProfile -File $Script @Argument 2>&1 | ForEach-Object { "$PSItem" -replace '\x1b\[[0-9;]*m', '' })
    [PSCustomObject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

# -- GK01 config -------------------------------------------------------------

$loaded = Import-GateConfig -RepoRoot $repoRoot
$config = $loaded.Config
if ($loaded.Problems.Count -gt 0) {
    Add-Result -Id 'GK01' -Name 'config' -Passed $false -Summary "$($loaded.Problems.Count) problem(s); no other check ran" -Detail $loaded.Problems
    Write-Output '[FAIL] gate: gate.config.psd1 is not valid, so no other check ran'
    exit 1
}
$onList = @($config.Checks.Keys | Where-Object { $config.Checks[$PSItem] })
Add-Result -Id 'GK01' -Name 'config' -Passed $true -Summary "valid; optional checks on: $(if ($onList.Count -gt 0) { $onList -join ', ' } else { 'none' })"

# -- GK02 tools --------------------------------------------------------------

$analyzerModule  = Get-Module -Name PSScriptAnalyzer -ListAvailable | Where-Object { $PSItem.Version -eq $requiredAnalyzer } | Select-Object -First 1
$pesterModule    = Get-Module -Name Pester -ListAvailable | Where-Object { $PSItem.Version.Major -ge 5 } | Select-Object -First 1
$gitleaks        = Get-Command -Name gitleaks -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$gitleaksVersion = if ($null -ne $gitleaks) { ((& $gitleaks.Source version) | Select-Object -First 1).Trim() } else { $null }
$git             = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

$toolProblems = @(
    if ($null -eq $analyzerModule) { "PSScriptAnalyzer $requiredAnalyzer is not installed: run $kitPath/Scripts/Install-GateTool.ps1" }
    if ($null -eq $pesterModule) { "Pester 5 is not installed: run $kitPath/Scripts/Install-GateTool.ps1" }
    if ($null -eq $gitleaks) { "gitleaks is not on PATH: run $kitPath/Scripts/Install-GateTool.ps1" }
    elseif ($gitleaksVersion -ne $requiredGitleaks) { "gitleaks $gitleaksVersion found; $requiredGitleaks is required" }
    if ($null -eq $git) { 'git is not on PATH' }
)
$toolSummary = if ($toolProblems.Count -eq 0) { "PSScriptAnalyzer $requiredAnalyzer, gitleaks $requiredGitleaks, Pester $($pesterModule.Version), git" } else { "$($toolProblems.Count) missing or wrong version" }
Add-Result -Id 'GK02' -Name 'tools' -Passed ($toolProblems.Count -eq 0) -Summary $toolSummary -Detail $toolProblems

# -- GK03 analyzer -----------------------------------------------------------

if ($Quick) {
    Write-Off -Id 'GK03' -Name 'analyzer' -Reason 'skipped by -Quick; CI runs it'
}
elseif ($null -eq $analyzerModule) {
    Add-Result -Id 'GK03' -Name 'analyzer' -Passed $false -Summary 'not run: PSScriptAnalyzer is missing'
}
else {
    Import-Module -Name PSScriptAnalyzer -RequiredVersion $requiredAnalyzer
    $analysis     = Invoke-GateAnalyzer -RepoRoot $repoRoot -KitRoot $kitRoot -Config $config
    $baselineFile = if ($config.Analyzer.Baseline) { Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.Analyzer.Baseline } else { '' }
    $compared     = Compare-AnalyzerBaseline -Findings $analysis.Findings -BaselineFile $baselineFile
    $detail       = @($compared.New | ForEach-Object { "$($PSItem.Path):$($PSItem.Line) $($PSItem.Rule): $($PSItem.Message)" })
    $summary      = if ($analysis.FileCount -eq 0) { 'no files to analyze' } else { "$($compared.New.Count) new finding(s) over $($analysis.FileCount) files" }
    if ($compared.Held -gt 0) { $summary += "; $($compared.Held) held by the baseline" }
    if ($compared.Shrinkable.Count -gt 0) { $summary += "; the baseline can shrink for $($compared.Shrinkable.Count) file and rule pair(s): run $kitPath/Scripts/Update-AnalyzerBaseline.ps1" }
    Add-Result -Id 'GK03' -Name 'analyzer' -Passed ($compared.New.Count -eq 0) -Summary $summary -Detail $detail
}

# -- GK04 static -------------------------------------------------------------

if (-not $config.StaticTests) {
    Add-Result -Id 'GK04' -Name 'static' -Passed $true -Summary 'no static test folder configured; nothing to run'
}
elseif ($null -eq $pesterModule) {
    Add-Result -Id 'GK04' -Name 'static' -Passed $false -Summary 'not run: Pester 5 is missing'
}
else {
    $staticFolder = Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.StaticTests
    $run          = Invoke-ChildScript -Script (Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-StaticTest.ps1') -Argument @('-Path', $staticFolder)
    $last         = @($run.Output | Where-Object { $PSItem -match '^\[(PASS|FAIL)\] static' }) | Select-Object -Last 1
    $failed       = @($run.Output | Where-Object { $PSItem -match '^\s*\[-\]' } | ForEach-Object { $PSItem.Trim() })
    $summary      = if ($last) { $last -replace '^\[(PASS|FAIL)\] static: ', '' } else { "exit $($run.ExitCode)" }
    Add-Result -Id 'GK04' -Name 'static' -Passed ($run.ExitCode -eq 0) -Summary $summary -Detail $failed
}

# -- GK05 to GK07 need gitleaks and git --------------------------------------

$gitleaksReady  = $null -ne $gitleaks -and $gitleaksVersion -eq $requiredGitleaks
$gitleaksConfig = if ($config.Gitleaks) { Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.Gitleaks } else { Join-Path -Path $kitRoot -ChildPath 'Config' -AdditionalChildPath 'gitleaks.toml' }

if (-not $gitleaksReady) {
    Add-Result -Id 'GK05' -Name 'secrets' -Passed $false -Summary "not run: gitleaks $requiredGitleaks is missing"
}
else {
    # Scanned as '.' from the root so fingerprints are relative and match .gitleaksignore (SE-001).
    Push-Location -LiteralPath $repoRoot
    try {
        $out  = @(& $gitleaks.Source dir . --config $gitleaksConfig --redact --no-banner 2>&1 | ForEach-Object { "$PSItem" })
        $exit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $summary = if ($exit -eq 0) { 'no leaks in the working tree' } else { 'leaks found in the working tree' }
    Add-Result -Id 'GK05' -Name 'secrets' -Passed ($exit -eq 0) -Summary $summary -Detail @($out | Where-Object { $PSItem -match 'Finding|File|Line|RuleID|leaks found' })
}

# Without -Base: commits not on any remote. With -Base: the commits a pull request adds.
$baseCommit = $null
$notReady   = $null
$hasHead    = $false
if ($null -eq $git) {
    $notReady = 'not run: git is not on PATH'
}
else {
    $null    = & $git.Source -C $repoRoot rev-parse --verify --quiet 'HEAD^{commit}' 2>$null
    $hasHead = $LASTEXITCODE -eq 0
    if ($Base) {
        $baseCommit = @(& $git.Source -C $repoRoot rev-parse --verify --quiet "$Base^{commit}" 2>$null) | Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or -not $baseCommit) { $notReady = "not run: base '$Base' is not a commit in this checkout" }
    }
}

$rangeArgs  = if ($Base) { @('HEAD', '--not', $baseCommit) } else { @('HEAD', '--not', '--remotes') }
$rangeLabel = if ($Base) { "commit(s) since $Base" } else { 'unpushed commit(s)' }

$unpushed = @()
if ($null -eq $notReady -and $hasHead) {
    $unpushed = @(& $git.Source -C $repoRoot rev-list @rangeArgs 2>$null)
    if ($LASTEXITCODE -ne 0) { $notReady = 'not run: git could not list the commits' }
}

if ($null -ne $notReady) {
    Add-Result -Id 'GK06' -Name 'commits' -Passed $false -Summary $notReady
    Add-Result -Id 'GK07' -Name 'messages' -Passed $false -Summary $notReady
}
elseif ($unpushed.Count -eq 0) {
    $none = if ($hasHead) { "no $rangeLabel" } else { 'no commits yet' }
    Add-Result -Id 'GK06' -Name 'commits' -Passed $true -Summary "$none; nothing to scan"
    Add-Result -Id 'GK07' -Name 'messages' -Passed $true -Summary "$none; nothing to scan"
}
else {
    if (-not $gitleaksReady) {
        Add-Result -Id 'GK06' -Name 'commits' -Passed $false -Summary "not run: gitleaks $requiredGitleaks is missing"
    }
    else {
        $out  = @(& $gitleaks.Source git $repoRoot --config $gitleaksConfig --redact --no-banner --log-opts ($rangeArgs -join ' ') 2>&1 | ForEach-Object { "$PSItem" })
        $exit = $LASTEXITCODE
        $summary = if ($exit -eq 0) { "no leaks in $($unpushed.Count) $rangeLabel" } else { "leaks found in $rangeLabel" }
        Add-Result -Id 'GK06' -Name 'commits' -Passed ($exit -eq 0) -Summary $summary -Detail @($out | Where-Object { $PSItem -match 'Finding|File|Commit|RuleID|leaks found' })
    }

    $patternFile = if ($config.MessagePatterns) { Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.MessagePatterns } else { Join-Path -Path $kitRoot -ChildPath 'Config' -AdditionalChildPath 'message-patterns.psd1' }
    $patterns    = @((Import-PowerShellDataFile -LiteralPath $patternFile).Patterns)
    $problems    = [System.Collections.Generic.List[string]]::new()

    foreach ($commit in $unpushed) {
        $short   = $commit.Substring(0, 7)
        $message = (& $git.Source -C $repoRoot log -1 --format=%B $commit) -join "`n"

        foreach ($pattern in $patterns) {
            foreach ($match in [regex]::Matches($message, $pattern.Pattern)) {
                if ($pattern.Allow -and $match.Value -match $pattern.Allow) { continue }
                $problems.Add("commit ${short}: $($pattern.Id) $($pattern.Title): $(Get-Prefix -Value $match.Value)")
            }
        }

        if ($gitleaksReady) {
            $null = $message | & $gitleaks.Source stdin --config $gitleaksConfig --redact --no-banner 2>&1
            if ($LASTEXITCODE -ne 0) { $problems.Add("commit ${short}: gitleaks found a secret in the message") }
        }
    }
    if (-not $gitleaksReady) { $problems.Add("gitleaks $requiredGitleaks is missing, so messages were checked against the patterns only") }

    Add-Result -Id 'GK07' -Name 'messages' -Passed ($problems.Count -eq 0) -Summary "messages of $($unpushed.Count) $rangeLabel, $($problems.Count) problem(s)" -Detail @($problems)
}

# -- GK08 permissions --------------------------------------------------------
# PM-001: each documented agent settings file keeps every documented deny rule, allows
# nothing beyond the documented allow rules and holds no undocumented key.
# PM-002: every committed agent settings file is documented.

$knownAgentFiles = @('.claude/settings.json', '.cursor/cli.json')
$documented      = @()
if ($config.Permissions) {
    $documented = @((Import-PowerShellDataFile -LiteralPath (Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.Permissions)).Files)
}
$permissionProblems = [System.Collections.Generic.List[string]]::new()

$tracked = @()
if ($null -ne $git -and $hasHead) { $tracked = @(& $git.Source -C $repoRoot ls-files -- @knownAgentFiles 2>$null) }
foreach ($path in $tracked) {
    if (@($documented | Where-Object { $PSItem.Path -eq $path }).Count -eq 0) {
        $permissionProblems.Add("${path}: committed but not documented in the permissions file (PM-002)")
    }
}

foreach ($entry in $documented) {
    $full = Resolve-GatePath -RepoRoot $repoRoot -RelativePath $entry.Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $permissionProblems.Add("$($entry.Path): documented but missing (PM-001)")
        continue
    }
    $settings = Get-Content -LiteralPath $full -Raw | ConvertFrom-Json -AsHashtable
    $block    = if ($settings -is [System.Collections.IDictionary]) { $settings['permissions'] } else { $null }
    if ($block -isnot [System.Collections.IDictionary]) {
        $permissionProblems.Add("$($entry.Path): no permissions block (PM-001)")
        continue
    }
    foreach ($key in @($settings.Keys | Where-Object { $PSItem -cnotin $entry.Keys })) { $permissionProblems.Add("$($entry.Path): undocumented setting '$key' (PM-001)") }
    foreach ($key in @($block.Keys | Where-Object { $PSItem -cnotin $entry.PermissionKeys })) { $permissionProblems.Add("$($entry.Path): undocumented setting 'permissions.$key' (PM-001)") }
    foreach ($rule in @($entry.Deny | Where-Object { $PSItem -cnotin @($block['deny']) })) { $permissionProblems.Add("$($entry.Path): documented deny rule missing: $rule (PM-001)") }
    foreach ($rule in @(@($block['allow']) | Where-Object { $PSItem -and $PSItem -cnotin $entry.Allow })) { $permissionProblems.Add("$($entry.Path): undocumented allow rule: $rule (PM-001)") }
}

$permissionSummary = if ($documented.Count -eq 0 -and $tracked.Count -eq 0) {
    'no agent settings file committed or documented; nothing to check'
}
elseif ($permissionProblems.Count -eq 0) {
    "$($documented.Count) agent settings file(s) match the documented rules"
}
else {
    'the agent settings files and the documented rules differ'
}
Add-Result -Id 'GK08' -Name 'permissions' -Passed ($permissionProblems.Count -eq 0) -Summary $permissionSummary -Detail @($permissionProblems)

# -- GK09 version ------------------------------------------------------------
# VR-001: the manifest, the newest CHANGELOG release and each listed .NOTES block name
# the same version. VR-002, with -Base: the version is not lower than the latest tag;
# a version already tagged is in HEAD's history, and no package input changed since
# Base, so a released number never labels a different package.

if (-not $config.Checks.Version) {
    Write-Off -Id 'GK09' -Name 'version' -Reason 'off in gate.config.psd1'
}
else {
    $versionProblems = [System.Collections.Generic.List[string]]::new()
    $prefix          = $config.Version.TagPrefix
    $moduleVersion   = [string](Import-PowerShellDataFile -LiteralPath (Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.Version.Manifest)).ModuleVersion
    $versionValid    = $moduleVersion -match '^\d+\.\d+\.\d+$'
    if (-not $versionValid) { $versionProblems.Add("$($config.Version.Manifest): ModuleVersion '$moduleVersion' is not MAJOR.MINOR.PATCH (VR-001)") }

    foreach ($relative in @($config.Version.NotesFiles)) {
        $found = [regex]::Match([System.IO.File]::ReadAllText((Resolve-GatePath -RepoRoot $repoRoot -RelativePath $relative)), '(?m)^\s*Version\s*:\s*(\S+)\s*$')
        if (-not $found.Success) { $versionProblems.Add("${relative}: no 'Version :' line (VR-001)") }
        elseif ($found.Groups[1].Value -ne $moduleVersion) { $versionProblems.Add("${relative}: Version $($found.Groups[1].Value) (VR-001)") }
    }

    $newest = [regex]::Match([System.IO.File]::ReadAllText((Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.Version.Changelog)), '(?m)^## \[(\d+\.\d+\.\d+)\]')
    if (-not $newest.Success) { $versionProblems.Add("$($config.Version.Changelog): no release heading (VR-001)") }
    elseif ($newest.Groups[1].Value -ne $moduleVersion) { $versionProblems.Add("$($config.Version.Changelog): newest release $($newest.Groups[1].Value) (VR-001)") }

    $tagNote = ''
    if ($Base) {
        if ($null -ne $notReady) {
            $versionProblems.Add("tags $notReady")
        }
        elseif ($versionValid) {
            $tagOut  = @(& $git.Source -C $repoRoot tag --list "$prefix*" 2>$null)
            $tagExit = $LASTEXITCODE
            $tagged  = @($tagOut | ForEach-Object { if ($PSItem -match "^$([regex]::Escape($prefix))(\d+\.\d+\.\d+)$") { [version]$Matches[1] } })
            $current = [version]$moduleVersion
            $latest  = $tagged | Sort-Object -Descending | Select-Object -First 1
            if ($tagExit -ne 0) {
                # Fail closed: a check that cannot see the tags does not pass them.
                $versionProblems.Add('git could not list the tags (VR-002)')
            }
            elseif ($null -ne $latest -and $current -lt $latest) {
                $versionProblems.Add("version $moduleVersion is lower than the latest tag $prefix$latest (VR-002)")
            }
            elseif ($tagged -contains $current) {
                $null = & $git.Source -C $repoRoot merge-base --is-ancestor "refs/tags/$prefix$moduleVersion" HEAD 2>$null
                if ($LASTEXITCODE -ne 0) { $versionProblems.Add("$prefix$moduleVersion is tagged on a commit this branch does not contain (VR-002)") }
                $changedOut = @(& $git.Source -C $repoRoot diff --name-only "$baseCommit...HEAD" 2>$null)
                if ($LASTEXITCODE -ne 0) {
                    $versionProblems.Add("git could not list the files changed since $Base (VR-002)")
                }
                else {
                    $inputs = @($config.Version.PackageInputs)
                    $hit = @($changedOut | Where-Object {
                            $changedPath = $PSItem
                            @($inputs | Where-Object { $changedPath -eq $PSItem -or ($PSItem.EndsWith('/') -and $changedPath.StartsWith($PSItem)) }).Count -gt 0
                        })
                    if ($hit.Count -gt 0) {
                        $versionProblems.Add("a package input changed since $Base but $prefix$moduleVersion is already released: bump the version (VR-002)")
                        foreach ($path in $hit) { $versionProblems.Add("  changed: $path") }
                    }
                }
                $tagNote = "; $prefix$moduleVersion already tagged"
            }
            else {
                $tagNote = if ($null -ne $latest) { "; not yet tagged, latest tag $prefix$latest" } else { '; no tags yet' }
            }
        }
    }
    $versionSummary = if ($versionProblems.Count -eq 0) {
        "$moduleVersion in the manifest, $(@($config.Version.NotesFiles).Count) .NOTES block(s) and the CHANGELOG$tagNote"
    }
    else {
        "version $moduleVersion does not agree everywhere"
    }
    Add-Result -Id 'GK09' -Name 'version' -Passed ($versionProblems.Count -eq 0) -Summary $versionSummary -Detail @($versionProblems)
}

# -- GK10 review, only with -Base --------------------------------------------
# RV-001: when the branch changes any file other than the review record and the files
# listed in Review.Exempt, the record at HEAD shows a completed review of a commit the
# branch adds, from the merge base with Base or an older one, and every finding has a
# Response that starts with Fixed:, Rejected:, Accepted: or Deferred:.

if (-not $config.Checks.Review) {
    Write-Off -Id 'GK10' -Name 'review' -Reason 'off in gate.config.psd1'
}
elseif (-not $Base) {
    Write-Off -Id 'GK10' -Name 'review' -Reason 'runs only with -Base'
}
elseif ($null -ne $notReady) {
    Add-Result -Id 'GK10' -Name 'review' -Passed $false -Summary $notReady
}
else {
    $reviewPath  = $config.Review.Record
    $exemptFiles = @(@($reviewPath) + @($config.Review.Exempt) | Where-Object { $PSItem })
    $mergeBase   = @(& $git.Source -C $repoRoot merge-base $baseCommit HEAD 2>$null) | Select-Object -First 1
    $diffOut     = @(& $git.Source -C $repoRoot diff --name-only "$baseCommit...HEAD" 2>$null)
    $diffExit    = $LASTEXITCODE
    $reviewed    = @($diffOut | Where-Object { $PSItem -and $exemptFiles -notcontains $PSItem })
    if ($diffExit -ne 0 -or -not $mergeBase) {
        # Fail closed: a check that cannot see the change does not pass it.
        Add-Result -Id 'GK10' -Name 'review' -Passed $false -Summary "not run: git could not list the files changed since $Base"
    }
    elseif ($reviewed.Count -eq 0) {
        Add-Result -Id 'GK10' -Name 'review' -Passed $true -Summary "no file changed since $Base; no review needed"
    }
    else {
        $reviewProblems = [System.Collections.Generic.List[string]]::new()
        $json   = (& $git.Source -C $repoRoot show "HEAD:$reviewPath" 2>$null) -join "`n"
        $record = $null
        if ($LASTEXITCODE -ne 0 -or -not $json) {
            $reviewProblems.Add("$reviewPath is not in HEAD: run $kitPath/Scripts/Invoke-ModelReview.ps1")
        }
        else {
            try { $record = $json | ConvertFrom-Json } catch { $reviewProblems.Add("$reviewPath is not valid JSON") }
        }
        if ($null -ne $record) {
            $names = @($record.PSObject.Properties.Name)
            if (-not ($names -contains 'SchemaVersion' -and $record.SchemaVersion -eq 1)) {
                $reviewProblems.Add("$reviewPath is not schema version 1")
            }
            if (-not ($names -contains 'Completed' -and $record.Completed -eq $true)) {
                $reviewProblems.Add("$reviewPath does not show a completed review")
            }
            $reviewCommit = if ($names -contains 'Commit') { "$($record.Commit)" } else { '' }
            $reviewBase   = if ($names -contains 'BaseCommit') { "$($record.BaseCommit)" } else { '' }
            # The review's base may be older than today's merge base: bringing the branch
            # up to date with Base moves the merge base forward, and the review still
            # covers every commit the branch adds.
            $baseCovered = $false
            if ($reviewBase -match '^[0-9a-f]{40}$') {
                $null = & $git.Source -C $repoRoot merge-base --is-ancestor $reviewBase $mergeBase 2>$null
                $baseCovered = $LASTEXITCODE -eq 0
            }
            if (-not $baseCovered) {
                $reviewProblems.Add("the review's base is not the merge base with $Base or older: the review does not cover every commit since $Base")
            }
            if ($reviewCommit -notmatch '^[0-9a-f]{40}$') {
                $reviewProblems.Add("$reviewPath names no commit")
            }
            else {
                $null = & $git.Source -C $repoRoot merge-base --is-ancestor $reviewCommit HEAD 2>$null
                if ($LASTEXITCODE -ne 0) {
                    $reviewProblems.Add("the reviewed commit $($reviewCommit.Substring(0, 7)) is not in HEAD's history")
                }
                # The reviewed commit must be one this branch adds. A record left by an
                # earlier pull request names a commit already in Base, and passes every
                # other test here. Exit 1 means "not an ancestor"; 0 or an error fails.
                $null = & $git.Source -C $repoRoot merge-base --is-ancestor $reviewCommit $mergeBase 2>$null
                if ($LASTEXITCODE -ne 1) {
                    $reviewProblems.Add("the reviewed commit $($reviewCommit.Substring(0, 7)) is already in ${Base}: the record is from an earlier pull request")
                }
            }
            if ($names -notcontains 'Findings') {
                $reviewProblems.Add("$reviewPath has no Findings list")
            }
            else {
                foreach ($finding in @($record.Findings | Where-Object { $null -ne $PSItem })) {
                    $id       = if ($finding.PSObject.Properties['Id']) { "$($finding.Id)" } else { '?' }
                    $response = if ($finding.PSObject.Properties['Response']) { "$($finding.Response)" } else { '' }
                    if ($response -notmatch '^(Fixed|Rejected|Accepted|Deferred): \S') {
                        $reviewProblems.Add("finding $id is not answered: its Response must start with Fixed:, Rejected:, Accepted: or Deferred:")
                    }
                }
            }
        }
        $summary = if ($reviewProblems.Count -eq 0) {
            "$reviewPath covers $($record.Commit.Substring(0, 7)); $(@($record.Findings | Where-Object { $null -ne $PSItem }).Count) finding(s), all answered"
        }
        else {
            'the review is missing, incomplete or not answered (RV-001)'
        }
        Add-Result -Id 'GK10' -Name 'review' -Passed ($reviewProblems.Count -eq 0) -Summary $summary -Detail @($reviewProblems)
    }
}

# -- GK11 unit, only with -Unit ----------------------------------------------
# UT-001: the repository's unit test script exits 0. The script owns its tests, its
# coverage floor and its results file.

if (-not $config.Checks.Unit) {
    Write-Off -Id 'GK11' -Name 'unit' -Reason 'off in gate.config.psd1'
}
elseif (-not $Unit) {
    Write-Off -Id 'GK11' -Name 'unit' -Reason 'runs only with -Unit'
}
else {
    $run    = Invoke-ChildScript -Script (Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.Unit.Script)
    $failed = @($run.Output | Where-Object { $PSItem -match '^\s*\[-\]|^\[FAIL\]' } | ForEach-Object { $PSItem.Trim() })
    if ($run.ExitCode -ne 0 -and $failed.Count -eq 0) { $failed = @($run.Output | Select-Object -Last 5) }
    $summary = if ($run.ExitCode -eq 0) { "$($config.Unit.Script) passed" } else { "$($config.Unit.Script) failed (exit $($run.ExitCode))" }
    Add-Result -Id 'GK11' -Name 'unit' -Passed ($run.ExitCode -eq 0) -Summary $summary -Detail $failed
}

# -- Summary -----------------------------------------------------------------

$failedChecks = @($results | Where-Object { -not $PSItem.Passed })
if ($failedChecks.Count -gt 0) {
    Write-Output "[FAIL] gate: $($failedChecks.Count) of $($results.Count) checks failed: $(($failedChecks | ForEach-Object { "$($PSItem.Id) $($PSItem.Name)" }) -join ', ')"
    exit 1
}

Write-Output "[PASS] gate: all $($results.Count) checks passed"
exit 0
