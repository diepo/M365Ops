function Get-M365OpsQuarantineMessages {
    <#
    .SYNOPSIS
        Elenca i messaggi in quarantena (spam/phishing/malware bloccati in ingresso o uscita),
        filtrabili per periodo/mittente/destinatario/tipo. Default: ultimi 7 giorni.
    .NOTES
        Restituisce l'oggetto nativo di Get-QuarantineMessage senza selezionare un sottoinsieme
        di campi: il tenant di test non ha messaggi in quarantena al momento della stesura, non
        c'e' modo di verificare dal vivo i nomi esatti dei campi restituiti (regola del modulo:
        mai un nome di colonna indovinato/non verificato, vedi la regola su colonne aggiunte di
        iniziativa in Invoke-M365OpsAgentTools) - meglio l'oggetto completo, verboso ma sempre
        corretto, che un Select-Object con nomi di proprieta' indovinati che rischiano di
        restituire colonne vuote.
    #>
    param(
        [datetime]$StartReceivedDate = (Get-Date).AddDays(-7),
        [datetime]$EndReceivedDate = (Get-Date),
        [string]$RecipientAddress,
        [string]$SenderAddress,
        [ValidateSet('Bulk', 'HighConfPhish', 'Malware', 'Phish', 'Spam', 'SPOMalware', 'TransportRule')] [string]$Type
    )
    Connect-M365OpsExchange
    $params = @{ StartReceivedDate = $StartReceivedDate; EndReceivedDate = $EndReceivedDate; PageSize = 1000 }
    if ($RecipientAddress) { $params.RecipientAddress = $RecipientAddress }
    if ($SenderAddress) { $params.SenderAddress = $SenderAddress }
    if ($Type) { $params.Type = $Type }
    Get-QuarantineMessage @params
}
