function Get-M365OpsSoftDeletedMailboxes {
    <#
    .SYNOPSIS
        Elenca le mailbox "eliminate ma ancora recuperabili" (soft-deleted) - quelle che restano per 30
        giorni dopo la RIMOZIONE DELLA LICENZA di un utente (o dopo l'eliminazione dell'account) e che
        Get-Mailbox normale NON mostra piu'. Sola lettura, nessuna modifica.
    .DESCRIPTION
        E' il passo che precede Clear-M365OpsUserPreviousMailbox (cancellazione definitiva senza
        toccare l'utente): permette di vedere QUALI mailbox sono in attesa, da quando, se hanno
        archivio, e soprattutto se sono protette da una hold (mai cancellabili da li').
        Causa dell'eliminazione, dal campo nativo di Exchange:
          - LicenzaRimossa  (IsSoftDeletedByDisable): l'utente ESISTE ancora, e' scollegata la sola
            mailbox - e' il caso che Clear-M365OpsUserPreviousMailbox sa cancellare.
          - UtenteEliminato (IsSoftDeletedByRemove): e' stato eliminato l'intero account - non e' il
            caso "senza toccare l'utente".
    .PARAMETER Identity
        Opzionale: UPN/alias/GUID di una mailbox specifica. Vuoto = tutte quelle eliminate del tenant.
    #>
    param([string]$Identity)

    Connect-M365OpsExchange
    $items = if ($Identity) {
        @(Get-Mailbox -SoftDeletedMailbox -Identity $Identity -ErrorAction Stop)
    } else {
        @(Get-Mailbox -SoftDeletedMailbox -ResultSize Unlimited -ErrorAction Stop)
    }

    $items | ForEach-Object {
        $cause = if ($_.IsSoftDeletedByDisable) { 'LicenzaRimossa' } elseif ($_.IsSoftDeletedByRemove) { 'UtenteEliminato' } else { 'Altro' }
        $holds = @($_.InPlaceHolds | Where-Object { $_ }).Count
        $reasons = @()
        if ($_.IsInactiveMailbox)          { $reasons += 'MailboxInattiva' }
        if ($_.LitigationHoldEnabled)      { $reasons += 'LitigationHold' }
        if ($holds -gt 0)                  { $reasons += "HoldRetentionEDiscovery($holds)" }
        if ($_.ComplianceTagHoldApplied)   { $reasons += 'ComplianceTagHold' }
        if ($_.DelayHoldApplied)           { $reasons += 'DelayHold' }
        $protected = $reasons.Count -gt 0
        [pscustomobject]@{
            DisplayName       = $_.DisplayName
            UserPrincipalName = $_.UserPrincipalName
            ExchangeGuid      = $_.ExchangeGuid
            WhenSoftDeleted   = $_.WhenSoftDeleted
            # I 30 giorni valgono solo per una mailbox NON protetta: una mailbox inattiva/con hold resta
            # finche' dura la hold, un conto alla rovescia sarebbe un numero senza senso (anche negativo).
            GiorniRimasti     = if ($_.WhenSoftDeleted -and -not $protected) { [int](30 - ((Get-Date) - $_.WhenSoftDeleted).TotalDays) } else { $null }
            Causa             = $cause
            HaArchivio        = [bool]($_.ArchiveGuid -and $_.ArchiveGuid -ne [Guid]::Empty)
            ProtettaDaHold    = $protected
            MotivoProtezione  = ($reasons -join ', ')
        }
    }
}
