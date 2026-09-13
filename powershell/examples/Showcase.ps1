#Requires -Version 7.6

[CmdletBinding()]
param([switch]$Auto)

Import-Module (Join-Path $PSScriptRoot '..' 'PoshUI.psd1') -Force -ErrorAction Stop

Show-PoshUIHeader -Label POSHUI -Title 'Terminal UI showcase'
$services = @(
    [pscustomobject]@{ Service = 'api'; Status = 'healthy'; Version = '26.8.0' }
    [pscustomobject]@{ Service = 'worker'; Status = 'queued'; Version = '26.8.0' }
)
$services |
    Format-PoshUIDataTable -Property Service, Status, Version |
    Show-PoshUIBox -Title Services -Style Rounded

Show-PoshUISparkline -Data 2, 4, 3, 7, 6, 9
Show-PoshUIGauge -Value 72 -Max 100 -Label CPU -Width 24
Format-PoshUIStatus Info "Automatic mode: $([bool]$Auto)" | Show-PoshUIBox -Title Runtime
