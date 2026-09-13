#Requires -Version 7.6

$manifest = Join-Path $PSScriptRoot '..' 'PoshUI.psd1'
Import-Module $manifest -Force -ErrorAction Stop
