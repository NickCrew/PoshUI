#Requires -Version 7.6

[CmdletBinding()]
param([switch]$NoPause)

Import-Module (Join-Path $PSScriptRoot '..' 'PoshUI.psd1') -Force -ErrorAction Stop

Show-PoshUIHeader EXAMPLES 'Native component composition'
Format-PoshUIStatus Success Ready | Show-PoshUIBox -Title Status -Style Rounded
Show-PoshUIHorizontalBarChart -Title Jobs -Data 2, 4, 3 -Labels api, worker, scheduler -Width 12
Show-PoshUIGauge -Value 7 -Max 10 -Label Capacity -Width 20

if (-not $NoPause -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
    [void](Read-PoshUIText -Message 'Press Enter to finish' -Default '')
}
