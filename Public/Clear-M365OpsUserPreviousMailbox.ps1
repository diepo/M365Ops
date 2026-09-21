function Clear-M365OpsUserPreviousMailbox {
    <#
    .SYNOPSIS
        Cancella DEFINITIVAMENTE la mailbox cloud gia' scollegata di un utente (dopo la rimozione
        della licenza) SENZA toccare l'account: l'utente resta in Entra ID/Exchange, con o senza
        altre licenze, senza piu' nessuna traccia della vecchia mailbox. IRREVERSIBILE.
    .DESCRIPTION
        Dopo aver rimosso la licenza Exchange a un utente, la sua mailbox non viene eliminata subito:
        resta 30 giorni in stato "soft-deleted" (recuperabile, vedi Get-M365OpsSoftDeletedMailboxes).
        Per anticipare la cancellazione definitiva SENZA eliminare l'utente NON si puo' usare
        Remove-Mailbox (elimina anche l'account): si usa
            Set-User -Identity <utente> -PermanentlyClearPreviousMailboxInfo
        che svuota sull'utente gli attributi della mailbox precedente (ExchangeGuid/ArchiveGuid...).
        Documentazione Microsoft, verificata il 21/09/2026: "This switch prevents you from
        reconnecting to the mailbox and prevents you from recovering content from the mailbox."
        Nessun altro modo di annullarlo.

        PROTEZIONI (tutte prima di toccare qualunque cosa - se una fallisce non si cancella nulla):
          1. -ConfirmPermanentDeletion OBBLIGATORIO: senza, l'operazione si rifiuta spiegando cosa
             andrebbe perso. Compare nella proposta mostrata all'utente, cosi' l'irreversibilita' e'
             visibile nel testo di conferma e non puo' scattare per un parametro dimenticato.
          2. L'utente deve ESISTERE (se l'account e' stato eliminato non e' questo il caso).
          3. NESSUNA mailbox ATTIVA: se l'utente ha ancora una mailbox utilizzabile (licenza ancora
             presente, o rimozione non ancora elaborata da Exchange) l'operazione si rifiuta - mai
             distruggere una mailbox in uso.
          4. Deve esistere una mailbox scollegata di QUESTO utente, causata dalla RIMOZIONE DELLA
             LICENZA (non dall'eliminazione dell'account).
          5. Nessuna hold: una mailbox con Litigation Hold/eDiscovery/retention hold o gia' "inattiva"
             e' conservata per motivi di conformita' e non va mai cancellata da qui.
    .PARAMETER Identity
        UPN dell'utente (es. mario.rossi@dominio.it).
    .PARAMETER ConfirmPermanentDeletion
        Riconoscimento esplicito che i dati (email, calendario, contatti, archivio) andranno persi
        per sempre.
    .OUTPUTS
        pscustomobject { UserPrincipalName; ClearedExchangeGuid; HadArchive; WhenSoftDeleted; StillListed }.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [switch]$ConfirmPermanentDeletion
    )

    if (-not $ConfirmPermanentDeletion) {
        throw "Operazione IRREVERSIBILE: cancella per sempre la mailbox cloud scollegata di '$Identity' (email, calendario, contatti, archivio) senza possibilita' di recupero, lasciando l'utente intatto. Per procedere serve il parametro -ConfirmPermanentDeletion. Prima verifica cosa c'e' con Get-M365OpsSoftDeletedMailboxes."
    }

    Connect-M365OpsExchange

    $user = Get-User -Identity $Identity -ErrorAction SilentlyContinue
    if (-not $user) {
        throw "Utente '$Identity' non trovato in Exchange Online - se l'account e' stato eliminato non e' il caso 'cancellare la mailbox senza toccare l'utente'."
    }
    $upn = $user.UserPrincipalName

    $active = Get-Mailbox -Identity $upn -ErrorAction SilentlyContinue
    if ($active) {
        throw "'$upn' ha ancora una mailbox ATTIVA ($($active.RecipientTypeDetails)): non e' stata scollegata. Rimuovi la licenza Exchange e attendi che Exchange la elabori (la mailbox deve comparire tra le eliminate, Get-M365OpsSoftDeletedMailboxes) - questa funzione non distrugge mai una mailbox in uso."
    }

    $soft = @(Get-Mailbox -SoftDeletedMailbox -Identity $upn -ErrorAction SilentlyContinue)
    if ($soft.Count -eq 0) {
        throw "Nessuna mailbox scollegata trovata per '$upn' - non c'e' nulla da cancellare (o la rimozione della licenza non e' ancora stata elaborata da Exchange: riprova piu' tardi, puo' richiedere del tempo)."
    }
    if ($soft.Count -gt 1) {
        throw "Trovate $($soft.Count) mailbox scollegate per '$upn' - caso anomalo, non procedo alla cieca. Controlla con Get-M365OpsSoftDeletedMailboxes -Identity '$upn'."
    }
    $mbx = $soft[0]

    if ($mbx.IsSoftDeletedByRemove -and -not $mbx.IsSoftDeletedByDisable) {
        throw "La mailbox di '$upn' e' stata eliminata insieme all'ACCOUNT (non per rimozione licenza): non e' il caso 'senza toccare l'utente'."
    }
    $holds = @($mbx.InPlaceHolds | Where-Object { $_ }).Count
    $why = @()
    if ($mbx.IsInactiveMailbox)        { $why += 'mailbox inattiva' }
    if ($mbx.LitigationHoldEnabled)    { $why += 'Litigation Hold' }
    if ($holds -gt 0)                  { $why += "$holds hold di retention/eDiscovery (es. una retention policy su tutte le mailbox)" }
    if ($mbx.ComplianceTagHoldApplied) { $why += 'ComplianceTagHold' }
    if ($mbx.DelayHoldApplied)         { $why += 'DelayHold' }
    if ($why.Count -gt 0) {
        throw "La mailbox di '$upn' e' PROTETTA da una hold di conformita' ($($why -join '; ')): e' conservata di proposito e non va cancellata da qui. Se vuoi davvero cancellarla, rimuovi prima la hold/escludi la mailbox dalla retention policy dal portale Purview (e la mailbox inattiva va gestita da Purview)."
    }

    $hadArchive = [bool]($mbx.ArchiveGuid -and $mbx.ArchiveGuid -ne [Guid]::Empty)
    Write-M365OpsLog "Cancellazione DEFINITIVA mailbox scollegata di '$upn' (ExchangeGuid $($mbx.ExchangeGuid), eliminata il $($mbx.WhenSoftDeleted), archivio: $hadArchive) - utente NON toccato."

    Set-User -Identity $upn -PermanentlyClearPreviousMailboxInfo -Confirm:$false -ErrorAction Stop

    $still = @(Get-Mailbox -SoftDeletedMailbox -Identity $upn -ErrorAction SilentlyContinue).Count -gt 0
    Write-Host "Mailbox scollegata di $upn cancellata definitivamente (utente intatto)." -ForegroundColor Green
    [pscustomobject]@{
        UserPrincipalName   = $upn
        ClearedExchangeGuid = $mbx.ExchangeGuid
        HadArchive          = $hadArchive
        WhenSoftDeleted     = $mbx.WhenSoftDeleted
        StillListed         = $still
    }
}
