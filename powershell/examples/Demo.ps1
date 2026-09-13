#Requires -Version 7.6

[CmdletBinding()]
param([switch]$Auto)

Import-Module (Join-Path $PSScriptRoot '..' 'PoshUI.psd1') -Force -ErrorAction Stop

Show-PoshUIHeader -Label RELEASE -Title 'Stage deployment'
Show-PoshUIBox -Title Summary -Content @(
    'Artifact 26.8.0 passed verification'
    'Environment: stage'
) -Style Rounded

$table = New-PoshUITable -Style Rounded -Header Check, Status
Add-PoshUITableRow -Table $table -Values Package, Passed
Add-PoshUITableRow -Table $table -Values Health, Healthy
Show-PoshUITable -Table $table

$progress = New-PoshUIProgress -Total 4 -Current 4 -Label Deployment
$progress | Show-PoshUIProgress
Write-PoshUILog -Level Info -Message 'demo completed' -Data @{ automatic = [bool]$Auto }
