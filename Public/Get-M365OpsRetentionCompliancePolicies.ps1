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
        # Try/catch per policy (bug reale, stesso schema gia' corretto piu' volte in questo
        # progetto - vedi Get-M365OpsCompliancePatterns.ps1): -ErrorAction SilentlyContinue
        # inghiottiva qualunque fallimento reale nel recupero delle regole (throttling
        # transitorio di Purview, una policy rinominata/rimossa durante il ciclo, RBAC piu'
        # ristretto sulle regole rispetto alle policy) producendo silenziosamente Rules = @(),
        # indistinguibile da una policy che legittimamente non ha regole. Ora un fallimento
        # resta locale a questa policy (segnalato in "Rules" invece di sparire), le altre
        # policy proseguono comunque.
        try {
            $rules = @(Get-RetentionComplianceRule -Policy $policy.Name -ErrorAction Stop)
        }
        catch {
            Write-M365OpsLog "Get-M365OpsRetentionCompliancePolicies: impossibile recuperare le regole per la policy $($policy.Name): $($_.Exception.Message)" -Level Warn
            $rules = @([pscustomobject]@{ error = "Regole non recuperabili per questa policy: $($_.Exception.Message)" })
        }
        [pscustomobject]@{
            Name              = $policy.Name
            Enabled           = $policy.Enabled
            Mode              = $policy.Mode
            Workload          = ($policy.Workload -join ', ')
            ExchangeLocation  = ($policy.ExchangeLocation -join ', ')
            SharePointLocation = ($policy.SharePointLocation -join ', ')
            OneDriveLocation  = ($policy.OneDriveLocation -join ', ')
            # Bug reale trovato dal vivo il 23/08/2026 (bug-hunt di 16 ore): 'TeamsLocation' non
            # esiste sull'oggetto restituito da Get-RetentionCompliancePolicy - Teams espone DUE
            # proprieta' separate (i messaggi canale e le chat vivono in store diversi), mai una
            # sola. Riferirsi a una proprieta' inesistente su un PSCustomObject in PowerShell non
            # lancia un errore: restituisce silenziosamente $null, quindi questa colonna era
            # SEMPRE vuota per OGNI policy, anche per una che copre davvero Teams - l'AI avrebbe
            # affermato con sicurezza che nessuna policy copre Teams, l'esatto tipo di lacuna di
            # reporting compliance che questa funzione esiste per intercettare.
            TeamsChannelLocation = ($policy.TeamsChannelLocation -join ', ')
            TeamsChatLocation    = ($policy.TeamsChatLocation -join ', ')
            WhenCreated       = $policy.WhenCreated
            # La mappatura sotto normalizzava tutte le voci di $rules sullo stesso schema fisso,
            # il che avrebbe scartato silenziosamente la proprieta' "error" prodotta dal catch
            # sopra (stesso bug, un passo piu' in la') - preservata qui passando "Error" nel
            # risultato mappato.
            Rules             = @($rules | ForEach-Object {
                [pscustomobject]@{
                    Name             = $_.Name
                    RetentionDuration = $_.RetentionDuration
                    RetentionComplianceAction = $_.RetentionComplianceAction
                    ExpirationDateOption = $_.ExpirationDateOption
                    Error            = $_.error
                }
            })
        }
    }
}
