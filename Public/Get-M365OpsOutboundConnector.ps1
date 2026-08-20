function Get-M365OpsOutboundConnector {
    <#
    .SYNOPSIS
        Elenca i connettori Outbound (regole su come il tenant INVIA posta verso
        destinazioni specifiche - tipicamente usati per instradare la posta verso un
        partner/gateway di sicurezza specifico invece che direttamente su internet, o per
        scenari ibridi).
    .NOTES
        Mode: ReadOnly

        Stesso bug strutturale di Get-M365OpsInboundConnector.ps1 (vedi nota li' per il
        dettaglio completo): Get-SendConnector e' esclusivo di Exchange on-premises, mai
        esistito in Exchange Online - sostituito con Get-OutboundConnector il 21/08/2026.
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    if ($Identity) { Get-OutboundConnector -Identity $Identity }
    else { Get-OutboundConnector | Select-Object Name, Enabled, ConnectorType, RecipientDomains, SmartHosts }
}
