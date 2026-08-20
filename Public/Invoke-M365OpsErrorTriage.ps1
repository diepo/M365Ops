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

    # Knowledge Base del progetto (20/08/2026, richiesto esplicitamente dall'utente): oltre a
    # Microsoft Learn (generico), consulta anche la KB globale (guida di configurazione
    # dell'app) e quella del tenant attivo - per un errore specifico di QUESTO progetto (es. il
    # limite RBAC app-only su Receive/SendConnector/Accepted Domain, documentato in sezione 6.4
    # della guida) sono una fonte piu' precisa di qualunque documentazione Microsoft generica.
    # Match per parola chiave semplice (nessuna chiamata AI aggiuntiva: i cataloghi sono piccoli,
    # non serve altro) - se un Topic o una parola del Title del documento compare nell'errore/
    # contesto, il documento e' probabilmente rilevante. Antepone la KB a Microsoft Learn nel
    # prompt finale (vedi sotto): per problemi di setup/configurazione di QUESTO progetto e'
    # una fonte piu' affidabile, non sostituisce pero' l'uso di Microsoft Learn per la sintassi
    # di una cmdlet/API nativa.
    $kbSnippet = ""
    try {
        $kbCombined = @(Get-M365OpsKnowledgeCatalog -TenantName $script:M365OpsGlobalKbName)
        if ($script:M365OpsContext -and $script:M365OpsContext.Name) {
            $kbCombined += @(Get-M365OpsKnowledgeCatalog -TenantName $script:M365OpsContext.Name)
        }
        $haystack = "$ErrorMessage $Context".ToLower()
        $kbMatch = $kbCombined | Where-Object {
            $words = @($_.Topics) + @(($_.Title -split '\s+'))
            $words | Where-Object { $_ -and $_.Length -gt 3 -and $haystack.Contains($_.ToLower()) } | Select-Object -First 1
        } | Select-Object -First 1
        if ($kbMatch) {
            # -ErrorAction SilentlyContinue qui non basterebbe: Get-M365OpsKnowledgeDocumentText
            # usa "throw", non Write-Error, e -ErrorAction non media mai un throw esplicito -
            # serve un try/catch vero (stesso principio gia' applicato nel dispatch di kb_query
            # in Invoke-M365OpsAgentTools.ps1).
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

    if (-not $docsSnippet) {
        # BUG STRUTTURALE trovato dal vivo il 19/08/2026 (segnalato dall'utente dopo aver dovuto
        # chiedere lui stesso la correzione di un errore reale): il pre-fetch sopra copre SOLO i
        # fallimenti di uno script Scripts\Custom che chiama una cmdlet PowerShell nativa
        # riconoscibile per nome (Verbo-Nome). Una scrittura Graph diretta (propose_graph_write/
        # propose_intune_write - es. la sintassi di una regola di un Assignment Filter Intune) non
        # ha ne' un file sorgente ne' un nome di cmdlet PowerShell da estrarre con la regex sopra,
        # quindi restava SEMPRE senza alcuna documentazione: l'AI diagnosticava alla cieca e
        # correttamente si rifiutava di indovinare (comportamento corretto date le informazioni
        # disponibili - ma quelle informazioni erano sistematicamente incomplete per questa intera
        # classe di errori). Prova reale che ha innescato il fix: "Invalid assignment filter rule:
        # (device.osVersion -ge ...)" - un problema documentato e risolvibile (l'operatore -ge non
        # e' valido sulla proprieta' 'osVersion', serve la proprieta' 'operatingSystemVersion'),
        # mai cercato perche' nessun nome di cmdlet PowerShell compare nell'errore Graph.
        # Fix: una chiamata AI breve ed economica (max 60 token, Invoke-M365OpsAgent - non serve
        # tool-calling per un solo termine di ricerca) chiede PRIMA "cosa cercheresti su Microsoft
        # Learn per capire questo errore", poi Invoke-M365OpsLookupMsDocs usa quel termine - stessa
        # fonte di verita' di sempre (incluso il suo fallback di ricerca generica Microsoft Learn,
        # gia' esistente, mai raggiunto finora quando l'errore non nomina una cmdlet PowerShell).
        try {
            $searchTopic = (Invoke-M365OpsAgent -Provider $Provider -MaxTokens 60 -Prompt @"
Questa azione su Microsoft Graph/Intune/Exchange Online e' fallita con questo errore:
$ErrorMessage

Contesto: $Context

Rispondi SOLO con il termine di ricerca (poche parole, in inglese) da cercare su Microsoft Learn
per trovare la pagina di documentazione che spiega la sintassi/i valori corretti per risolvere
QUESTO errore specifico - nessun altro testo, nessuna spiegazione, nessuna virgolettatura.
"@).Trim()
            if ($searchTopic -and $searchTopic.Length -lt 200) {
                $docsSnippet = "`n`nDocumentazione Microsoft Learn REALE trovata per questo errore (usala come fonte di verita' per la sintassi corretta, non la tua conoscenza pregressa):`n--- $searchTopic ---`n$(Invoke-M365OpsLookupMsDocs -Topic $searchTopic)"
            }
        } catch { }
    }

    $prompt = @"
Un'azione in un modulo PowerShell che gestisce Intune/Microsoft Graph/Exchange Online e' fallita con questo errore:

$ErrorMessage

Contesto: $Context
$sourceSnippet
$kbSnippet
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
