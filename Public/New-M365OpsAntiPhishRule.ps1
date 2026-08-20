function New-M365OpsAntiPhishRule {
    <#
    .SYNOPSIS
        Crea una regola che collega un criterio anti-phishing esistente (AntiPhishPolicy) a
        dei destinatari specifici - senza una regola, un criterio anti-phishing non si
        applica a nessuno. -ExtraParams passa altri parametri nativi di New-AntiPhishRule
        (es. ExceptIfRecipientDomainIs, ExceptIfSentTo, Priority, Comments) - se non sei
        sicuro del nome esatto, consulta prima lookup_ms_docs "New-AntiPhishRule". Sintassi
        verificata contro la documentazione ufficiale Microsoft (non a memoria) il
        21/08/2026.
    .NOTES
        Un criterio anti-phishing puo' essere collegato a UNA SOLA regola (non e' possibile
        riusarlo su piu' regole) - Microsoft lo impedisce direttamente al momento della
        creazione, non e' un limite di questo wrapper.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$AntiPhishPolicy,
        [string[]]$RecipientDomainIs,
        [string[]]$SentTo,
        [string[]]$SentToMemberOf,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name; AntiPhishPolicy = $AntiPhishPolicy }
    if ($RecipientDomainIs) { $params.RecipientDomainIs = $RecipientDomainIs }
    if ($SentTo) { $params.SentTo = $SentTo }
    if ($SentToMemberOf) { $params.SentToMemberOf = $SentToMemberOf }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    $rule = New-AntiPhishRule @params -ErrorAction Stop
    Write-Host "Regola anti-phishing creata: $Name" -ForegroundColor Green
    $rule | Select-Object Name, State, AntiPhishPolicy, RecipientDomainIs, SentTo
}
