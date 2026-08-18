function Invoke-M365OpsErrorTriage {
    <#
    .SYNOPSIS
        Diagnosi e proposta di auto-correzione per un'azione fallita davvero (dopo eventuali
        retry interni gia' previsti dalle singole cmdlet) - non usata ad ogni chiamata, solo
        sui fallimenti reali, per non sprecare la API key su cose che non ne hanno bisogno.
        Usata sia da Server.ps1 (scritture confermate: CreateGroup, ExoWrite, CustomWrite...)
        sia da Invoke-M365OpsAgentTools (script personalizzati in sola lettura che falliscono).
    .NOTES
        Regole di sicurezza applicate a valle da Test-M365OpsFixApplicable/Invoke-M365OpsApplyFix:
        il fix si applica solo se il testo da sostituire compare ESATTAMENTE UNA VOLTA nel file
        target, sempre con backup automatico, e solo dentro la cartella del modulo - mai path
        arbitrari, mai senza conferma esplicita dell'utente in chat.
    #>
    param(
        [Parameter(Mandatory)] [string]$ErrorMessage,
        [string]$Context,
        [string]$SourceFile,
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude'
    )

    $sourceSnippet = ""
    $docsSnippet = ""
    if ($SourceFile -and (Test-Path $SourceFile)) {
        $sourceContent = Get-Content $SourceFile -Raw
        $sourceSnippet = "`n`nContenuto attuale del file sospetto ($(Split-Path -Leaf $SourceFile)):`n" + $sourceContent

        # Principio permanente: mai correggere/riscrivere a memoria una chiamata a una cmdlet
        # Exchange/Graph nativa - si consulta sempre la documentazione reale e aggiornata di
        # Microsoft Learn prima di proporre un fix, cosi' la correzione usa parametri/sintassi
        # verificati invece che plausibili-ma-forse-sbagliati o superati.
        $nativeCmdlets = [regex]::Matches($sourceContent, '\b(Get|Set|New|Remove|Add|Enable|Disable|Start|Stop|Complete|Connect|Disconnect|Grant|Revoke|Import|Export|Test)-(?!M365Ops)[A-Z][A-Za-z0-9]+\b') |
            ForEach-Object { $_.Value } | Select-Object -Unique | Select-Object -First 3
        if ($nativeCmdlets) {
            $docsParts = foreach ($cmd in $nativeCmdlets) {
                try { "--- $cmd ---`n$(Invoke-M365OpsLookupMsDocs -Topic $cmd)" } catch { "--- $cmd --- (lookup fallito: $($_.Exception.Message))" }
            }
            $docsSnippet = "`n`nDocumentazione Microsoft Learn REALE per le cmdlet native usate nel file (usala come fonte di verita' per parametri/sintassi, non la tua conoscenza pregressa):`n" + ($docsParts -join "`n`n")
        }
    }

    $prompt = @"
Un'azione in un modulo PowerShell che gestisce Intune/Microsoft Graph/Exchange Online e' fallita con questo errore:

$ErrorMessage

Contesto: $Context
$sourceSnippet
$docsSnippet

Analizza l'errore e rispondi SOLO con un blocco JSON, nessun altro testo prima o dopo, in questo formato esatto:
{
  "classification": "transient" | "input" | "bug",
  "explanation": "spiegazione breve, onesta, in italiano di cosa e' successo",
  "fix": {
    "file": "nome file relativo tipo Public/New-M365OpsGroup.ps1 o Scripts/Custom/NomeScript.ps1, oppure null se non applicabile",
    "search": "il blocco di testo ESATTO da cercare nel file (deve comparire una sola volta), oppure null",
    "replace": "il testo con cui sostituirlo, oppure null"
  }
}

"transient" = probabilmente basta riprovare (es. problemi di rete, eventual consistency).
"input" = serve una decisione o un dato da parte dell'utente, non un fix di codice.
"bug" = difetto nel codice. Se non hai abbastanza informazioni per essere sicuro della
correzione esatta, imposta comunque classification a "bug" ma lascia fix.file a null e
spiega nella explanation cosa andrebbe verificato manualmente - non inventare una
correzione se non sei ragionevolmente sicuro che sia corretta.

Se il file sospetto e' dentro Scripts/Custom (uno script "home made" aggiunto dall'operatore,
non una cmdlet del modulo core): questo modulo gestisce due modalita' di autenticazione per
tenant, AppOnly (client credentials) e Delegated (login utente + MFA) - lo script NON deve MAI
gestire token o credenziali proprie ne' assumere quale modalita' e' attiva. Se proponi una
correzione, usa sempre le funzioni gia' esistenti del modulo per l'accesso dati (es.
Invoke-M365OpsGraphRequest per Graph, Connect-M365OpsExchange + le cmdlet Exchange native per
Exchange Online) cosi' lo script resta valido sotto entrambe le modalita', esattamente come le
cmdlet del modulo core.
"@

    $raw = Invoke-M365OpsAgent -Prompt $prompt -MaxTokens 1500 -Provider $Provider

    try {
        $jsonMatch = [regex]::Match($raw, '\{[\s\S]*\}')
        if (-not $jsonMatch.Success) { throw "Nessun JSON nella risposta." }
        return ($jsonMatch.Value | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            classification = "unknown"
            explanation    = "Non sono riuscito a interpretare la risposta dell'AI in formato strutturato. Risposta grezza: $raw"
            fix            = $null
        }
    }
}
