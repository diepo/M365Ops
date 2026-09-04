function Invoke-M365OpsFullAccessAutoMapPlan {
    <#
    .SYNOPSIS
        Esegue le azioni calcolate da Get-M365OpsFullAccessAutoMapPlan (Revoke+Grant se il
        membro aveva gia' un grant diretto, altrimenti solo Grant - sempre con AutoMapping
        esplicito). Ogni azione e' isolata in un proprio try/catch: un errore su UNA non
        blocca le altre, ogni Get/Set e' loggato con Write-M365OpsLog, il risultato di
        ciascuna azione (incluso l'errore se fallita) e' restituito riga per riga - mai
        un'eccezione che interrompe l'intero batch. Richiesto esplicitamente dall'utente il
        31/08/2026: "ogni get set deve essere ovviamente loggato e ogni errore intercettato
        e gestito con output chiaro".
    .PARAMETER Actions
        L'array Actions restituito da Get-M365OpsFullAccessAutoMapPlan (o un sottoinsieme
        filtrato dall'utente prima dell'esecuzione).
    #>
    param(
        [Parameter(Mandatory)] [object[]]$Actions
    )

    $i = 0
    foreach ($a in $Actions) {
        $i++
        $outcome = [pscustomobject]@{
            Mailbox     = $a.Mailbox
            User        = $a.User
            SourceGroup = $a.SourceGroup
            RevokeOk    = $null
            GrantOk     = $false
            Error       = $null
        }
        try {
            if ($a.NeedsRevoke) {
                Write-M365OpsLog "AutoMapRepair [$i/$($Actions.Count)]: rimuovo grant diretto esistente di '$($a.User)' su '$($a.Mailbox)' prima di riassegnarlo con AutoMapping"
                Revoke-M365OpsMailboxPermission -Identity $a.Mailbox -User $a.User -PermissionType FullAccess
                $outcome.RevokeOk = $true
            }
            Write-M365OpsLog "AutoMapRepair [$i/$($Actions.Count)]: assegno FullAccess+AutoMapping a '$($a.User)' su '$($a.Mailbox)' (da gruppo '$($a.SourceGroup)')"
            Grant-M365OpsMailboxPermission -Identity $a.Mailbox -User $a.User -PermissionType FullAccess
            $outcome.GrantOk = $true
        } catch {
            $outcome.Error = $_.Exception.Message
            Write-M365OpsLog "AutoMapRepair [$i/$($Actions.Count)] FALLITO: '$($a.User)' su '$($a.Mailbox)' - $($_.Exception.Message)" -Level Error
        }
        $outcome
    }
}
