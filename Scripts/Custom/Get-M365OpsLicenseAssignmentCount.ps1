function Get-M365OpsLicenseAssignmentCount {
<#
.SYNOPSIS
Conta le licenze Microsoft 365 assegnate nel tenant, elencando nome e quantita per ciascuna.
.NOTES
Mode: ReadOnly
CatalogTrigger: ^.*\b(licenze|license)\b.*$ 
#>

    # Chiamata Graph per ottenere le assegnazioni delle licenze utente
    $path = '/subscribedSkus?$select=skuPartNumber,consumedUnits'
    $result = Invoke-M365OpsGraphRequest -Method GET -Path $path
    $lines = foreach ($sku in $result.value) {
        "$($sku.skuPartNumber): assegnate $($sku.consumedUnits)"
    }
    return "Licenze assegnate nel tenant:`n" + ($lines -join "`n")
}

