#Requires -Version 7.6
<#
.SYNOPSIS
    Helpers shared by Invoke-Gate.ps1 and Update-AnalyzerBaseline.ps1.

.DESCRIPTION
    Reads and checks gate.config.psd1 (rules CF-001 to CF-005), resolves the paths it
    names, runs PSScriptAnalyzer with the kit's settings and rules, and reads the
    analyzer baseline (AN-001).

.NOTES
    **Invocation:** lib helper — dot-sourced by the scripts in Scripts\. Defines
    functions only; running it does nothing else.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The config keys and their defaults. A key missing from a repository's config takes
# the default; a key not listed here fails CF-003.
$script:GateConfigDefault = [ordered]@{
    SchemaVersion   = 1
    Checks          = [ordered]@{ Review = $true; Version = $false; Unit = $false }
    Analyzer        = [ordered]@{ Paths = @(); Exclude = @('*.Tests.ps1'); ExcludeRules = @(); ExcludeRulesByPath = @{}; Baseline = '' }
    StaticTests     = ''
    Gitleaks        = ''
    MessagePatterns = ''
    Permissions     = ''
    Review          = [ordered]@{ Record = 'Review/LastReview.json'; Exempt = @() }
    Version         = [ordered]@{ Manifest = ''; Changelog = ''; NotesFiles = @(); TagPrefix = 'v'; PackageInputs = @() }
    Unit            = [ordered]@{ Script = '' }
}

function Get-GateRepoRoot {
    <#
    .SYNOPSIS
        Returns the root of the git checkout that holds a folder.
    .PARAMETER Path
        A folder inside the checkout.
    .OUTPUTS
        System.String. The root, as a full path. Throws when the folder is not in a
        git checkout.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $root = @(& git -C $Path rev-parse --show-toplevel 2>$null) | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $root) { throw "[Get-GateRepoRoot] '$Path' is not inside a git checkout." }
    [System.IO.Path]::GetFullPath($root)
}

function Resolve-GatePath {
    <#
    .SYNOPSIS
        Turns a config path into a full path under the repository root (rule CF-004).
    .PARAMETER RepoRoot
        The repository root.
    .PARAMETER RelativePath
        A path from gate.config.psd1: relative, '/' separated, with no '..' segment.
    .OUTPUTS
        System.String. The full path. Throws when the path is absolute or leaves the
        repository.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RelativePath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '^[A-Za-z]:' -or $RelativePath.Contains('\')) {
        throw "[Resolve-GatePath] '$RelativePath' must be relative to the repository root and use / separators (CF-004)."
    }
    $parts = @($RelativePath.Split('/') | Where-Object { $PSItem -and $PSItem -ne '.' })
    if ($parts -contains '..' -or $parts.Count -eq 0) {
        throw "[Resolve-GatePath] '$RelativePath' must name a path inside the repository (CF-004)."
    }
    if ($parts.Count -eq 1) { return Join-Path -Path $RepoRoot -ChildPath $parts[0] }
    Join-Path -Path $RepoRoot -ChildPath $parts[0] -AdditionalChildPath $parts[1..($parts.Count - 1)]
}

