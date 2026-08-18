function Get-M365OpsRemoteDomain {
    <#
    .SYNOPSIS
        Elenca le impostazioni per dominio remoto (formato messaggi, risposte
        automatiche/assenza consentite, inoltro automatico) - controllano come il tenant
        invia posta verso un dominio esterno specifico, "Default" per tutti gli altri.
    .NOTES
        Mode: ReadOnly
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    if ($Identity) { Get-RemoteDomain -Identity $Identity }
    else { Get-RemoteDomain | Select-Object Name, DomainName, AutoForwardEnabled, AutoReplyEnabled, AllowedOOFType }
}
