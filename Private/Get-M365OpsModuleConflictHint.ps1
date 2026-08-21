function Get-M365OpsModuleConflictHint {
    <#
    .SYNOPSIS
        Riconosce se un'eccezione e' il noto conflitto di assembly tra MicrosoftTeams e
        ExchangeOnlineManagement (sezione 6.6 della guida) e, se si', restituisce un messaggio
        chiaro con l'unico rimedio noto (riavviare il server). Restituisce $null per qualunque
        altro errore, cosi' i chiamanti possono farlo propagare inalterato.

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
    if ($RawMessage -notmatch 'Could not load file or assembly') { return $null }

    "Connessione a $ThisService fallita per un conflitto tra i moduli PowerShell: caricare $OtherService e $ThisService nello stesso processo server ha causato una versione incompatibile di una libreria di autenticazione condivisa (errore .NET originale: $RawMessage). E' un conflitto noto di Microsoft tra MicrosoftTeams e ExchangeOnlineManagement (non un bug di M365Ops, vedi guida sezione 6.6) - dipende dalle versioni esatte installate di entrambi i moduli, non e' prevedibile in anticipo ne' sempre presente. Riavvia il server (pulsante Manutenzione, o 'M365Ops - Termina e riavvia' sul Desktop se non risponde) per liberare il processo e riprova - $ThisService da solo, senza prima connettere $OtherService in questa sessione, funziona sempre."
}
