function Invoke-M365OpsWriteRecovery {
    <#
    .SYNOPSIS
        Quando una scrittura Microsoft Graph gia' confermata fallisce (es. Graph risponde con
        un messaggio chiaro tipo "A password must be specified to create a new user"), chiede
        all'AI di leggere l'errore e proporre un corpo della richiesta corretto - invece di
        limitarsi a mostrare l'errore grezzo all'utente (18/08/2026, richiesta esplicita
        dell'utente dopo aver visto un 400 su una creazione utente senza password).

        Diverso da Invoke-M365OpsActionRecovery (quello e' per correggere un'estrazione a
        regex sbagliata dal testo libero dell'utente, rileggendo il messaggio originale) e da
        Invoke-M365OpsErrorTriage (quello diagnostica un bug di CODICE in uno script, non un
        campo mancante in una richiesta Graph). Qui l'errore stesso, restituito da Graph, e'
        gia' la fonte di verita' su cosa manchi o sia sbagliato - non serve rileggere nulla,
        serve solo costruire un corpo valido.

    .OUTPUTS
        pscustomobject con canFix (bool), explanation (stringa, da mostrare all'utente) e
        correctedBody (hashtable, il corpo COMPLETO corretto - non solo la differenza) - oppure
        canFix=$false se l'AI non e' ragionevolmente sicura della correzione. NON esegue mai
        nulla: il chiamante (Execute-PendingAction in Server.ps1) e' responsabile di mostrare
        la nuova proposta e ottenere una conferma esplicita separata prima di riprovare - una
        scrittura corretta automaticamente resta comunque una scrittura, mai eseguita senza
        che l'utente veda cosa sta per succedere.
    #>
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        [object]$Body,
        [Parameter(Mandatory)] [string]$ErrorMessage,
        [string]$Reason,
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude'
    )

    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Compress -Depth 8 } else { "(nessuno)" }

    # BUG STRUTTURALE trovato dal vivo il 19/08/2026, segnalato dall'utente in modo esplicito:
    # "il comando sintatticamente errato deve essere corretto o proposta una correzione da
    # implementare, non un errore bloccante - e' il punto fondante di questa app". Prova reale:
    # una regola di un Assignment Filter Intune rifiutata da Graph con "Invalid assignment
    # filter rule" - l'errore diceva CHE la regola era invalida ma non COME correggerla (a
    # differenza di "a password must be specified", auto-esplicativo). Questa funzione, PRIMA
    # di questo fix, ragionava SOLO sul testo dell'errore stesso, senza alcun modo di consultare
    # la documentazione reale quando l'errore non si auto-spiega - risultato osservato dal vivo:
    # "canFix: false, l'errore non specifica quale sintassi... usare al suo posto", un vicolo
    # cieco anche quando la correzione ESISTE ed E' documentata (verificato: la proprieta'
    # 'osVersion' non supporta -ge, serve 'operatingSystemVersion' - pagina Microsoft Learn
    # reale, mai consultata perche' nessun meccanismo di ricerca esisteva qui). Stesso fix gia'
    # applicato a Invoke-M365OpsErrorTriage (diagnosi POST-fallimento) - qui e' il punto piu'
    # importante perche' e' quello che propone il RETRY IMMEDIATO con parametri corretti,
    # non solo una diagnosi testuale.
    $docsSnippet = ""
    try {
        $searchTopic = (Invoke-M365OpsAgent -Provider $Provider -MaxTokens 60 -Prompt @"
Questa scrittura Microsoft Graph e' fallita:
Metodo e percorso: $Method $Path
Errore restituito da Graph:
$ErrorMessage

Rispondi SOLO con il termine di ricerca (poche parole, in inglese) da cercare su Microsoft Learn
per trovare la pagina di documentazione che spiega la sintassi/le proprieta'/i valori corretti
per risolvere QUESTO errore specifico - nessun altro testo, nessuna spiegazione, nessuna
virgolettatura.
"@).Trim()
        if ($searchTopic -and $searchTopic.Length -lt 200) {
            $docsSnippet = "`n`nDocumentazione Microsoft Learn REALE trovata per questo errore (usala come fonte di verita' per costruire il corpo corretto, non la tua conoscenza pregressa - se conferma una sintassi/proprieta'/operatore specifico, usalo):`n--- $searchTopic ---`n$(Invoke-M365OpsLookupMsDocs -Topic $searchTopic)"
        }
    } catch { }

    # Knowledge Base del progetto (20/08/2026, richiesto esplicitamente dall'utente), stesso
    # principio gia' applicato a Invoke-M365OpsErrorTriage: per un errore specifico di setup/
    # configurazione di QUESTA app (es. il limite RBAC app-only documentato in sezione 6.4 della
    # guida) la KB globale/tenant e' una fonte piu' precisa di Microsoft Learn generico. Match
    # per parola chiave semplice, nessuna chiamata AI aggiuntiva.
    $kbSnippet = ""
    try {
        $kbCombined = @(Get-M365OpsKnowledgeCatalog -TenantName $script:M365OpsGlobalKbName)
        if ($script:M365OpsContext -and $script:M365OpsContext.Name) {
            $kbCombined += @(Get-M365OpsKnowledgeCatalog -TenantName $script:M365OpsContext.Name)
        }
        $haystack = "$ErrorMessage $Path $Reason".ToLower()
        $kbMatch = $kbCombined | Where-Object {
            $words = @($_.Topics) + @(($_.Title -split '\s+'))
            $words | Where-Object { $_ -and $_.Length -gt 3 -and $haystack.Contains($_.ToLower()) } | Select-Object -First 1
        } | Select-Object -First 1
        if ($kbMatch) {
            # -ErrorAction non media un throw esplicito - serve un try/catch vero.
            $kbText = $null
            try { $kbText = Get-M365OpsKnowledgeDocumentText -TenantName $script:M365OpsGlobalKbName -FileName $kbMatch.FileName } catch { }
            if (-not $kbText -and $script:M365OpsContext -and $script:M365OpsContext.Name) {
                try { $kbText = Get-M365OpsKnowledgeDocumentText -TenantName $script:M365OpsContext.Name -FileName $kbMatch.FileName } catch { }
            }
            if ($kbText) {
                $kbSnippet = "`n`nDocumentazione INTERNA di questo progetto trovata per questo errore (`"$($kbMatch.Title)`" - se rilevante, e' una fonte piu' precisa di Microsoft Learn per problemi di setup/configurazione specifici di questa app):`n$kbText"
            }
        }
    } catch { }

    $prompt = @"
Una scrittura Microsoft Graph proposta da un tool di amministrazione Microsoft 365, gia'
confermata esplicitamente dall'utente, e' stata eseguita ed e' FALLITA. L'errore restituito da
Graph descrive spesso con precisione cosa manca o e' invalido - ma non sempre (es. "invalid
rule" senza dire quale sintassi usare al suo posto): in quel caso usa la documentazione
Microsoft Learn fornita sotto, se presente, invece di limitarti al solo testo dell'errore.

Metodo e percorso: $Method $Path
Motivo originale della scrittura: $(if ($Reason) { $Reason } else { "(non specificato)" })
Corpo originale inviato:
$bodyJson

Errore restituito da Microsoft Graph:
$ErrorMessage
$kbSnippet
$docsSnippet

Se l'errore indica chiaramente cosa manca o e' invalido (es. "a password must be specified",
un campo obbligatorio mancante, un formato non valido), OPPURE se la documentazione Microsoft
Learn fornita sopra chiarisce la sintassi/proprieta'/operatore corretto per questo caso,
costruisci il corpo COMPLETO corretto (non solo il campo aggiunto - l'intero oggetto body
valido). Per una password mancante in una creazione utente, genera una password temporanea
CASUALE e sufficientemente complessa (non "Password123", non un valore prevedibile) e imposta
forceChangePasswordNextSignIn=true, cosi' l'utente la cambia al primo accesso - e' il default
corretto quando l'utente ha detto di lasciare tutto a default, non un'invenzione arbitraria.

BUG REALE trovato dal vivo il 19/08/2026 durante uno stress test mirato, IMPORTANTE: correggi
SOLO cio' che QUESTO errore sta segnalando, anche se altre parti del corpo restano di
correttezza incerta e non menzionate da questo errore. Esempio reale osservato: un errore
Graph "Error converting value to type System.String[], path groupTypes" indica chiaramente
che va corretto SOLO quel campo (da stringa ad array) - un dubbio non correlato su un ALTRO
campo del corpo (es. se l'operatore di un'altra proprieta' della regola sia quello giusto) NON
e' un motivo valido per rifiutare la correzione di QUESTO errore specifico: quel dubbio, se
fondato, produrra' un errore SUCCESSIVO al prossimo tentativo (questa funzione viene richiamata
di nuovo automaticamente ad ogni fallimento, non e' un unico tentativo) - a quel punto lo si
affrontera' con lo stesso procedimento. Rifiutare di correggere un problema chiaro solo perche'
resta un'incertezza su un problema DIVERSO e non ancora manifestato lascia l'utente bloccato
su un errore che sai gia' come risolvere.

Rispondi SOLO con un blocco JSON, nessun altro testo prima o dopo, in questo formato esatto:
{
  "canFix": true|false,
  "explanation": "spiegazione breve e onesta in italiano di cosa correggi e perche', da mostrare all'utente PRIMA che confermi di nuovo",
  "correctedBody": { <corpo completo corretto, stessa struttura dell'originale> }
}

Imposta "canFix": false (e correctedBody: null) SOLO se ne' l'errore ne' la documentazione
fornita indicano come correggere il problema che QUESTO errore descrive, o se la correzione
richiederebbe informazioni che solo l'utente puo' fornire (es. scegliere quale di due gruppi
con lo stesso nome) - non inventare un valore plausibile ma incerto solo per riempire il campo
che l'errore descrive. Non bloccare pero' una correzione chiara per un dubbio su un campo
diverso che questo errore non sta segnalando.
"@

    $raw = Invoke-M365OpsAgent -Prompt $prompt -MaxTokens 800 -Provider $Provider

    try {
        $jsonMatch = [regex]::Match($raw, '\{[\s\S]*\}')
        if (-not $jsonMatch.Success) { throw "Nessun JSON nella risposta." }
        $parsed = $jsonMatch.Value | ConvertFrom-Json
        return [pscustomobject]@{
            canFix        = [bool]$parsed.canFix
            explanation   = [string]$parsed.explanation
            correctedBody = if ($parsed.canFix) { ConvertTo-M365OpsHashtable $parsed.correctedBody } else { $null }
        }
    }
    catch {
        return [pscustomobject]@{
            canFix        = $false
            explanation   = "Non sono riuscito a interpretare la risposta dell'AI in formato strutturato."
            correctedBody = $null
        }
    }
}
