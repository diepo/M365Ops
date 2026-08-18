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

    $prompt = @"
Una scrittura Microsoft Graph proposta da un tool di amministrazione Microsoft 365, gia'
confermata esplicitamente dall'utente, e' stata eseguita ed e' FALLITA. L'errore restituito da
Graph descrive di solito con precisione cosa manca o e' invalido - il tuo compito e' costruire
un corpo della richiesta corretto, non indovinare cause non menzionate dall'errore.

Metodo e percorso: $Method $Path
Motivo originale della scrittura: $(if ($Reason) { $Reason } else { "(non specificato)" })
Corpo originale inviato:
$bodyJson

Errore restituito da Microsoft Graph:
$ErrorMessage

Se l'errore indica chiaramente cosa manca o e' invalido (es. "a password must be specified",
un campo obbligatorio mancante, un formato non valido), costruisci il corpo COMPLETO corretto
(non solo il campo aggiunto - l'intero oggetto body valido). Per una password mancante in una
creazione utente, genera una password temporanea CASUALE e sufficientemente complessa (non
"Password123", non un valore prevedibile) e imposta forceChangePasswordNextSignIn=true, cosi'
l'utente la cambia al primo accesso - e' il default corretto quando l'utente ha detto di
lasciare tutto a default, non un'invenzione arbitraria.

Rispondi SOLO con un blocco JSON, nessun altro testo prima o dopo, in questo formato esatto:
{
  "canFix": true|false,
  "explanation": "spiegazione breve e onesta in italiano di cosa correggi e perche', da mostrare all'utente PRIMA che confermi di nuovo",
  "correctedBody": { <corpo completo corretto, stessa struttura dell'originale> }
}

Imposta "canFix": false (e correctedBody: null) se l'errore non indica chiaramente come
correggere la richiesta, o se la correzione richiederebbe informazioni che solo l'utente puo'
fornire (es. scegliere quale di due gruppi con lo stesso nome) - non inventare un valore
plausibile ma incerto solo per riempire il campo.
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
