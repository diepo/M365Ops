function Start-M365OpsExchangeDelegatedLogin {
    <#
    .SYNOPSIS
        Avvia il login delegato per Exchange Online (utente + MFA) per il tenant ATTIVO -
        richiede AuthMode = 'Delegated'. A differenza di Connect-M365OpsExchange -AllowInteractive
        (che chiama Connect-ExchangeOnline -Device e BLOCCA il server per tutta la durata del
        login, con il codice visibile solo nella console del processo), questa funzione fa
        SOLO la richiesta del codice device (rapida, non bloccante) - il completamento va
        verificato con Complete-M365OpsExchangeDelegatedLogin (polling, anch'esso non bloccante).
        Solo l'ultimo passo (Connect-ExchangeOnline -AccessToken, dentro Complete-...) tocca
        Exchange Online, e a quel punto e' rapido perche' il token e' gia' pronto.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    if ($script:M365OpsContext.AuthMode -ne 'Delegated') {
        throw "Il tenant '$($script:M365OpsContext.Name)' e' in modalita' AppOnly, non Delegated - la connessione Exchange e' gia' silenziosa via certificato."
    }
    if (-not $script:M365OpsContext.DelegatedUpn) {
        throw "Il profilo '$($script:M365OpsContext.Name)' non ha un DelegatedUpn configurato. Usa Set-M365OpsTenant -DelegatedUpn per impostarlo."
    }

    $flow = Start-M365OpsDeviceCodeFlow -TenantId $script:M365OpsContext.TenantId `
        -ClientId $script:M365OpsExoDeviceCodeClientId -Scope $script:M365OpsExoDeviceCodeScopes

    if (-not $script:M365OpsPendingExoDeviceCode) { $script:M365OpsPendingExoDeviceCode = @{} }
    $script:M365OpsPendingExoDeviceCode[$script:M365OpsContext.Name] = $flow

    [pscustomobject]@{
        Tenant          = $script:M365OpsContext.Name
        UserCode        = $flow.UserCode
        VerificationUri = $flow.VerificationUri
        ExpiresAt       = $flow.ExpiresAt
        Interval        = $flow.Interval
    }
}
