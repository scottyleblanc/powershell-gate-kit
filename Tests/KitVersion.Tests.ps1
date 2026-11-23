#Requires -Version 7.6

# Rule KT-002: the Version row in README.md and Docs/SECURITY.md names the kit's
# version, the ModuleVersion in Gate/version.psd1. GK09 reads only the manifest and the
# CHANGELOG, so nothing else holds these rows to the released number.

BeforeDiscovery {
    $kitRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:files = @(
        @{ Relative = 'README.md'; Full = Join-Path -Path $kitRoot -ChildPath 'README.md' }
        @{ Relative = 'Docs/SECURITY.md'; Full = Join-Path -Path $kitRoot -ChildPath 'Docs' -AdditionalChildPath 'SECURITY.md' }
    )
}

BeforeAll {
    $kitRoot         = Split-Path -Path $PSScriptRoot -Parent
    $manifestPath    = Join-Path -Path $kitRoot -ChildPath 'Gate' -AdditionalChildPath 'version.psd1'
    $script:version  = [string](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion
}

Describe 'Kit version rows' -Tag 'Static' {

    It 'reads a MAJOR.MINOR.PATCH version from Gate/version.psd1' {
        $script:version | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'KT-002 <Relative> names the version in its Version row' -ForEach $script:files {
        $text  = [System.IO.File]::ReadAllText($Full)
        $rows  = @([regex]::Matches($text, '(?m)^\| Version \| (?<value>[^|]*?) \|\r?$'))
        $rows.Count | Should -Be 1 -Because "$Relative holds one '| Version | ... |' row"
        $rows[0].Groups['value'].Value | Should -BeExactly "$script:version (tagged on merge)"
    }
}
