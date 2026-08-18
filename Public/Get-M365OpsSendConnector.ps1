function Get-M365OpsSendConnector {
    <#
    .SYNOPSIS
        Elenca i connettori Send (regole su come il tenant INVIA posta verso destinazioni
        specifiche - tipicamente usati per instradare la posta verso un partner/gateway di
        sicurezza specifico invece che direttamente su internet, o per scenari ibridi).
    .NOTES
        Mode: ReadOnly
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    if ($Identity) { Get-SendConnector -Identity $Identity }
    else { Get-SendConnector | Select-Object Name, Enabled, AddressSpaces, SmartHosts }
}
