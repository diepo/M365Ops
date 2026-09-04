function Get-M365OpsFullAccessAutoMapPlan {
    <#
    .SYNOPSIS
        Per un elenco di mailbox, individua i permessi FullAccess assegnati a GRUPPI ed
        esplode ogni gruppo nei suoi membri, calcolando il piano di azioni necessario per
        dare a ciascun membro un accesso DIRETTO con AutoMapping esplicito. NON esegue
        nessuna scrittura - restituisce solo il piano (vedi
        Invoke-M365OpsFullAccessAutoMapPlan per eseguirlo), cosi' puo' essere riletto e
        confermato UNA SOLA VOLTA anche su centinaia di mailbox, invece di una conferma per
        singola assegnazione. Richiesto esplicitamente dall'utente il 31/08/2026.
    .NOTES
        LIMITE REALE di Exchange (Online e on-prem), non un'assunzione: il flag
        -AutoMapping di Add-MailboxPermission funziona SOLO per un grant DIRETTO a un
        singolo utente - imposta l'attributo Active Directory msExchDelegateListLink
        sull'oggetto utente, che Outlook legge per aggiungere da solo la mailbox al
        profilo. Quando il trustee e' un GRUPPO, quell'attributo non viene MAI impostato
        sui membri (Exchange valuta l'appartenenza al gruppo solo al momento del controllo
        di accesso, non al momento dell'assegnazione): l'accesso funziona comunque (i
        membri POSSONO aprire la mailbox), ma Outlook non la aggiunge mai in automatico,
        qualunque sia il valore di AutoMapping passato sul grant al gruppo. L'unico modo
        per abilitare davvero l'AutoMapping e' un grant diretto sul singolo utente - da qui
        la necessita' di "esplodere" il gruppo.

        Il grant sul gruppo NON viene mai proposto per la rimozione da questa funzione: va
        mantenuto per la gestione futura dell'accesso (nuovi membri del gruppo continuano a
        ricevere accesso automaticamente) - il compromesso e' che un membro aggiunto al
        gruppo DOPO questa esecuzione avra' comunque accesso ma non l'AutoMapping, finche'
        questo piano non viene ricalcolato ed eseguito di nuovo. Se un membro ha GIA' anche
        un grant diretto sulla stessa mailbox (oltre a quello ereditato dal gruppo), non e'
        possibile leggere da Exchange se l'AutoMapping era gia' attivo su quel grant
        (Get-MailboxPermission non espone questo stato) - il piano lo rimuove e lo
        riassegna sempre, per garantire lo stato finale corretto indipendentemente da
        quello di partenza.
    .PARAMETER Identities
        Elenco di Identity di mailbox (indirizzo email o UPN) su cui operare.
    #>
    param(
        [Parameter(Mandatory)] [string[]]$Identities
    )

    $actions = @()
    $errors = @()
    $groupMemberCache = @{}

    foreach ($mbx in $Identities) {
        Write-M365OpsLog "AutoMapRepair: lettura permessi FullAccess di '$mbx'"
        try {
            $perms = @(Get-M365OpsMailboxPermissions -Identity $mbx -ErrorAction Stop | Where-Object { $_.Type -eq 'FullAccess' })
        } catch {
            $msg = "Errore leggendo i permessi di '$mbx': $($_.Exception.Message)"
            Write-M365OpsLog $msg -Level Error
            $errors += [pscustomobject]@{ Mailbox = $mbx; Stage = 'ReadPermissions'; Group = $null; Error = $_.Exception.Message }
            continue
        }

        $directUserNames = @($perms | Where-Object { $_.TrusteeType -eq 'User' } | ForEach-Object { $_.User.ToLowerInvariant() })
        $groupGrants = @($perms | Where-Object { $_.TrusteeType -eq 'Group' })

        foreach ($g in $groupGrants) {
            $groupName = $g.User
            if (-not $groupMemberCache.ContainsKey($groupName)) {
                Write-M365OpsLog "AutoMapRepair: espansione membri del gruppo '$groupName'"
                try {
                    $groupMemberCache[$groupName] = @(Get-M365OpsDistributionGroupMembers -Identity $groupName -ErrorAction Stop | Select-Object -ExpandProperty PrimarySmtpAddress)
                } catch {
                    $msg = "Errore espandendo il gruppo '$groupName' (mailbox '$mbx'): $($_.Exception.Message)"
                    Write-M365OpsLog $msg -Level Error
                    $errors += [pscustomobject]@{ Mailbox = $mbx; Stage = 'ExpandGroup'; Group = $groupName; Error = $_.Exception.Message }
                    $groupMemberCache[$groupName] = @()
                }
            }

            foreach ($member in $groupMemberCache[$groupName]) {
                if (-not $member) { continue }
                $alreadyDirect = $directUserNames -contains $member.ToLowerInvariant()
                $actions += [pscustomobject]@{
                    Mailbox     = $mbx
                    User        = $member
                    SourceGroup = $groupName
                    NeedsRevoke = $alreadyDirect
                }
            }
        }
    }

    # Stessa coppia mailbox+utente puo' comparire piu' volte se e' membro di PIU' gruppi
    # con FullAccess sulla stessa mailbox - un solo grant diretto basta, deduplicato qui
    # invece che a valle nell'esecuzione.
    $dedupedActions = $actions | Group-Object Mailbox, User | ForEach-Object { $_.Group[0] }

    [pscustomobject]@{
        Actions = @($dedupedActions)
        Errors  = @($errors)
        Summary = [pscustomobject]@{
            MailboxesAnalyzed = $Identities.Count
            TotalActions      = @($dedupedActions).Count
            RevokeThenGrant   = @($dedupedActions | Where-Object NeedsRevoke).Count
            GrantOnly         = @($dedupedActions | Where-Object { -not $_.NeedsRevoke }).Count
            ReadErrors        = @($errors).Count
        }
    }
}
