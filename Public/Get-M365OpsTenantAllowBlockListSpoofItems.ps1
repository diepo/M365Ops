function Get-M365OpsTenantAllowBlockListSpoofItems {
    <#
    .SYNOPSIS
        Elenca le coppie spoof (mittente falsificato + infrastruttura di invio reale)
        configurate nella Tenant Allow/Block List - una sotto-lista separata dalle voci
        normali per mittente/URL/hash/IP (vedi Get-M365OpsTenantAllowBlockList), pensata
        specificamente per i falsi positivi/negativi dell'anti-spoofing.
    .NOTES
        L'Identity di ogni voce restituita (un GUID) va usata con Remove-M365Ops
        TenantAllowBlockListSpoofItem per rimuoverla - mai indovinata.
        Mode: ReadOnly
    #>
    param(
        [ValidateSet('Allow', 'Block')] [string]$Action,
        [ValidateSet('Internal', 'External')] [string]$SpoofType
    )
    Connect-M365OpsExchange
    $params = @{ Identity = 'Default' }
    if ($Action) { $params.Action = $Action }
    if ($SpoofType) { $params.SpoofType = $SpoofType }
    # Solo le proprieta' esplicitamente documentate da Microsoft (Identity, SpoofedUser,
    # SendingInfrastructure, SpoofType) - la pagina non conferma altri campi di output,
    # meglio non aggiungerne a intuito (vedi convenzione #6 del README).
    Get-TenantAllowBlockListSpoofItems @params |
        Select-Object Identity, SpoofedUser, SendingInfrastructure, SpoofType
}
