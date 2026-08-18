function Get-M365OpsRetentionCompliancePolicies {
    <#
    .SYNOPSIS
        Elenca le retention policy di Purview (Security & Compliance) con le rispettive regole
        associate (RetentionComplianceRule) - dove si applicano (Exchange/SharePoint/OneDrive/
        Teams), da quanto tempo, e l'azione al termine del periodo (mantieni, elimina, o
        entrambi con revisione).
    .NOTES
        Verificato dal vivo il 18/08/2026: Connect-IPPSSession espone SOLO i cmdlet coperti dai
        ruoli RBAC di Microsoft Purview effettivamente assegnati all'app - su un service
        principal con solo il ruolo per la Quarantena (vedi le cmdlet *QuarantineMessage* gia'
        funzionanti in questo modulo), Get-RetentionCompliancePolicy semplicemente non esiste
        nella sessione ("term not recognized", non un errore di permesso esplicito - la
        differenza rispetto a SharePoint/Teams, che invece rispondono con un errore di permesso
        chiaro). Serve assegnare il ruolo "Compliance Administrator" (o un ruolo piu' mirato alla
        gestione retention) al service principal/utente da Microsoft Purview
        (compliance.microsoft.com > Ruoli e ambiti > Autorizzazioni) - vedi sezione 4.5 della
        guida.
    #>
    Connect-M365OpsCompliance
    $policies = @(Get-RetentionCompliancePolicy)
    foreach ($policy in $policies) {
        $rules = @(Get-RetentionComplianceRule -Policy $policy.Name -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Name              = $policy.Name
            Enabled           = $policy.Enabled
            Mode              = $policy.Mode
            Workload          = ($policy.Workload -join ', ')
            ExchangeLocation  = ($policy.ExchangeLocation -join ', ')
            SharePointLocation = ($policy.SharePointLocation -join ', ')
            OneDriveLocation  = ($policy.OneDriveLocation -join ', ')
            TeamsLocation     = ($policy.TeamsLocation -join ', ')
            WhenCreated       = $policy.WhenCreated
            Rules             = @($rules | ForEach-Object {
                [pscustomobject]@{
                    Name             = $_.Name
                    RetentionDuration = $_.RetentionDuration
                    RetentionComplianceAction = $_.RetentionComplianceAction
                    ExpirationDateOption = $_.ExpirationDateOption
                }
            })
        }
    }
}
