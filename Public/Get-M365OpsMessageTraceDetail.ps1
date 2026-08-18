function Get-M365OpsMessageTraceDetail {
    <#
    .SYNOPSIS
        Dettaglio degli hop di consegna per un singolo messaggio (dato MessageTraceId +
        destinatario, ottenuti da Get-M365OpsMessageTrace).
    .NOTES
        Usa Get-MessageTraceDetailV2, non il vecchio Get-MessageTraceDetail - stesso motivo di
        Get-M365OpsMessageTrace (cmdlet classica in dismissione, verificato su Microsoft Learn
        il 15/08/2026). Stessi due parametri, entrambi ancora obbligatori su V2.
        https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-messagetracedetailv2
    #>
    param(
        [Parameter(Mandatory)] [guid]$MessageTraceId,
        [Parameter(Mandatory)] [string]$RecipientAddress
    )
    Connect-M365OpsExchange
    Get-MessageTraceDetailV2 -MessageTraceId $MessageTraceId -RecipientAddress $RecipientAddress
}
