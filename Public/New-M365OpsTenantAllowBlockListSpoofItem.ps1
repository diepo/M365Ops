function New-M365OpsTenantAllowBlockListSpoofItem {
    <#
    .SYNOPSIS
        Aggiunge una coppia spoof (mittente falsificato + infrastruttura di invio reale) alla
        Tenant Allow/Block List - Allow per un falso positivo (mittente legittimo bloccato per
        errore), Block per un falso negativo (spoofing reale non intercettato dai criteri
        normali). Sintassi verificata contro la documentazione ufficiale Microsoft (non a
        memoria) il 18/08/2026.
    .PARAMETER SendingInfrastructure
        Il vero dominio/IP sorgente da cui arriva il messaggio (dal record DNS del server
        mittente), non il dominio che appare come "From" visibile - quello e' SpoofedUser.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Allow', 'Block')] [string]$Action,
        [Parameter(Mandatory)] [string]$SendingInfrastructure,
        [Parameter(Mandatory)] [string]$SpoofedUser,
        [Parameter(Mandatory)] [ValidateSet('Internal', 'External')] [string]$SpoofType
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop OBBLIGATORIO qui - bug reale trovato dal vivo il 18/08/2026: senza,
    # un errore lato server ("A server side error has occurred...") e' non terminante e
    # veniva ignorato in silenzio, la funzione riportava "Fatto" senza aver creato nulla per
    # davvero (verificato: Get-TenantAllowBlockListSpoofItems restituiva elenco vuoto subito dopo).
    New-TenantAllowBlockListSpoofItems -Identity 'Default' -Action $Action -SendingInfrastructure $SendingInfrastructure -SpoofedUser $SpoofedUser -SpoofType $SpoofType -Confirm:$false -ErrorAction Stop
    Write-Host "Voce spoof aggiunta ($Action): $SpoofedUser da $SendingInfrastructure ($SpoofType)" -ForegroundColor Green
}
