#Requires -Version 7.6

function Measure-AN014WhatIfDecided {
    <#
    .SYNOPSIS
        Rule AN-014: in a command that supports ShouldProcess, every cmdlet call that
        accepts -WhatIf has a preview decision.

    .DESCRIPTION
        Checks each function, and a script with a param block, whose [CmdletBinding()]
        declares SupportsShouldProcess. Reports a call in it to a cmdlet that has a
        -WhatIf parameter unless one of these holds:
          - Gated: it is inside the body of an if whose condition is
            $PSCmdlet.ShouldProcess(...), or a variable assigned from it in the same
            function.
          - After an early return: an earlier if in the same function returns or throws
            when $PSCmdlet.ShouldProcess(...) is declined.
          - Explicit: the call passes -WhatIf itself, such as -WhatIf:$false for work
            that must happen even during a preview.
        Without one of these, a caller's -WhatIf reaches the call through
        $WhatIfPreference and silently skips it. Only compiled cmdlets are checked, so
        the result does not depend on which modules are installed; ForEach-Object is
        excluded because it accepts -WhatIf but changes nothing itself. A function
        defined inside a checked one is judged by its own declaration (DEC-015). Custom
        PSScriptAnalyzer rule.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes in. The rule runs once per file, on the
        root script block, and ignores the nested ones it is also called for.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\source -Recurse -CustomRulePath .\tools\gate\Analyzer\Rules\*.psm1

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord, one per
        call that a preview would skip without a decision.

    .NOTES
        Returns diagnostic records, not the Success/Data/Message object: this is the
        contract PSScriptAnalyzer requires of a rule.
        Limitation: .NET calls such as [System.IO.File]::WriteAllText, and $env:
        assignments, never honour -WhatIf, so they are not checked; review covers them.
        A function call is not checked: one that supports ShouldProcess makes its own
        decision. "After an early return" is read from source order, not control flow.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($null -ne $ScriptBlockAst.Parent) { return }

    $shouldProcess    = '\$PSCmdlet\.ShouldProcess\('
    $supportsWhatIf   = @{}
    $notStateChanging = @('ForEach-Object')
    $declaresCache    = @{}

    $commands = @($ScriptBlockAst.FindAll({
        param([System.Management.Automation.Language.Ast]$Node)
        $Node -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    foreach ($command in $commands) {
        $name = $command.GetCommandName()
        if ([string]::IsNullOrEmpty($name)) { continue }

        # The enclosing function, if any; its body is the scope that decides.
        $function = $command.Parent
        while ($null -ne $function -and $function -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $function = $function.Parent
        }
        $scope = if ($null -ne $function) { $function.Body } else { $ScriptBlockAst }

        if (-not $declaresCache.ContainsKey($scope)) {
            $declares = $false
            if ($null -ne $scope.ParamBlock) {
                foreach ($attribute in @($scope.ParamBlock.Attributes)) {
                    if (($attribute.TypeName.Name -split '\.')[-1] -notin @('CmdletBinding', 'CmdletBindingAttribute')) { continue }
                    foreach ($argument in @($attribute.NamedArguments)) {
                        if ($argument.ArgumentName -ne 'SupportsShouldProcess') { continue }
                        $declares = $argument.ExpressionOmitted -or $argument.Argument.Extent.Text -ne '$false'
                    }
                }
            }
            $declaresCache[$scope] = $declares
        }
        if (-not $declaresCache[$scope]) { continue }

        if (-not $supportsWhatIf.ContainsKey($name)) {
            $resolved = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $resolved -and $resolved.CommandType -eq 'Alias') { $resolved = $resolved.ResolvedCommand }
            $supportsWhatIf[$name] = $null -ne $resolved -and
                $resolved.CommandType -eq 'Cmdlet' -and
                $resolved.Name -notin $notStateChanging -and
                $resolved.Parameters.ContainsKey('WhatIf')
        }
        if (-not $supportsWhatIf[$name]) { continue }

        # Explicit: the call passes -WhatIf itself.
        $explicit = @($command.CommandElements | Where-Object {
            $PSItem -is [System.Management.Automation.Language.CommandParameterAst] -and
            $PSItem.ParameterName -eq 'WhatIf'
        }).Count -gt 0
        if ($explicit) { continue }

        # Variables assigned from ShouldProcess in this scope: $applied = $PSCmdlet.ShouldProcess(...)
        $gateVariables = @($scope.FindAll({
            param([System.Management.Automation.Language.Ast]$Node)
            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.Right.Extent.Text -match '^\$PSCmdlet\.ShouldProcess\('
        }, $true) | ForEach-Object { $PSItem.Left.VariablePath.UserPath })

        # Gated: inside the body of an if clause whose condition is the gate.
        $gated = $false
        $child = $command
        $parent = $command.Parent
        while ($null -ne $parent -and $parent -ne $scope.Parent) {
            if ($parent -is [System.Management.Automation.Language.IfStatementAst]) {
                foreach ($clause in $parent.Clauses) {
                    if ($clause.Item2 -ne $child) { continue }
                    $condition = $clause.Item1.Extent.Text.Trim()
                    $isGate = ($condition -match "^$shouldProcess") -or
                        @($gateVariables | Where-Object { $condition -eq "`$$PSItem" }).Count -gt 0
                    if ($isGate) { $gated = $true }
                }
            }
            $child = $parent
            $parent = $parent.Parent
        }
        if ($gated) { continue }

        # After an early return: an earlier if that returns or throws when the gate declines.
        $start = $command.Extent.StartOffset
        $earlyReturn = @($scope.FindAll({
            param([System.Management.Automation.Language.Ast]$Node)
            $Node -is [System.Management.Automation.Language.IfStatementAst] -and
                $Node.Extent.EndOffset -lt $start
        }, $true) | Where-Object {
            $condition = $PSItem.Clauses[0].Item1.Extent.Text.Trim()
            $declined = ($condition -match "^(-not\s*|!\s*)\(?\s*$shouldProcess") -or
                @($gateVariables | Where-Object { $condition -match "^(-not\s*|!\s*)\`$$PSItem$" }).Count -gt 0
            $leaves = @($PSItem.Clauses[0].Item2.FindAll({
                param([System.Management.Automation.Language.Ast]$Node)
                $Node -is [System.Management.Automation.Language.ReturnStatementAst] -or
                    $Node -is [System.Management.Automation.Language.ThrowStatementAst]
            }, $true)).Count -gt 0
            $declined -and $leaves
        }).Count -gt 0
        if ($earlyReturn) { continue }

        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = "[AN-014] '$name' accepts -WhatIf but no ShouldProcess decision covers it. Put it inside if (`$PSCmdlet.ShouldProcess(...)), return early when ShouldProcess declines, or pass -WhatIf:`$false if it must run during a preview."
            Extent   = $command.Extent
            RuleName = 'Measure-AN014WhatIfDecided'
            Severity = 'Warning'
        }
    }
}

Export-ModuleMember -Function 'Measure-AN014WhatIfDecided'
