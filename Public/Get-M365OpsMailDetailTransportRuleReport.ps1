function Get-M365OpsMailDetailTransportRuleReport {
    <#
    .SYNOPSIS
        Report dettagliato di quali messaggi hanno attivato quali regole di trasporto, in
        un intervallo di date - utile per verificare se/quanto una regola sta davvero
        agendo nella pratica, non solo se e' abilitata. Diverso da Get-M365OpsTransportRules
        (che mostra la CONFIGURAZIONE delle regole, non il loro effetto reale sui messaggi).
    .NOTES
        Mode: ReadOnly
    #>
    param(
        [datetime]$StartDate = (Get-Date).AddDays(-7),
        [datetime]$EndDate = (Get-Date),
        [string]$SenderAddress,
        [string]$RecipientAddress
    )
    Connect-M365OpsExchange
    $params = @{ StartDate = $StartDate; EndDate = $EndDate }
    if ($SenderAddress) { $params.SenderAddress = $SenderAddress }
    if ($RecipientAddress) { $params.RecipientAddress = $RecipientAddress }
    Get-MailDetailTransportRuleReport @params
}
