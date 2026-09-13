#Requires -Version 7.6

param(
    [Parameter(Position = 0)]
    [string]$Mode
)

if ($Mode -and $Mode -ne '--minimal') {
    throw "Unknown PoshUI import mode '$Mode'. Expected --minimal."
}

$script:PoshUILibDir = $PSScriptRoot
$script:PoshUILoadedModules = [Collections.Generic.List[string]]::new()
$script:PoshUIPublicFunctions = @(
    (Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'PoshUI.psd1')).FunctionsToExport
)
$script:PoshUIExportedFunctions = [Collections.Generic.List[string]]::new()
$script:PoshUIModuleDirectory = Join-Path $PSScriptRoot 'modules'

$ExecutionContext.SessionState.Module.OnRemove = {
    Get-Module | Where-Object {
        $_.Path -and $_.Path.StartsWith($script:PoshUIModuleDirectory, [StringComparison]::OrdinalIgnoreCase)
    } | Remove-Module -Force -ErrorAction SilentlyContinue
}

$runtimeModule = Import-Module (Join-Path $PSScriptRoot 'modules' 'Runtime.psm1') -Force -PassThru -ErrorAction Stop
foreach ($functionName in $runtimeModule.ExportedFunctions.Keys) {
    if ($functionName -in $script:PoshUIPublicFunctions) {
        [void]$script:PoshUIExportedFunctions.Add($functionName)
    }
}

$script:PoshUILoad = @{}
foreach ($name in @(
        'COLORS', 'LOGGING', 'PROGRESS', 'ICONS', 'BOXES', 'TABLES', 'PROMPTS', 'MENUS', 'CHARTS'
        'LAYOUT', 'DATATABLE', 'LIVEREGION', 'TREE', 'SEARCHABLESELECTION', 'TEXTVIEWS', 'STEPPER'
    )) {
    $configured = [Environment]::GetEnvironmentVariable("POSH_UI_LOAD_$name")
    $script:PoshUILoad[$name] = [string]::IsNullOrEmpty($configured) -or $configured -eq 'true'
}

if ($Mode -eq '--minimal') {
    foreach ($name in @(
            'PROGRESS', 'BOXES', 'TABLES', 'PROMPTS', 'LAYOUT', 'DATATABLE'
            'LIVEREGION', 'TREE', 'SEARCHABLESELECTION', 'TEXTVIEWS', 'STEPPER'
        )) {
        $script:PoshUILoad[$name] = $false
    }
}

function Import-PoshUIFeatureInternal {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$File
    )

    $modulePath = Join-Path $script:PoshUILibDir 'modules' "$File.psm1"
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw [IO.FileNotFoundException]::new("PoshUI feature '$Name' was not found at '$modulePath'.")
    }

    $imported = Import-Module -Name $modulePath -Force -PassThru -ErrorAction Stop
    foreach ($functionName in $imported.ExportedFunctions.Keys) {
        if ($functionName -in $script:PoshUIPublicFunctions) {
            [void]$script:PoshUIExportedFunctions.Add($functionName)
        }
    }
    [void]$script:PoshUILoadedModules.Add($Name)
}

function Initialize-PoshUIInternal {
    Import-PoshUIFeatureInternal -Name configuration -File Configuration
    $features = [ordered]@{
        COLORS              = 'Colors'
        LOGGING             = 'Logging'
        ICONS               = 'Icons'
        PROGRESS            = 'Progress'
        BOXES               = 'Boxes'
        TABLES              = 'Tables'
        LAYOUT              = 'Layout'
        DATATABLE           = 'DataTable'
        TREE                = 'Tree'
        TEXTVIEWS           = 'TextViews'
        STEPPER             = 'Stepper'
        PROMPTS             = 'Prompts'
        MENUS               = 'Menus'
        SEARCHABLESELECTION = 'SearchableSelection'
        CHARTS              = 'Charts'
        LIVEREGION          = 'LiveRegion'
    }
    foreach ($name in $features.Keys) {
        if ($script:PoshUILoad[$name]) {
            Import-PoshUIFeatureInternal -Name $name.ToLowerInvariant() -File $features[$name]
        }
    }
}

$environmentBeforeImport = [Environment]::GetEnvironmentVariables()
try {
    Initialize-PoshUIInternal
}
finally {
    $environmentAfterImport = [Environment]::GetEnvironmentVariables()
    foreach ($name in $environmentAfterImport.Keys) {
        if (-not $environmentBeforeImport.Contains($name)) {
            Remove-Item -LiteralPath ('Env:{0}' -f $name) -ErrorAction SilentlyContinue
        }
    }
    foreach ($name in $environmentBeforeImport.Keys) {
        [Environment]::SetEnvironmentVariable([string]$name, [string]$environmentBeforeImport[$name])
    }
}

Export-ModuleMember -Function $script:PoshUIExportedFunctions
