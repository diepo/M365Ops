function Disable-M365OpsDistributionGroup {
    <#
    .SYNOPSIS
        NON FUNZIONA in Exchange Online - vedi .NOTES. Lasciata come funzione dedicata
        (invece di rimuoverla) solo per dare un errore chiaro e immediato invece di un
        "term not recognized" criptico, se qualcuno (umano o AI) la chiama comunque. Per
        rimuovere davvero un gruppo (non solo disabilitare la posta) vedi
        Remove-M365OpsDistributionGroup, che funziona normalmente.
    .NOTES
        BUG STRUTTURALE trovato dal vivo il 21/08/2026 durante uno stress test mirato
        sull'intero codice preesistente - stessa classe di errore gia' vista per
        Receive-/SendConnector (sezione 6.4/17.15 della guida) e per
        Enable-M365OpsDistributionGroup sopra: Disable-DistributionGroup e' un cmdlet
        ESCLUSIVO di Exchange on-premises, mai esistito in Exchange Online, verificato su
        documentazione ufficiale Microsoft E confermato dal vivo (Get-Command restituisce
        nulla in una sessione Exchange Online reale). Nessun equivalente cloud diretto: in
        Exchange Online un gruppo o e' mail-enabled (Distribution Group) o non lo e' mai
        stato (Security Group puro) - non esiste un'operazione per "convertire" un gruppo
        esistente togliendogli la posta senza eliminarlo.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    throw "Disable-DistributionGroup non esiste in Exchange Online (cmdlet esclusivo di Exchange on-premises) - non c'e' un equivalente cloud per 'togliere la posta' a un gruppo esistente senza eliminarlo. Se vuoi eliminare del tutto il gruppo '$Identity' usa invece Remove-M365OpsDistributionGroup (irreversibile). Se il gruppo e' sincronizzato da un Active Directory on-premise, questa operazione va fatta LA', non da qui."
}
