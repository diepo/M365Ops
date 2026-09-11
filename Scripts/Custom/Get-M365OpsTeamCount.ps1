function Get-M365OpsTeamCount {
<#
.SYNOPSIS
Conta i Microsoft Teams presenti nel tenant.
.NOTES
Mode: ReadOnly
CatalogTrigger: ^.*\bteam(s)?\b.*$
#>

    # Chiamata Graph per ottenere i gruppi con Teams associati
    $path = "/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id"
    $result = Invoke-M365OpsGraphRequest -Method GET -Path $path

    # Conta i team trovati
    $count = @($result.value).Count

    return "Numero di Microsoft Teams nel tenant: $count"
}

