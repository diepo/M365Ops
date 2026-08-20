function New-M365OpsAntiSpamRule {
    <#
    .SYNOPSIS
        Crea una regola che collega un criterio anti-spam esistente (HostedContentFilterPolicy)
        a dei destinatari specifici - senza una regola, un criterio anti-spam non si applica
        a nessuno. -ExtraParams passa altri parametri nativi di New-HostedContentFilterRule
        (es. ExceptIfRecipientDomainIs, ExceptIfSentTo, Priority, Comments) - se non sei
        sicuro del nome esatto, consulta prima lookup_ms_docs "New-HostedContentFilterRule".
        Sintassi verificata contro la documentazione ufficiale Microsoft (non a memoria) il
        21/08/2026.
    .NOTES
        Un criterio anti-spam puo' essere collegato a UNA SOLA regola (non e' possibile
        riusarlo su piu' regole) - Microsoft lo impedisce direttamente al momento della
        creazione, non e' un limite di questo wrapper.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$HostedContentFilterPolicy,
        [string[]]$RecipientDomainIs,
        [string[]]$SentTo,
        [string[]]$SentToMemberOf,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name; HostedContentFilterPolicy = $HostedContentFilterPolicy }
    if ($RecipientDomainIs) { $params.RecipientDomainIs = $RecipientDomainIs }
    if ($SentTo) { $params.SentTo = $SentTo }
    if ($SentToMemberOf) { $params.SentToMemberOf = $SentToMemberOf }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    $rule = New-HostedContentFilterRule @params -ErrorAction Stop
    Write-Host "Regola anti-spam creata: $Name" -ForegroundColor Green
    $rule | Select-Object Name, State, HostedContentFilterPolicy, RecipientDomainIs, SentTo
}
