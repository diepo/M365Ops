function Get-M365OpsGuestUserCount {
<#
.SYNOPSIS
Conta gli utenti ospiti (Guest) di Entra ID e restituisce una frase pronta.
.NOTES
Mode: ReadOnly
CatalogTrigger: ^.*\b(ospiti|guest)\b.*$ 
CatalogDefer: 
#>

    # Chiamata Graph per contare utenti con filtro userType eq 'Guest'
    $path = '/users?$filter=userType eq ''Guest''&$select=id'
    $result = Invoke-M365OpsGraphRequest -Method GET -Path $path
    $count = @($result.value).Count

    return "Il tenant ha $count utenti ospiti."
}

