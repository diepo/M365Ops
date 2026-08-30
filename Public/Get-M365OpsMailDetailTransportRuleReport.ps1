function Get-M365OpsMailDetailTransportRuleReport {
    <#
    .SYNOPSIS
        Report dettagliato di quali messaggi hanno attivato quali regole di trasporto, in
        un intervallo di date - utile per verificare se/quanto una regola sta davvero
        agendo nella pratica, non solo se e' abilitata. Diverso da Get-M365OpsTransportRules
        (che mostra la CONFIGURAZIONE delle regole, non il loro effetto reale sui messaggi).
    .NOTES
        Mode: ReadOnly

        Finestra dati (bug reale, corretto): la documentazione Microsoft per
        Get-MailDetailTransportRuleReport accetta una data di inizio fino a 30 giorni indietro,
        ma restituisce comunque solo gli ultimi 10 giorni di dati - un intervallo richiesto piu'
        ampio di 10 giorni non genera errori ma puo' restituire dati silenziosamente incompleti,
        quindi qui si avvisa esplicitamente in $script:M365OpsLastReportWarnings quando succede
        (stesso meccanismo usato in Get-M365OpsMessageTrace.ps1).

        PageSize (bug reale, corretto): la cmdlet ha default PageSize 1000/Page 1 (max
        documentato 5000) e non veniva mai impostato - un tenant con piu' di 1000 risultati
        otteneva silenziosamente solo la prima pagina. Ora si imposta esplicitamente il massimo
        documentato (5000) e si avvisa se il numero di righe restituite e' pari al PageSize
        (segnale che potrebbero esserci altri dati oltre questa pagina).
    #>
    param(
        [datetime]$StartDate = (Get-Date).AddDays(-7),
        [datetime]$EndDate = (Get-Date),
        [string]$SenderAddress,
        [string]$RecipientAddress
    )
    Connect-M365OpsExchange
    $script:M365OpsLastReportWarnings = $null
    $warnings = @()
    $pageSize = 5000

    if ((New-TimeSpan -Start $StartDate -End $EndDate).TotalDays -gt 10) {
        $warnings += "Intervallo richiesto superiore a 10 giorni: Get-MailDetailTransportRuleReport accetta una data di inizio fino a 30 giorni fa, ma restituisce comunque solo gli ultimi 10 giorni di dati - la parte piu' vecchia del periodo potrebbe risultare mancante senza errore."
    }

    $params = @{ StartDate = $StartDate; EndDate = $EndDate; PageSize = $pageSize }
    if ($SenderAddress) { $params.SenderAddress = $SenderAddress }
    if ($RecipientAddress) { $params.RecipientAddress = $RecipientAddress }
    $results = @(Get-MailDetailTransportRuleReport @params)

    if ($results.Count -ge $pageSize) {
        $warnings += "Risultato pari al PageSize ($pageSize): potrebbero esserci altri dati oltre questa pagina."
    }
    if ($warnings.Count -gt 0) { $script:M365OpsLastReportWarnings = $warnings }

    return $results
}
