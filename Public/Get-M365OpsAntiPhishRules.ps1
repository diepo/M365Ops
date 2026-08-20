function Get-M365OpsAntiPhishRules {
    <#
    .SYNOPSIS
        Elenca le regole anti-phishing: a QUALI destinatari si applica ciascun criterio
        anti-phishing (Get-M365OpsAntiPhishPolicies) - una policy senza una regola collegata
        non si applica a nessuno, tranne quella predefinita del sistema.
    .NOTES
        Mode: ReadOnly
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    if ($Identity) { Get-AntiPhishRule -Identity $Identity }
    else { Get-AntiPhishRule | Select-Object Name, State, Priority, AntiPhishPolicy, RecipientDomainIs, SentTo, SentToMemberOf }
}
