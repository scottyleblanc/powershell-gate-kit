#Requires -Version 7.6

<#
.SYNOPSIS
    Sets the release version the commits since the latest tag call for (rule VR-003).

.DESCRIPTION
    Works out the next version the same way gate check GK09 does (Get-GateNextVersion:
    a breaking change is major, or minor before 1.0; feat is minor; fix and sec are
    patch; other types are no release). Then it:

      - sets ModuleVersion in the file gate.config.psd1 names under Version.Manifest
      - gives the entries under '## [Unreleased]' in Version.Changelog a release
        heading, '## [x.y.z] - yyyy-MM-dd' (UTC date), and leaves '## [Unreleased]'
        empty above it

    When the branch already holds an untagged release section from an earlier run and
    the bump has grown since (a feat after a fix), that section is renamed instead.
    When the commits call for no release, nothing changes.

    Run it on the branch, after the last commit that changes the bump, and commit the
    two files it changes. GK09 fails until the version matches.

.EXAMPLE
    pwsh -NoProfile -File ./tools/gate/Scripts/Update-ReleaseVersion.ps1

    Sets the version and the CHANGELOG heading for this branch's release.

.EXAMPLE
    pwsh -NoProfile -File ./tools/gate/Scripts/Update-ReleaseVersion.ps1 -WhatIf

    Prints the version it would set and changes nothing.

.NOTES
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Needs
    git, Checks.Version and Version.FromCommits on, and Version.Manifest and
    Version.Changelog set in gate.config.psd1. Writes only those two files, keeping
    their line endings.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([string])]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'Lib' -AdditionalChildPath 'GateLib.ps1')

$repoRoot = Get-GateRepoRoot -Path $PSScriptRoot

$loaded = Import-GateConfig -RepoRoot $repoRoot
if ($loaded.Problems.Count -gt 0) { throw "[Update-ReleaseVersion] gate.config.psd1 is not valid: $($loaded.Problems -join '; ')" }
$config = $loaded.Config
if (-not ($config.Checks.Version -and $config.Version.FromCommits)) {
    throw '[Update-ReleaseVersion] Turn on Checks.Version and Version.FromCommits in gate.config.psd1 first.'
}

$next = Get-GateNextVersion -RepoRoot $repoRoot -TagPrefix $config.Version.TagPrefix
if ($next.Problem) { throw "[Update-ReleaseVersion] $($next.Problem)" }
if ($next.Latest -and $next.Next -eq $next.Latest) {
    Write-Output "[INFO] no release: the $($next.Commits) commit(s) since $($config.Version.TagPrefix)$($next.Latest) are not feat, fix, sec or breaking"
    return
}

$manifestPath  = Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.Version.Manifest
$changelogPath = Resolve-GatePath -RepoRoot $repoRoot -RelativePath $config.Version.Changelog
$current       = [string](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion
$target        = $next.Next
$today         = [datetime]::UtcNow.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)

# The changelog: give the [Unreleased] entries the release heading.
$changelog = [System.IO.File]::ReadAllText($changelogPath)
$eol       = if ($changelog.Contains("`r`n")) { "`r`n" } else { "`n" }
$unreleased = [regex]::Match($changelog, '(?ms)^## \[Unreleased\][^\r\n]*\r?\n(?<body>.*?)(?=^## \[|\z)')
if (-not $unreleased.Success) { throw "[Update-ReleaseVersion] $($config.Version.Changelog) has no '## [Unreleased]' heading." }
$pending = $unreleased.Groups['body'].Value.Trim()

$hasTarget  = [regex]::IsMatch($changelog, "(?m)^## \[$([regex]::Escape($target))\]")
$staleMatch = [regex]::Match($changelog, "(?m)^## \[$([regex]::Escape($current))\][^\r\n]*")
$isStale    = $current -ne $target -and $current -ne $next.Latest -and $staleMatch.Success

if ($hasTarget -or $isStale) {
    # An earlier run on this branch already made the section.
    if ($pending) {
        throw "[Update-ReleaseVersion] $($config.Version.Changelog): move the entries under [Unreleased] into the release section by hand, then run this again."
    }
    $newChangelog = if ($isStale -and -not $hasTarget) {
        $changelog.Remove($staleMatch.Index, $staleMatch.Length).Insert($staleMatch.Index, "## [$target] - $today")
    }
    else { $changelog }
}
else {
    if (-not $pending) {
        throw "[Update-ReleaseVersion] $($config.Version.Changelog): add this release's entries under [Unreleased] first."
    }
    $body         = $unreleased.Groups['body']
    $section      = "## [Unreleased]$eol$eol## [$target] - $today$eol$eol$($body.Value.TrimStart("`r", "`n"))"
    $newChangelog = $changelog.Remove($unreleased.Index, $unreleased.Length).Insert($unreleased.Index, $section)
}

# The manifest: set ModuleVersion.
$manifest = [System.IO.File]::ReadAllText($manifestPath)
$found    = [regex]::Matches($manifest, "(?m)^(\s*ModuleVersion\s*=\s*)'[^']*'")
if ($found.Count -ne 1) { throw "[Update-ReleaseVersion] $($config.Version.Manifest): expected one ModuleVersion = '...' line, found $($found.Count)." }
$newManifest = $manifest.Remove($found[0].Index, $found[0].Length).Insert($found[0].Index, "$($found[0].Groups[1].Value)'$target'")

$from = if ($next.Latest) { "$($config.Version.TagPrefix)$($next.Latest)" } else { 'the first commit' }
if ($PSCmdlet.ShouldProcess("$($config.Version.Manifest) and $($config.Version.Changelog)", "Set version $target ($($next.Bump) since $from)")) {
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($manifestPath, $newManifest, $utf8)
    [System.IO.File]::WriteAllText($changelogPath, $newChangelog, $utf8)
    Write-Output "[INFO] version $target ($($next.Bump) since $from): $($config.Version.Manifest) and $($config.Version.Changelog) updated; commit both"
}
