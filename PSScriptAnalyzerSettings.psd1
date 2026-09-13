@{
    # Every rule runs except the ones excluded below. Each exclusion records why,
    # because a settings file whose job is silencing findings is worse than no
    # settings file: the count goes green and nobody knows what was traded away.
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')

    ExcludeRules        = @(
        # PoshUI's entire job is rendering to the terminal. Write-Host is the
        # rendering surface, not incidental logging, so this rule fires on
        # every module that draws a box, table, menu, or chart: 280 findings,
        # all on code doing exactly what the module exists to do.
        'PSAvoidUsingWriteHost',

        # This rule wants a BOM so legacy Windows PowerShell 5.1 can detect
        # UTF-8. Every source file here is already git-tracked UTF-8 without
        # a BOM, which is the standard cross-platform convention and avoids
        # BOM-related diff noise. Adding one would be a regression, not a fix.
        'PSUseBOMForUnicodeEncodedFile',

        # The manifest declares the complete public surface. The root loader
        # filters that inventory when feature toggles disable a module, so its
        # final Export-ModuleMember call is necessarily variable-driven.
        'PSUseToExportFieldsInManifest',

        # Scriptblocks and compatibility parameters are invoked through nested
        # scopes in the benchmark and public chart functions. The analyzer
        # cannot see those uses and reports them as unused.
        'PSReviewUnusedParameter',

        # Terminal capability probes intentionally treat failed host APIs as
        # unavailable features. Those catches degrade to the safe path without
        # emitting a second error from the presentation layer.
        'PSAvoidUsingEmptyCatchBlock'
    )
}
