#Requires -Version 7.6

# Rules AN-002 to AN-009: each custom analyzer rule reports its defect and stays quiet
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
}
