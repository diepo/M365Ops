function Get-M365OpsReceiveConnector {
    <#
    .SYNOPSIS
        Elenca i connettori Receive (regole su come il tenant ACCETTA posta in ingresso da
        fonti specifiche - tipicamente usati per integrare un gateway di sicurezza email di
        terze parti o un server on-premise in scenari ibridi, raro su un tenant cloud-only
        semplice).
    .NOTES
        Mode: ReadOnly
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    if ($Identity) { Get-ReceiveConnector -Identity $Identity }
    else { Get-ReceiveConnector | Select-Object Name, Enabled, RemoteIPRanges }
}
