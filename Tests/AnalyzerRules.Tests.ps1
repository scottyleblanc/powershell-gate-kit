#Requires -Version 7.6

# Rules AN-002 to AN-013: each custom analyzer rule reports its defect and stays quiet
# on the corrected code. A rule that never fires would let GK03 pass anything.

BeforeDiscovery {
    $script:cases = @(
        @{
            Rule = 'Measure-AN002OutputTypeDeclared'
            Bad  = 'function Get-Thing { [CmdletBinding()] param([string]$Name) $Name }'
            Good = 'function Get-Thing { [CmdletBinding()] [OutputType([string])] param([string]$Name) $Name }'
        }
        @{
            Rule = 'Measure-AN003PlatformFromAutomaticVariable'
            Bad  = 'if ($env:OS -eq "Windows_NT") { "win" }'
            Good = 'if ($IsWindows) { "win" }'
        }
        @{
            Rule = 'Measure-AN004ParameterTyped'
            Bad  = 'function Get-Thing { [OutputType([string])] param($Name) $Name }'
            Good = 'function Get-Thing { [OutputType([string])] param([string]$Name) $Name }'
        }
        @{
            Rule = 'Measure-AN005NoLineContinuation'
            Bad  = "Get-ChildItem -Path . ``" + [System.Environment]::NewLine + "    -File"
            Good = '$params = @{ Path = "."; File = $true }; Get-ChildItem @params'
        }
        @{
            Rule = 'Measure-AN006PathWithJoinPath'
            Bad  = '$binPath = "$root\bin"'
            Good = '$binPath = Join-Path -Path $root -ChildPath "bin"'
        }
        @{
            Rule = 'Measure-AN007EncodingNamed'
            Bad  = 'Set-Content -Path $target -Value "x"'
            Good = 'Set-Content -Path $target -Value "x" -Encoding UTF8'
        }
        @{
            Rule = 'Measure-AN008UsePSItem'
            Bad  = '1..3 | ForEach-Object { $_ * 2 }'
            Good = '1..3 | ForEach-Object { $PSItem * 2 }'
        }
        @{
            Rule = 'Measure-AN009NoEmoji'
            Bad  = 'Write-Output "done ' + [char]::ConvertFromUtf32(0x2705) + '"'
            Good = 'Write-Output "[INFO] done"'
        }
        @{
            Rule = 'Measure-AN010StrictModeSet'
            Bad  = 'function Get-Thing { [CmdletBinding()] param([string]$Name) $Name }'
            Good = "function Get-Thing { [CmdletBinding()] param([string]`$Name) Set-StrictMode -Version Latest; `$ErrorActionPreference = 'Stop'; `$Name }"
        }
        @{
            Rule = 'Measure-AN011CmdletBindingDeclared'
            Bad  = 'function Get-Thing { param([string]$Name) $Name }'
            Good = 'function Get-Thing { [CmdletBinding()] param([string]$Name) $Name }'
        }
        @{
            Rule = 'Measure-AN012SuppressionJustified'
            Bad  = "function Get-Thing { [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingWriteHost', '')] [CmdletBinding()] param() }"
            Good = "function Get-Thing { [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingWriteHost', '', Justification = 'Console output.')] [CmdletBinding()] param() }"
        }
        @{
            Rule = 'Measure-AN013HelpComplete'
            Bad  = 'function Get-Thing { [CmdletBinding()] param([string]$Name) $Name }'
            Good = @'
function Get-Thing {
    <#
    .SYNOPSIS
        Returns a name.
    .DESCRIPTION
        Returns the name it is given.
    .PARAMETER Name
        The name.
    .EXAMPLE
        Get-Thing -Name 'x'
    .NOTES
        None.
    #>
    [CmdletBinding()]
    param([string]$Name)
    $Name
}
'@
        }
    )
}

BeforeAll {
    Import-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0
    $script:rulesPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Analyzer' -AdditionalChildPath 'Rules', '*.psm1'

    function Get-RuleHit {
        param([string]$Script, [string]$Rule)
        $params = @{
            ScriptDefinition = $Script
            CustomRulePath   = $script:rulesPath
        }
        @(Invoke-ScriptAnalyzer @params | Where-Object { $PSItem.RuleName -eq $Rule })
    }
}

