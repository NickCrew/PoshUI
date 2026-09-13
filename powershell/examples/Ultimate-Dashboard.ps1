#Requires -Version 7.6

[CmdletBinding()]
param(
    [switch]$Auto,
    [ValidateRange(1, 100)][int]$Iterations = 1,
    [ValidateRange(0, 60)][int]$RefreshInterval = 0
)

Import-Module (Join-Path $PSScriptRoot '..' 'PoshUI.psd1') -Force -ErrorAction Stop

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    Show-PoshUIHeader DASHBOARD "System snapshot $iteration"
    Show-PoshUIGauge -Value (40 + $iteration) -Max 100 -Label CPU -Width 24
    Show-PoshUIGauge -Value (60 + $iteration) -Max 100 -Label Memory -Width 24
    Show-PoshUISparkline -Data 30, 42, 38, 55, 48, (40 + $iteration)

    $table = New-PoshUITable -Style Rounded -Header Service, Status
    Add-PoshUITableRow -Table $table -Values api, (Format-PoshUIStatus Success Running)
    Add-PoshUITableRow -Table $table -Values worker, (Format-PoshUIStatus Info Queued)
    Show-PoshUITable -Table $table

    if ($iteration -lt $Iterations -and $RefreshInterval -gt 0) {
        Start-Sleep -Seconds $RefreshInterval
    }
}

if (-not $Auto) {
    Format-PoshUIStatus Info 'Run with -Auto for noninteractive use' | Show-PoshUIBox -Title Hint
}
