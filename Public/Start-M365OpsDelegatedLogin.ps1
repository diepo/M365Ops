function Start-M365OpsDelegatedLogin {
    <#
    .SYNOPSIS
        Avvia il login delegato (utente + MFA) per il tenant ATTIVO - richiede
        AuthMode = 'Delegated' nel profilo. Restituisce il codice e l'URL che l'utente
        deve aprire; il completamento va verificato con Complete-M365OpsDelegatedLogin
        (polling, non blocca qui). La sessione precedente eventualmente in corso per
        questo tenant viene sovrascritta.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    if ($script:M365OpsContext.AuthMode -ne 'Delegated') {
        throw "Il tenant '$($script:M365OpsContext.Name)' e' in modalita' AppOnly, non Delegated - il login utente non serve (usa gia' l'App Registration configurata)."
    }

    $flow = Start-M365OpsDeviceCodeFlow -TenantId $script:M365OpsContext.TenantId

    if (-not $script:M365OpsPendingDeviceCode) { $script:M365OpsPendingDeviceCode = @{} }
    $script:M365OpsPendingDeviceCode[$script:M365OpsContext.Name] = $flow

    [pscustomobject]@{
        Tenant          = $script:M365OpsContext.Name
        UserCode        = $flow.UserCode
        VerificationUri = $flow.VerificationUri
        ExpiresAt       = $flow.ExpiresAt
        Interval        = $flow.Interval
    }
}