function Import-GateConfig {
    <#
    .SYNOPSIS
        Reads gate.config.psd1 from the repository root and checks it (rules CF-001 to
        CF-005).
    .PARAMETER RepoRoot
        The repository root.
    .OUTPUTS
        PSCustomObject with Config (an ordered hashtable with every default filled in)
        and Problems (a string array; empty when the config is valid).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $problems = [System.Collections.Generic.List[string]]::new()
    $config   = [ordered]@{}
    foreach ($key in $script:GateConfigDefault.Keys) {
        $value = $script:GateConfigDefault[$key]
        $config[$key] = if ($value -is [System.Collections.IDictionary]) { [ordered]@{} + $value } else { $value }
    }

    $file = Join-Path -Path $RepoRoot -ChildPath 'gate.config.psd1'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        $problems.Add('gate.config.psd1 is not at the repository root (CF-001)')
        return [PSCustomObject]@{ Config = $config; Problems = @($problems) }
    }

    # Import-PowerShellDataFile accepts only data: no command or expression runs.
    $read = $null
    try {
        $read = Import-PowerShellDataFile -LiteralPath $file
    }
    catch {
        $problems.Add("gate.config.psd1 is not a valid data file: $($PSItem.Exception.Message) (CF-001)")
        return [PSCustomObject]@{ Config = $config; Problems = @($problems) }
    }

    foreach ($key in $read.Keys) {
        if (-not $config.Contains($key)) {
            $problems.Add("gate.config.psd1: unknown key '$key' (CF-003)")
            continue
        }
        $default = $script:GateConfigDefault[$key]
        if ($default -is [System.Collections.IDictionary]) {
            if ($read[$key] -isnot [System.Collections.IDictionary]) {
                $problems.Add("gate.config.psd1: '$key' must be a hashtable (CF-003)")
                continue
            }
            foreach ($inner in $read[$key].Keys) {
                if (-not $default.Contains($inner)) { $problems.Add("gate.config.psd1: unknown key '$key.$inner' (CF-003)") }
                else { $config[$key][$inner] = $read[$key][$inner] }
            }
        }
        else {
            $config[$key] = $read[$key]
        }
    }

    if ($config.SchemaVersion -ne 1) { $problems.Add("gate.config.psd1: SchemaVersion must be 1 (CF-002)") }

    foreach ($name in @($config.Checks.Keys)) {
        if ($config.Checks[$name] -isnot [bool]) { $problems.Add("gate.config.psd1: Checks.$name must be `$true or `$false (CF-003)") }
    }

    # Every path is relative and inside the repository (CF-004); a file the config names
    # must exist, except the review record, which a branch adds later.
    $mustExist = [System.Collections.Generic.List[object]]::new()
    foreach ($path in @($config.Analyzer.Paths)) { $mustExist.Add(@('Analyzer.Paths', $path, 'Container')) }

    # Analyzer.ExcludeRulesByPath maps a folder to the rule names not reported under it.
    $byPath = $config.Analyzer.ExcludeRulesByPath
    if ($byPath -isnot [System.Collections.IDictionary]) {
        $problems.Add("gate.config.psd1: 'Analyzer.ExcludeRulesByPath' must be a hashtable of folder = rule names (CF-003)")
        $config.Analyzer.ExcludeRulesByPath = @{}
    }
    else {
        foreach ($folder in @($byPath.Keys)) {
            $mustExist.Add(@('Analyzer.ExcludeRulesByPath', [string]$folder, 'Container'))
            $rules = @($byPath[$folder])
            if ($rules.Count -eq 0 -or @($rules | Where-Object { $PSItem -isnot [string] -or -not $PSItem }).Count -gt 0) {
                $problems.Add("gate.config.psd1: Analyzer.ExcludeRulesByPath '$folder' must list one or more rule names (CF-003)")
            }
        }
    }
    # The leading commas keep each triple whole: @() would flatten them otherwise.
    $optionalPaths = @(
        , @('Analyzer.Baseline', $config.Analyzer.Baseline, 'Leaf')
        , @('StaticTests', $config.StaticTests, 'Container')
        , @('Gitleaks', $config.Gitleaks, 'Leaf')
        , @('MessagePatterns', $config.MessagePatterns, 'Leaf')
        , @('Permissions', $config.Permissions, 'Leaf')
    )
    foreach ($pair in $optionalPaths) {
        if ($pair[1]) { $mustExist.Add($pair) }
    }
    if ($config.Checks.Version) {
        $versionFiles = @(
            , @('Version.Manifest', $config.Version.Manifest, 'Leaf')
            , @('Version.Changelog', $config.Version.Changelog, 'Leaf')
        )
        foreach ($pair in $versionFiles) {
            if (-not $pair[1]) { $problems.Add("gate.config.psd1: Checks.Version is on, so $($pair[0]) must name a file (CF-005)") }
            else { $mustExist.Add($pair) }
        }
        foreach ($path in @($config.Version.NotesFiles)) { $mustExist.Add(@('Version.NotesFiles', $path, 'Leaf')) }
        if ($config.Version.TagPrefix -notmatch '^[A-Za-z0-9._-]*$') { $problems.Add('gate.config.psd1: Version.TagPrefix may hold only letters, digits, ., _ and - (CF-005)') }
    }
    if ($config.Checks.Unit) {
        if (-not $config.Unit.Script) { $problems.Add('gate.config.psd1: Checks.Unit is on, so Unit.Script must name a script (CF-005)') }
        else { $mustExist.Add(@('Unit.Script', $config.Unit.Script, 'Leaf')) }
    }
    if ($config.Checks.Review -and -not $config.Review.Record) {
        $problems.Add('gate.config.psd1: Checks.Review is on, so Review.Record must name a file (CF-005)')
    }

    foreach ($entry in $mustExist) {
        try {
            $full = Resolve-GatePath -RepoRoot $RepoRoot -RelativePath ([string]$entry[1])
            if (-not (Test-Path -LiteralPath $full -PathType $entry[2])) {
                $kind = if ($entry[2] -eq 'Leaf') { 'file' } else { 'folder' }
                $problems.Add("gate.config.psd1: $($entry[0]) names '$($entry[1])', which is not a $kind in the repository (CF-004)")
            }
        }
        catch {
            $problems.Add("gate.config.psd1: $($entry[0]): $($PSItem.Exception.Message -replace '^\[Resolve-GatePath\] ', '')")
        }
    }
    foreach ($path in @($config.Review.Exempt) + @($config.Review.Record) + @($config.Version.PackageInputs)) {
        if (-not $path) { continue }
        try { $null = Resolve-GatePath -RepoRoot $RepoRoot -RelativePath ([string]$path) }
        catch { $problems.Add("gate.config.psd1: $($PSItem.Exception.Message -replace '^\[Resolve-GatePath\] ', '')") }
    }

    [PSCustomObject]@{ Config = $config; Problems = @($problems) }
}

