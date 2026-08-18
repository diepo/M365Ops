param(
    [string]$TenantProfile = "contoso-test"
)

Import-Module (Join-Path $PSScriptRoot 'M365Ops.psd1') -Force
Connect-M365Ops -TenantProfile $TenantProfile

Write-Host "`nPronto. Esempi:" -ForegroundColor Cyan
Write-Host "  Get-M365OpsManagedDevices"
Write-Host "  Get-M365OpsCompliancePatterns"
Write-Host "  Get-Command -Module M365Ops   # elenco completo cmdlet"
