function New-M365OpsAntiPhishPolicy {
    <#
    .SYNOPSIS
        Crea un criterio anti-phishing - soglia di rilevamento, intelligence su
        mailbox/spoofing, azione in caso di autenticazione fallita (SPF/DKIM/DMARC).
        -ExtraParams passa altri parametri nativi di New-AntiPhishPolicy (es.
        PhishThresholdLevel, EnableMailboxIntelligence, EnableSpoofIntelligence,
        AuthenticationFailAction) - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "New-AntiPhishPolicy". Sintassi verificata contro la documentazione
        ufficiale Microsoft (non a memoria) il 21/08/2026: unico parametro davvero
        obbligatorio e' Name.
    .NOTES
        Un criterio da solo non si applica a nessuno: serve anche una regola che lo colleghi
        a dei destinatari (New-M365OpsAntiPhishRule).
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    $policy = New-AntiPhishPolicy @params -ErrorAction Stop
    Write-Host "Criterio anti-phishing creato: $Name" -ForegroundColor Green
    $policy | Select-Object Name, Enabled, PhishThresholdLevel, EnableMailboxIntelligence, EnableSpoofIntelligence
}
