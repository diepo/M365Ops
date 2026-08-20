function Get-M365OpsAntiSpamRules {
    <#
    .SYNOPSIS
        Elenca le regole anti-spam (Hosted Content Filter Rule): a QUALI destinatari si
        applica ciascun criterio anti-spam (Get-M365OpsAntiSpamPolicies) - una policy senza
        una regola collegata non si applica a nessuno, tranne quella "Default" del sistema.
    .NOTES
        Mode: ReadOnly
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    if ($Identity) { Get-HostedContentFilterRule -Identity $Identity }
    else { Get-HostedContentFilterRule | Select-Object Name, State, Priority, HostedContentFilterPolicy, RecipientDomainIs, SentTo, SentToMemberOf }
}
