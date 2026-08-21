function Get-M365OpsModuleConflictHint {
    <#
    .SYNOPSIS
        Riconosce se un'eccezione e' il noto conflitto di assembly tra MicrosoftTeams e
        ExchangeOnlineManagement (sezione 6.6 della guida) e, se si', restituisce un messaggio
        chiaro con l'unico rimedio noto (riavviare il server). Restituisce $null per qualunque
        altro errore, cosi' i chiamanti possono farlo propagare inalterato.

        Due pattern riconosciuti (25/08/2026, il secondo aggiunto dopo un caso reale segnalato
        dal vivo: connesso Teams, poi Exchange fallito con "The given assembly name was invalid."
        - stessa famiglia di conflitto della prima variante ("Could not load file or assembly"),
        solo un messaggio .NET diverso: entrambi sono errori generati durante il caricamento di
        un assembly gia' presente nel processo in una versione diversa - .NET sceglie quale delle
        due frasi mostrare in base a QUALE punto del caricamento fallisce, non e' un problema
        diverso.

        Sostituisce (24/08/2026) la guardia PREVENTIVA usata in precedenza ("l'altro modulo e'
        gia' caricato, blocco a priori"): una matrice di test dal vivo ha dimostrato che NESSUN
        ordine di connessione e' affidabilmente sicuro o rotto in modo prevedibile - dipende da
        quali versioni esatte dei due moduli sono installate, cosa che varia da PC a PC (l'utente
        stesso ricorda un'asimmetria opposta sulla propria macchina rispetto a quella riprodotta
        qui). Bloccare a priori un tentativo che magari sarebbe riuscito e' quindi peggio che
        lasciarlo provare e mostrare un errore chiaro SOLO se e quando fallisce davvero -
        richiesto esplicitamente dall'utente dopo aver visto la guardia preventiva ripristinata:
        "non voglio il safe guard, nelle versioni vecchie funzionava".
    #>
    param(
        [Parameter(Mandatory)] [string]$RawMessage,
        [Parameter(Mandatory)] [string]$ThisService,
        [Parameter(Mandatory)] [string]$OtherService
    )
    # Non ri-rivestire un messaggio gia' composto da Invoke-M365OpsWithExoRepairRetry (25/08/2026,
    # bug reale trovato dal vivo): quella funzione include il messaggio .NET grezzo dentro la
    # propria narrazione, quindi contiene ANCH'ESSA "Could not load file or assembly"/"The given
    # assembly name was invalid" come sottostringa - senza questo controllo, il catch esterno
    # nei chiamanti la intercettava di nuovo e la sostituiva con il messaggio generico del
    # conflitto Teams, nascondendo la diagnosi piu' precisa (installazione danneggiata, non
    # conflitto) gia' fatta a monte. Frase-sentinella scelta perche' compare SOLO li'.
    if ($RawMessage -match "installazione locale del modulo ExchangeOnlineManagement") { return $null }
    if ($RawMessage -notmatch 'Could not load file or assembly' -and $RawMessage -notmatch 'The given assembly name was invalid') { return $null }

    "Connessione a $ThisService fallita per un conflitto tra i moduli PowerShell: caricare $OtherService e $ThisService nello stesso processo server ha causato una versione incompatibile di una libreria di autenticazione condivisa (errore .NET originale: $RawMessage). E' un conflitto noto di Microsoft tra MicrosoftTeams e ExchangeOnlineManagement (non un bug di M365Ops, vedi guida sezione 6.6) - dipende dalle versioni esatte installate di entrambi i moduli, non e' prevedibile in anticipo ne' sempre presente. Riavvia il server (pulsante Manutenzione, o 'M365Ops - Termina e riavvia' sul Desktop se non risponde) per liberare il processo e riprova - $ThisService da solo, senza prima connettere $OtherService in questa sessione, funziona sempre."
}
