function Get-M365OpsAntiSpamPolicies {
    <#
    .SYNOPSIS
        Elenca i criteri anti-spam in ingresso (Hosted Content Filter Policy): come vengono
        trattati spam/spam ad alta confidenza/phishing/bulk mail (scarta, mette in quarantena,
        sposta nella cartella posta indesiderata).
    #>
    Connect-M365OpsExchange
    Get-HostedContentFilterPolicy |
        Select-Object Name, IsDefault, SpamAction, HighConfidenceSpamAction, PhishSpamAction,
            HighConfidencePhishAction, BulkSpamAction, BulkThreshold, QuarantineRetentionPeriod
}
