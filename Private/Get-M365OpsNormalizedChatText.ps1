function Get-M365OpsNormalizedChatText {
    <#
    .SYNOPSIS
        Normalizza il testo di un messaggio chat (gia' in minuscolo) PRIMA del matching sul
        catalogo comandi (Gui\CommandCatalog.ps1), per assorbire il "rumore" meccanico piu'
        comune della scrittura veloce in italiano.

        Bug-hunt 19/08/2026: il messaggio "dispositivi mostrami quali sono kelli nn conformi"
        (typo "nn" per "non") non faceva scattare il trigger specifico di ListNonCompliant,
        cadendo sul catch-all generico di ListDevices - risposta con TUTTI i dispositivi invece
        dei soli non conformi, senza alcun segnale che il filtro fosse stato ignorato.

        NON e' un correttore ortografico: refusi/trasposizioni DENTRO una parola (es. "quta" per
        "questa", "diverdamnete" per "diversamente") restano fuori apposta - un dizionario di
        pattern non potrebbe mai coprire varianti illimitate senza diventare un pozzo senza
        fondo, e il motore AI le gestisce gia' benissimo da solo (verificato dal vivo nello
        stesso bug-hunt: routing corretto su piu' messaggi con parole storpiate/invertite). Qui
        si corregge solo cio' che e' meccanicamente riconoscibile e limitato: punteggiatura
        malformata e abbreviazioni SMS/chat cosi' diffuse da essere di fatto standard.
    .PARAMETER Text
        Testo gia' in minuscolo (Handle-ChatMessage lo normalizza prima di chiamare questa
        funzione) - qui non si tocca il casing, solo il rumore meccanico.
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)

    $t = $Text

    # Apostrofi doppi o ripetuti ("c''e''", "un''altra") -> singolo. Capita scrivendo veloce su
    # tastiera fisica quando il tasto apostrofo "rimbalza", o per abitudine da mobile.
    $t = $t -replace "['´`]{2,}", "'"

    # Abbreviazioni SMS/chat italiane piu' comuni rilevanti per capire l'intento di una
    # richiesta - solo parole INTERE (\b), mai sottostringhe, per non toccare parole vere che le
    # contengono per caso (es. "nn" non deve toccare "innovazione", "sn" non deve toccare
    # "assegna").
    $abbrev = [ordered]@{
        'nn'    = 'non'
        'sn'    = 'sono'
        'cmq'   = 'comunque'
        'qnd'   = 'quando'
        'qlk'   = 'qualche'
        'xché'  = 'perché'
        'xche'  = 'perché'
        'xchè'  = 'perché'
        'perche' = 'perché'
    }
    foreach ($k in $abbrev.Keys) {
        $t = $t -replace "\b$k\b", $abbrev[$k]
    }

    return $t
}
