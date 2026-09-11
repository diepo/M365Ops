function Get-M365OpsMailboxArchiveDetail {
    <#
    .SYNOPSIS
        Scorciatoia: dettagli REALI dell'archivio (Online Archive / In-Place Archive) di UNA
        mailbox in UNA sola chiamata - nome (ArchiveName), stato, GUID (da Get-Mailbox
        -Archive) E dimensione/numero di elementi/ultimo logon DELL'ARCHIVIO (da
        Get-MailboxStatistics -Archive), mai della mailbox primaria. Equivalente a chiamare
        Get-M365OpsMailboxDetail -Archive e Get-M365OpsMailboxStatistics -Archive
        separatamente e unire i risultati - usa quella coppia se ti serve solo UNO dei due
        tagli di dati, questa funzione se ti servono entrambi insieme.
    #>
    param([Parameter(Mandatory)][string]$Identity)
    Connect-M365OpsExchange
    # Bug reale segnalato dal vivo dall'utente il 11/09/2026: nessuna funzione dell'allowlist
    # exo_query esponeva mai i dati REALI dell'archivio (ArchiveName compreso) - l'unica
    # disponibile all'epoca, Get-M365OpsMailboxStatistics, chiamava Get-EXOMailboxStatistics
    # SENZA -Archive, quindi qualunque numero riportato "come archivio" era in realta' la
    # mailbox primaria, senza che nessun errore lo segnalasse. Non era una scelta sbagliata
    # dell'IA: lo strumento giusto non esisteva affatto in precedenza. Generalizzato subito
    # dopo lo stesso giorno (Get-M365OpsMailboxDetail + -Archive su
    # Get-M365OpsMailboxStatistics) - questa funzione resta come comoda scorciatoia
    # "entrambi i tagli in un colpo solo", non piu' l'unico modo di arrivarci.
    $mbx = Get-Mailbox -Identity $Identity -ErrorAction Stop
    if (-not $mbx.ArchiveStatus -or $mbx.ArchiveStatus -eq 'None') {
        return [pscustomobject]@{
            Identity       = $Identity
            ArchiveEnabled = $false
            ArchiveName    = $null
            ArchiveStatus  = $mbx.ArchiveStatus
            ArchiveGuid    = $null
            SizeGB         = $null
            ItemCount      = $null
            LastLogonTime  = $null
        }
    }
    $stats = Get-EXOMailboxStatistics -Identity $Identity -Archive -Properties TotalItemSize, ItemCount, LastLogonTime -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Identity       = $Identity
        ArchiveEnabled = $true
        # ArchiveName e' una MultiValuedProperty (Auto-Expanding Archive puo' aggiungere
        # archivi ausiliari oltre al principale) - unita in una stringa sola invece di un
        # array grezzo, cosi' resta leggibile sia per l'IA sia per un eventuale comando di
        # catalogo che la restituisce gia' come stringa pronta.
        ArchiveName    = if ($mbx.ArchiveName) { ($mbx.ArchiveName -join ', ') } else { $null }
        ArchiveStatus  = $mbx.ArchiveStatus
        ArchiveGuid    = $mbx.ArchiveGuid
        SizeGB         = if ($stats.TotalItemSize) { [math]::Round(($stats.TotalItemSize.Value.ToBytes() / 1GB), 2) } else { $null }
        ItemCount      = $stats.ItemCount
        LastLogonTime  = $stats.LastLogonTime
    }
}
