@{
    # The documented agent permission rules for gate check GK08 (rules PM-001 and
    # PM-002). Copy into the repository (for example gate/agent-permissions.psd1) and
    # name the copy in gate.config.psd1 under Permissions.
    #
    # Each entry: Path is a committed agent settings file, relative to the repository
    # root; Keys is every top-level key the file may hold, and PermissionKeys every key
    # its permissions block may hold, so a setting such as defaultMode, hooks or env
    # cannot be added unseen; Allow is every allow rule the file may hold; Deny is every
    # deny rule it must hold. A file may add deny rules, but not drop one, and may not
    # hold an allow rule missing from Allow. Loosening the rules therefore means
    # changing this file in the same diff.
    #
    # A committed .claude/settings.json or .cursor/cli.json with no entry here fails
    # PM-002.

    Files = @(
        @{
            Path           = '.claude/settings.json'
            Keys           = @('$schema', 'permissions')
            PermissionKeys = @('allow', 'deny')
            Allow = @(
                'Bash(pwsh -NoProfile -File ./tools/gate/Scripts/Invoke-Gate.ps1*)'
                'Bash(git status *)'
                'Bash(git diff *)'
                'Bash(git log *)'
                'Bash(git show *)'
            )
            Deny  = @(
                'Bash(git push *)'
                'Bash(rm *)'
                'Bash(rmdir *)'
                'Read(~/.aws/**)'
                'Read(~/.ssh/**)'
                'Read(~/.claude/.credentials.json)'
            )
        }
    )
}
