function Enable-M365OpsDistributionGroup {
    <#
    .SYNOPSIS
        NON FUNZIONA in Exchange Online - vedi .NOTES. Lasciata come funzione dedicata
        (invece di rimuoverla) solo per dare un errore chiaro e immediato invece di un
        "term not recognized" criptico, se qualcuno (umano o AI) la chiama comunque.
    .NOTES
        BUG STRUTTURALE trovato dal vivo il 21/08/2026 durante uno stress test mirato
        sull'intero codice preesistente ("mai dare per scontato che non esistano bug non
        ancora scoperti") - stessa classe di errore gia' vista per Receive-/SendConnector
        (sezione 6.4/17.15 della guida): Enable-DistributionGroup e' un cmdlet ESCLUSIVO di
        Exchange on-premises, mai esistito in Exchange Online, verificato su documentazione
        ufficiale Microsoft ("available only in on-premises Exchange") E confermato dal vivo
        (Get-Command restituisce nulla in una sessione Exchange Online reale). A differenza
        del caso Connector, qui NON esiste un equivalente diretto in Exchange Online da
        sostituire: "mail-enable" un gruppo esistente e' un concetto legato alla
        sincronizzazione con Active Directory on-premise (attributi schema AD), non
        un'operazione che l'API cloud espone in nessuna forma - un gruppo creato via
        New-M365OpsDistributionGroup/New-M365OpsMailSecurityGroup e' gia' mail-enabled fin
        dalla creazione, non serve mai abilitarlo dopo.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    throw "Enable-DistributionGroup non esiste in Exchange Online (cmdlet esclusivo di Exchange on-premises) - non c'e' un equivalente cloud: un gruppo creato in Exchange Online e' gia' mail-enabled fin dalla creazione. Se il gruppo '$Identity' e' sincronizzato da un Active Directory on-premise, questa operazione va fatta LA' (Enable-DistributionGroup sul server Exchange on-premise), non da qui."
}
