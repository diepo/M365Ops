function Get-M365OpsMailboxDetail {
    <#
    .SYNOPSIS
        Restituisce TUTTE le proprieta' di Get-Mailbox per UNA mailbox (l'oggetto completo,
        non un sottoinsieme curato a mano) - lo strumento GENERALE da usare per qualunque
        campo specifico non gia' coperto da una funzione piu' mirata di questo modulo (es.
        ArchiveName/ArchiveStatus/ArchiveGuid, ProhibitSendQuota, WhenMailboxCreated,
        EmailAddresses, RecipientTypeDetails, LitigationHoldEnabled, RetentionPolicy, ecc.),
        invece di continuare a chiedere una nuova funzione dedicata per ogni singolo campo.
    .PARAMETER Archive
        Se presente, restituisce l'oggetto ARCHIVIO (Get-Mailbox -Archive) invece della
        mailbox primaria - stessa distinzione di Get-M365OpsMailboxStatistics -Archive, ma
        qui per le proprieta' di IDENTITA'/CONFIGURAZIONE (nome, stato, quota...), non per
        dimensione/numero elementi/ultimo logon (quelle vengono SOLO da
        Get-MailboxStatistics, Get-Mailbox non le ha mai avute, con o senza -Archive).
    #>
    param(
        [Parameter(Mandatory)][string]$Identity,
        [switch]$Archive
    )
    Connect-M365OpsExchange
    # Aggiunta l'11/09/2026 su richiesta esplicita dell'utente, dopo aver dovuto costruire
    # Get-M365OpsMailboxArchiveDetail per UN campo mancante (ArchiveName): "stiamo inseguendo
    # il dettaglio ogni volta... l'IA avrebbe dovuto partire da Get-Mailbox | fl" - richiesta
    # corretta, un tool generale sull'oggetto Get-Mailbox completo evita di dover aggiungere
    # una funzione nuova ogni volta che serve un campo non ancora coperto. Restituisce
    # l'oggetto COSI' COM'E' (nessuna proiezione/Select-Object): tutte le proprieta' native
    # di Get-Mailbox restano disponibili all'IA, che sceglie da sola quale usare.
    if (-not $Archive) {
        return Get-Mailbox -Identity $Identity -ErrorAction Stop
    }
    # Bug reale trovato dal vivo l'11/09/2026, STESSO giorno: Get-Mailbox -Archive lancia
    # SEMPRE "couldn't be found" quando la mailbox PRIMARIA esiste ma non ha nessun archivio
    # abilitato - un messaggio fuorviante che sembra dire che la mailbox stessa non esiste
    # (verificato dal vivo isolando la chiamata: la mailbox era presente e funzionante, solo
    # priva di archivio). Distingue qui i due casi PRIMA di lasciar propagare l'errore
    # originale, cosi' l'IA (e l'utente) non confondono "nessun archivio" con "mailbox
    # inesistente" - stesso principio di Get-M365OpsMailboxArchiveDetail (non fidarsi di un
    # segnale fuorviante quando ne esiste uno piu' diretto e verificabile).
    try {
        Get-Mailbox -Identity $Identity -Archive -ErrorAction Stop
    } catch {
        $primary = Get-Mailbox -Identity $Identity -ErrorAction SilentlyContinue
        if ($primary -and (-not $primary.ArchiveGuid -or $primary.ArchiveGuid -eq [Guid]::Empty)) {
            throw "La mailbox '$Identity' esiste ma NON ha nessun archivio abilitato - richiedere l'oggetto archivio (Get-Mailbox -Archive) fallisce sempre in questo caso con un errore Exchange fuorviante ('couldn't be found', che sembra riferirsi alla mailbox stessa, non e' cosi'). Nessun dato di archivio da mostrare per questa mailbox."
        }
        throw
    }
}
