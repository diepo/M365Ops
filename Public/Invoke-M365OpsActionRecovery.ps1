function Invoke-M365OpsActionRecovery {
    <#
    .SYNOPSIS
        Quando un'azione costruita da testo libero con estrazione a regex (non AI) fallisce
        in esecuzione, prova a chiedere all'AI di rileggere il messaggio originale dell'utente
        e proporre parametri corretti - pensato per errori di ESTRAZIONE testuale (es. un'email
        con un carattere di troppo/mancante preso per errore dal regex), non per bug di codice
        (quelli restano gestiti da Invoke-M365OpsErrorTriage). Il chiamante (Execute-PendingAction
        in Server.ps1) e' responsabile di annunciare il tentativo all'utente e di fare
        l'eventuale retry - questa funzione SOLO diagnostica e propone, non esegue nulla e non
        modifica lo stato del tenant.
    .OUTPUTS
        pscustomobject con canFix (bool), explanation (stringa) e correctedParameters (oggetto
        con gli stessi campi di -Parameters, valori corretti) - o canFix=$false se l'AI non e'
        ragionevolmente sicura di aver capito l'intento reale dell'utente.
    #>
    param(
        [Parameter(Mandatory)] [string]$ActionType,
        [Parameter(Mandatory)] [hashtable]$Parameters,
        [Parameter(Mandatory)] [string]$ErrorMessage,
        [Parameter(Mandatory)] [string]$OriginalMessage,
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude'
    )

    $paramsJson = ($Parameters | ConvertTo-Json -Compress -Depth 4)

    $prompt = @"
Un'azione '$ActionType' in un tool di amministrazione Microsoft 365 e' stata costruita
automaticamente da testo libero (estrazione con regex, NON dall'AI) a partire dal messaggio
originale di un utente, ed e' fallita in esecuzione.

Messaggio originale dell'utente:
$OriginalMessage

Parametri attualmente usati (probabilmente mal estratti dal messaggio per un limite del
regex, non perche' l'utente li abbia scritti cosi'):
$paramsJson

Errore ottenuto eseguendo l'azione con questi parametri:
$ErrorMessage

Rileggi il messaggio originale e prova a capire quali fossero i valori REALMENTE intesi
dall'utente per ciascun campo (es. un nome con un refuso, un'email con un carattere di
troppo o mancante per un errore di estrazione testuale - non una vera scelta dell'utente).
Rispondi SOLO con un blocco JSON, nessun altro testo prima o dopo, in questo formato esatto:
{
  "canFix": true|false,
  "explanation": "spiegazione breve e onesta in italiano di cosa correggi e perche', da mostrare all'utente",
  "correctedParameters": { <stessi campi dei Parametri sopra, con i valori corretti> }
}

Imposta "canFix": false (e correctedParameters: null) se non sei ragionevolmente sicuro
dell'intento reale dell'utente per almeno un campo - non inventare un valore plausibile ma
incerto solo per riempire il campo.
"@

    $raw = Invoke-M365OpsAgent -Prompt $prompt -MaxTokens 800 -Provider $Provider

    try {
        $jsonMatch = [regex]::Match($raw, '\{[\s\S]*\}')
        if (-not $jsonMatch.Success) { throw "Nessun JSON nella risposta." }
        return ($jsonMatch.Value | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            canFix              = $false
            explanation         = "Non sono riuscito a interpretare la risposta dell'AI in formato strutturato."
            correctedParameters = $null
        }
    }
}