function Invoke-GateAnalyzer {
    <#
    .SYNOPSIS
        Runs PSScriptAnalyzer over the folders the config names, with the kit's
        settings and custom rules. A finding from a rule that
        Analyzer.ExcludeRulesByPath lists for a folder is dropped for files under it.
    .PARAMETER RepoRoot
        The repository root.
    .PARAMETER KitRoot
        The kit's root folder (the parent of Scripts\).
    .PARAMETER Config
        The config returned by Import-GateConfig.
    .OUTPUTS
        PSCustomObject with FileCount and Findings; each finding has Path (relative,
        '/' separated), Line, Rule and Message.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$KitRoot,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary]$Config
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $settingsFile = Join-Path -Path $KitRoot -ChildPath 'Analyzer' -AdditionalChildPath 'AnalyzerSettings.psd1'
    $kitSettings  = Import-PowerShellDataFile -LiteralPath $settingsFile
    $settings = @{
        Severity            = [string[]]$kitSettings.Severity
        IncludeDefaultRules = $true
        ExcludeRules        = [string[]]@(@($kitSettings.ExcludeRules) + @($Config.Analyzer.ExcludeRules) | Where-Object { $PSItem } | Select-Object -Unique)
        CustomRulePath      = [string](Join-Path -Path $KitRoot -ChildPath 'Analyzer' -AdditionalChildPath 'Rules', '*.psm1')
    }

    $folders = @($Config.Analyzer.Paths | ForEach-Object { Resolve-GatePath -RepoRoot $RepoRoot -RelativePath $PSItem })
    $files   = @()
    if ($folders.Count -gt 0) {
        $files = @(Get-ChildItem -LiteralPath $folders -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File | Where-Object {
                $name = $PSItem.Name
                @($Config.Analyzer.Exclude | Where-Object { $name -like $PSItem }).Count -eq 0
            } | Sort-Object -Property FullName -Unique)
    }

    # Folder prefixes ('scripts/') and the rules not reported under each.
    $byPath = @(foreach ($folder in @($Config.Analyzer.ExcludeRulesByPath.Keys)) {
            [PSCustomObject]@{ Prefix = ([string]$folder).Trim('/') + '/'; Rules = [string[]]@($Config.Analyzer.ExcludeRulesByPath[$folder]) }
        })

    $findings = @(foreach ($file in $files) {
            foreach ($record in @(Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settings)) {
                $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $record.ScriptPath).Replace('\', '/')
                $skip     = @($byPath | Where-Object { $relative.StartsWith($PSItem.Prefix, [System.StringComparison]::OrdinalIgnoreCase) -and $PSItem.Rules -contains $record.RuleName })
                if ($skip.Count -gt 0) { continue }
                [PSCustomObject]@{
                    Path    = $relative
                    Line    = $record.Line
                    Rule    = $record.RuleName
                    Message = $record.Message
                }
            }
        })

    [PSCustomObject]@{ FileCount = $files.Count; Findings = $findings }
}

function Compare-AnalyzerBaseline {
    <#
    .SYNOPSIS
        Splits analyzer findings into those the baseline holds and new ones (rule
        AN-001).
    .DESCRIPTION
        The baseline counts findings per file and rule, so it survives line moves.
        Findings for a file and rule beyond the baseline's count are new; when a file
        and rule have more findings than the baseline allows, every finding of that
        pair is listed, because which one is new cannot be told apart.
    .PARAMETER Findings
        The findings from Invoke-GateAnalyzer.
    .PARAMETER BaselineFile
        The baseline file, or an empty string for none.
    .OUTPUTS
        PSCustomObject with New (findings that fail), Held (the count the baseline
        holds) and Shrinkable (file and rule pairs with fewer findings than the
        baseline allows).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$BaselineFile
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $allowed = @{}
    if ($BaselineFile) {
        foreach ($entry in @((Import-PowerShellDataFile -LiteralPath $BaselineFile).Findings)) {
            $allowed["$($entry.Path)|$($entry.Rule)"] = [int]$entry.Count
        }
    }

    $new        = [System.Collections.Generic.List[object]]::new()
    $held       = 0
    $shrinkable = [System.Collections.Generic.List[string]]::new()
    $groups     = @($Findings | Group-Object -Property { "$($PSItem.Path)|$($PSItem.Rule)" })
    foreach ($group in $groups) {
        $limit = if ($allowed.ContainsKey($group.Name)) { $allowed[$group.Name] } else { 0 }
        if ($group.Count -gt $limit) { foreach ($finding in $group.Group) { $new.Add($finding) } }
        else { $held += $group.Count }
    }
    foreach ($key in $allowed.Keys) {
        $found = @($groups | Where-Object { $PSItem.Name -eq $key })
        $count = if ($found.Count -gt 0) { $found[0].Count } else { 0 }
        if ($count -lt $allowed[$key]) { $shrinkable.Add($key) }
    }

    [PSCustomObject]@{ New = @($new); Held = $held; Shrinkable = @($shrinkable) }
}
