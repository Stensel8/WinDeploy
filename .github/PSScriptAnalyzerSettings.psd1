@{
    # Rules excluded for WinDeploy:
    #
    # PSAvoidUsingWriteHost      -- Deployment scripts intentionally use Write-Host for coloured output.
    # PSReviewUnusedParameter    -- Parameters can be used via splatting or dynamic dispatch.
    # PSUseShouldProcessForStateChangingFunctions -- Admin deployment tools don't need ShouldProcess.
    # PSAvoidUsingCmdletAliases  -- A few short aliases are used intentionally in interactive helpers.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSReviewUnusedParameter',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingCmdletAliases'
    )

    # PSUseCompatibleCmdlets: flag cmdlets removed or unavailable in PowerShell 7 on Windows.
    Rules = @{
        PSUseCompatibleCmdlets = @{
            compatibility = @(
                'core-7.2.0-windows'
            )
        }
    }
}