Describe 'Custom analyzer rules' -Tag 'Static' {

    It '<Rule> reports the defect' -ForEach $script:cases {
        @(Get-RuleHit -Script $Bad -Rule $Rule).Count | Should -BeGreaterThan 0
    }

    It '<Rule> passes the corrected code' -ForEach $script:cases {
        @(Get-RuleHit -Script $Good -Rule $Rule).Count | Should -Be 0
    }

    It 'Measure-AN002OutputTypeDeclared skips class methods and constructors, and still reports a function beside them' {
        $script = 'class Thing { Thing() { } [string] Name() { return "x" } static [int] Twice([int] $a) { return $a * 2 } }' +
            [System.Environment]::NewLine + 'function Get-Thing { param([string]$Name) $Name }'
        $hits = @(Get-RuleHit -Script $script -Rule 'Measure-AN002OutputTypeDeclared')
        $hits.Count | Should -Be 1
        $hits[0].Message | Should -Match "Function 'Get-Thing'"
    }

    It '<Rule> checks a script with a param block and skips a function inside it' -ForEach @(
        @{ Rule = 'Measure-AN010StrictModeSet' }
        @{ Rule = 'Measure-AN011CmdletBindingDeclared' }
        @{ Rule = 'Measure-AN013HelpComplete' }
    ) {
        $script = 'param([string]$Name)' + [System.Environment]::NewLine + 'function Get-Inner { $Name }'
        $hits = @(Get-RuleHit -Script $script -Rule $Rule)
        $hits.Count | Should -Be 1
        $hits[0].Message | Should -Match 'The script'
    }

    It '<Rule> skips a function defined inside another function' -ForEach @(
        @{ Rule = 'Measure-AN010StrictModeSet' }
        @{ Rule = 'Measure-AN011CmdletBindingDeclared' }
        @{ Rule = 'Measure-AN013HelpComplete' }
    ) {
        $script = 'function Get-Outer { function Get-Inner { 1 } Get-Inner }'
        $hits = @(Get-RuleHit -Script $script -Rule $Rule)
        $hits.Count | Should -Be 1
        $hits[0].Message | Should -Match "Function 'Get-Outer'"
    }

    It 'Measure-AN010StrictModeSet does not count settings made inside a try block' {
        $script = "function Get-Thing { [CmdletBinding()] param() try { Set-StrictMode -Version Latest; `$ErrorActionPreference = 'Stop' } finally { } }"
        @(Get-RuleHit -Script $script -Rule 'Measure-AN010StrictModeSet').Count | Should -Be 1
    }

    It 'Measure-AN012SuppressionJustified reports a blank Justification' {
        $script = "function Get-Thing { [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = ' ')] [CmdletBinding()] param() }"
        @(Get-RuleHit -Script $script -Rule 'Measure-AN012SuppressionJustified').Count | Should -Be 1
    }

    It 'Measure-AN013HelpComplete reports help that a prose line starting with a dot makes unreadable' {
        $script = "function Get-Thing {`n    <#`n    .SYNOPSIS`n        Reads a file.`n    .DESCRIPTION`n        Reads a`n        .properties file.`n    .EXAMPLE`n        Get-Thing`n    .NOTES`n        None.`n    #>`n    [CmdletBinding()]`n    param()`n}"
        $hits = @(Get-RuleHit -Script $script -Rule 'Measure-AN013HelpComplete')
        $hits.Count | Should -Be 1
        $hits[0].Message | Should -Match 'no help block that Get-Help can read'
    }

    It 'Measure-AN013HelpComplete reports script help written directly below #Requires' {
        $script = "#Requires -Version 7.0`n<#`n.SYNOPSIS`n    Runs.`n.DESCRIPTION`n    Runs.`n.EXAMPLE`n    ./Run.ps1`n.NOTES`n    None.`n#>`n[CmdletBinding()]`nparam()"
        @(Get-RuleHit -Script $script -Rule 'Measure-AN013HelpComplete').Count | Should -Be 1
        $fixed = $script.Replace("7.0`n<#", "7.0`n`n<#")
        @(Get-RuleHit -Script $fixed -Rule 'Measure-AN013HelpComplete').Count | Should -Be 0
    }

    It 'Measure-AN013HelpComplete names a missing and a stale parameter entry' {
        $script = "function Get-Thing {`n    <#`n    .SYNOPSIS`n        Returns.`n    .DESCRIPTION`n        Returns.`n    .PARAMETER Old`n        Gone.`n    .EXAMPLE`n        Get-Thing`n    .NOTES`n        None.`n    #>`n    [CmdletBinding()]`n    param([string]`$Name)`n}"
        $hits = @(Get-RuleHit -Script $script -Rule 'Measure-AN013HelpComplete')
        $hits.Count | Should -Be 1
        $hits[0].Message | Should -Match 'no \.PARAMETER for Name'
        $hits[0].Message | Should -Match 'names no parameter: OLD'
    }
}
