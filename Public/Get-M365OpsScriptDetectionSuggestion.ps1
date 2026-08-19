function Get-M365OpsScriptDetectionSuggestion {
    <#
    .SYNOPSIS
        Legge il contenuto di uno script (ps1/bat/cmd) caricato per il packaging Win32 e chiede
        all'AI di dedurre una regola di detection plausibile (marker file o chiave di registro
        che lo script stesso scrive quando ha successo) - richiesto esplicitamente dall'utente
        il 19/08/2026 per evitare di chiedere sempre la detection all'operatore quando puo'
        essere dedotta dal codice.

        Usata come TENTATIVO, non come sostituto della richiesta all'utente: se l'AI non e'
        ragionevolmente sicura, il chiamante (Get-M365OpsScriptPackagePlan in Gui\Server.ps1)
        procede comunque a chiedere all'operatore, esattamente come prima di questa funzione.
        Una detection dedotta con sicurezza compare comunque nel testo di conferma della
        sequenza (mai applicata silenziosamente) con una nota che ne segnala la provenienza,
        stesso principio gia' usato per la detection dedotta dai metadati di un exe/msi.

        Diversa da Invoke-M365OpsWriteRecovery (quella corregge un corpo Graph gia' fallito
        leggendo l'errore restituito) - qui si analizza codice sorgente PRIMA di qualunque
        scrittura, per dedurre un side-effect osservabile, non per correggere un errore.
    .OUTPUTS
        pscustomobject con confident (bool) ed explanation (stringa, da mostrare comunque
        all'utente) - se confident=true, anche DetectionMode ('FileExists'|'RegistryExists') e
        i campi corrispondenti (DetectionPath/DetectionFile oppure
        DetectionRegistryKeyPath/DetectionRegistryValueName).
    #>
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude'
    )

    $scriptContent = Get-Content -Path $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $scriptContent) {
        return [pscustomobject]@{ confident = $false; explanation = "Impossibile leggere il contenuto dello script." }
    }
    # Limite dimensione per non sprecare token su script enormi/generati automaticamente -
    # uno script di installazione utile alla detection e' quasi sempre molto piu' corto di
    # questo, un troncamento qui e' un segnale che comunque non converrebbe fidarsi ciecamente.
    if ($scriptContent.Length -gt 20000) { $scriptContent = $scriptContent.Substring(0, 20000) + "`n... (troncato)" }

    $prompt = @"
Analizza questo script di installazione ($([IO.Path]::GetFileName($FilePath))), destinato a essere pacchettizzato come app Win32 Intune. Il tuo compito e' dedurre una regola di "detection" affidabile per Intune - un segnale osservabile SUL DISPOSITIVO che indichi che lo script ha completato l'installazione con successo, cosi' Intune puo' verificare se l'app risulta installata.

Cerca nello script un'operazione che crea/scrive qualcosa di stabile e verificabile in caso di successo: un file creato in un percorso fisso, una chiave/valore di registro scritto, o un file gia' presente per via dell'installazione stessa (es. un eseguibile copiato in una cartella nota, o un installer esterno lanciato con un percorso di destinazione esplicito nel comando). NON proporre un marker che lo script non scrive davvero - se non trovi un segnale chiaro e affidabile nel codice, dichiara di non essere sicuro invece di indovinare un percorso plausibile.

Contenuto dello script:
``````
$scriptContent
``````

Rispondi SOLO con un blocco JSON, nessun altro testo prima o dopo:
{
  "confident": true|false,
  "explanation": "spiegazione breve in italiano di cosa hai trovato (o perche' non sei sicuro), da mostrare all'utente",
  "detectionMode": "FileExists"|"RegistryExists"|null,
  "detectionPath": "percorso CARTELLA del file marker (senza il nome del file), solo se FileExists" ,
  "detectionFile": "nome del file marker, solo se FileExists",
  "detectionRegistryKeyPath": "percorso chiave, es. HKLM:\\SOFTWARE\\MiaApp, solo se RegistryExists",
  "detectionRegistryValueName": "nome valore, solo se RegistryExists"
}

Imposta "confident": false (gli altri campi possono restare vuoti) se lo script non scrive nulla di verificabile con certezza - e' sempre meglio chiedere all'utente che proporre un marker sbagliato (Intune riporterebbe falsi positivi/negativi di installazione su ogni dispositivo).
"@

    $raw = Invoke-M365OpsAgent -Prompt $prompt -MaxTokens 600 -Provider $Provider

    try {
        $jsonMatch = [regex]::Match($raw, '\{[\s\S]*\}')
        if (-not $jsonMatch.Success) { throw "Nessun JSON nella risposta." }
        $parsed = $jsonMatch.Value | ConvertFrom-Json
        $confident = [bool]$parsed.confident
        return [pscustomobject]@{
            confident                  = $confident
            explanation                = [string]$parsed.explanation
            DetectionMode              = if ($confident) { [string]$parsed.detectionMode } else { $null }
            DetectionPath              = if ($confident) { [string]$parsed.detectionPath } else { $null }
            DetectionFile              = if ($confident) { [string]$parsed.detectionFile } else { $null }
            DetectionRegistryKeyPath   = if ($confident) { [string]$parsed.detectionRegistryKeyPath } else { $null }
            DetectionRegistryValueName = if ($confident) { [string]$parsed.detectionRegistryValueName } else { $null }
        }
    }
    catch {
        return [pscustomobject]@{ confident = $false; explanation = "Non sono riuscito a interpretare la risposta dell'AI in formato strutturato." }
    }
}
