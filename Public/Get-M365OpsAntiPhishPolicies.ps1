function Get-M365OpsAntiPhishPolicies {
    <#
    .SYNOPSIS
        Elenca i criteri anti-phishing: soglia di rilevamento, intelligence su mailbox/spoofing
        attive, azione in caso di autenticazione fallita (SPF/DKIM/DMARC).
    #>
    Connect-M365OpsExchange
    Get-AntiPhishPolicy |
        Select-Object Name, IsDefault, Enabled, PhishThresholdLevel, EnableMailboxIntelligence,
            EnableSpoofIntelligence, AuthenticationFailAction
}
