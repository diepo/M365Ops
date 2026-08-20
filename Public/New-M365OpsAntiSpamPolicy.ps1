function New-M365OpsAntiSpamPolicy {
    <#
    .SYNOPSIS
        Crea un criterio anti-spam in ingresso (Hosted Content Filter Policy) - come vengono
        trattati spam/spam ad alta confidenza/phishing/bulk mail (scarta, mette in quarantena,
        sposta nella cartella posta indesiderata). -ExtraParams passa altri parametri nativi
        di New-HostedContentFilterPolicy (es. SpamAction, HighConfidenceSpamAction,
        PhishSpamAction, HighConfidencePhishAction, BulkSpamAction, BulkThreshold,
        QuarantineRetentionPeriod) - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "New-HostedContentFilterPolicy". Sintassi verificata contro la
        documentazione ufficiale Microsoft (non a memoria) il 21/08/2026: unico parametro
        davvero obbligatorio e' Name, tutte le azioni hanno un default Microsoft sensato se
        omesse.
    .NOTES
        Un criterio da solo non si applica a nessuno: serve anche una regola che lo colleghi
        a dei destinatari (New-M365OpsAntiSpamRule) - stesso schema di
        New-M365OpsQuarantinePolicy/QuarantinePolicy, la policy definisce COSA succede, la
        regola definisce A CHI si applica.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    $policy = New-HostedContentFilterPolicy @params -ErrorAction Stop
    Write-Host "Criterio anti-spam creato: $Name" -ForegroundColor Green
    $policy | Select-Object Name, SpamAction, HighConfidenceSpamAction, PhishSpamAction, BulkSpamAction
}
