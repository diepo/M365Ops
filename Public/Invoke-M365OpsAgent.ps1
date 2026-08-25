function Invoke-M365OpsAgent {
    <#
    .SYNOPSIS
        Motore AI pluggable: manda un prompt + dati grezzi a un provider LLM e restituisce
        il ragionamento. Questa e' la funzione che tiene la logica di dominio FUORI dal codice
        — nessuna regex, nessuna soglia fissa: il modello ragiona sui dati ogni volta.

    .PARAMETER Provider
        'Claude' (default, Anthropic Messages API) oppure 'AzureOpenAI'.
        Non esiste un provider 'Copilot': M365 Copilot non espone un'API generica richiamabile
        da codice per questo scopo. Il pezzo realmente equivalente e intercambiabile e' Azure OpenAI
        (spesso il motore sotto al brand Copilot) — usa quel provider se ti serve restare
        nell'ecosistema Microsoft/Azure.

    .PARAMETER ReturnUsage
        Se presente, restituisce un pscustomobject { Text; InputTokens; OutputTokens;
        CachedTokens } invece della sola stringa di testo (25/08/2026, richiesto esplicitamente
        dall'utente per mostrare quanti token sono stati spesi in una specifica interazione IA -
        l'analizzatore intestazioni per primo). Il conteggio arriva GRATIS nella stessa risposta
        HTTP gia' attesa per il testo (campo "usage" di entrambe le API, Claude e Azure OpenAI) -
        nessuna chiamata aggiuntiva, nessun costo di latenza in piu' (verificato leggendo la
        struttura della risposta prima di implementare, non assunto). Default $false per NON
        toccare il contratto esistente delle altre ~5 funzioni che chiamano gia' questa e si
        aspettano una stringa semplice (Invoke-M365OpsErrorTriage, Invoke-M365OpsActionRecovery,
        Get-M365OpsCompliancePatterns, ecc.) - estendere quelle a un uso piu' ampio di questo
        parametro resta un lavoro futuro separato, non fatto qui per non rischiare di romperle.
    .EXAMPLE
        Invoke-M365OpsAgent -Prompt "Raggruppa questi dispositivi non conformi per causa comune" -Context $devicesJson
    #>
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Context,
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude',
        [int]$MaxTokens = 2000,
        [switch]$ReturnUsage
    )

    $fullPrompt = if ($Context) { "$Prompt`n`n--- DATI (JSON grezzo) ---`n$Context" } else { $Prompt }

    switch ($Provider) {
        'Claude' {
            $apiKey = Get-M365OpsSecret -Name 'ANTHROPIC_API_KEY'
            if (-not $apiKey) { throw "Variabile d'ambiente ANTHROPIC_API_KEY non trovata. Serve una API key da console.anthropic.com." }

            $body = @{
                model      = "claude-sonnet-4-5"
                max_tokens = $MaxTokens
                messages   = @(@{ role = "user"; content = $fullPrompt })
            } | ConvertTo-Json -Depth 8

            # -TimeoutSec 120 (25/08/2026, bug reale trovato da un agente di regression-review
            # della maratona): il server GUI accetta le richieste HTTP con un unico
            # HttpListener sincrono a thread singolo (Gui/Server.ps1) - senza un limite qui,
            # una chiamata IA rimasta bloccata a monte (rete lenta, provider in difficolta')
            # blocca l'INTERO server per chiunque altro, non solo per questa richiesta.
            # Riprodotto dal vivo: una chiamata a /api/analyze-headers-ai e' rimasta appesa
            # oltre 3 minuti (senza questo limite avrebbe potuto restare cosi' a tempo
            # indeterminato, dato che Invoke-RestMethod senza -TimeoutSec non ne applica
            # nessuno di suo) rendendo il server irraggiungibile per ogni altra richiesta nel
            # frattempo. 120s e' abbondante per una singola chiamata completions anche su un
            # modello reasoning con contesto ampio (i round multipli del tool-calling in
            # Invoke-M365OpsAgentTools.ps1 hanno ciascuno il proprio budget separato, non
            # condiviso) - un timeout qui finisce nello stesso try/catch gia' esistente
            # (Gui/Server.ps1, fallback su Invoke-M365OpsAgent poi messaggio d'errore pulito),
            # nessuna gestione nuova necessaria.
            $response = Invoke-RestMethod -Method POST -Uri "https://api.anthropic.com/v1/messages" -TimeoutSec 120 -Headers @{
                "x-api-key"         = $apiKey
                "anthropic-version" = "2023-06-01"
                "Content-Type"      = "application/json"
            } -Body $body
            $script:M365OpsAiCallCount.Claude++

            $claudeText = $response.content[0].text
            if (-not $claudeText) {
                # Stesso controllo aggiunto a Invoke-M365OpsAgentTools il 17/08/2026, mai
                # applicato qui: un contenuto vuoto arrivava fino al chiamante senza spiegazione.
                Write-M365OpsLog "Claude (Invoke-M365OpsAgent): risposta vuota (stop_reason=$($response.stop_reason))" -Level Error
                $claudeText = "Il modello non ha prodotto una risposta (motivo interno: $($response.stop_reason)) - prova a riformulare in modo piu' semplice."
            }
            if ($ReturnUsage) {
                return [pscustomobject]@{
                    Text         = $claudeText
                    InputTokens  = $response.usage.input_tokens
                    OutputTokens = $response.usage.output_tokens
                    CachedTokens = $response.usage.cache_read_input_tokens
                }
            }
            return $claudeText
        }
        'AzureOpenAI' {
            $apiKey = Get-M365OpsSecret -Name 'AZURE_OPENAI_KEY'
            $endpoint = Get-M365OpsSecret -Name 'AZURE_OPENAI_ENDPOINT'
            $deployment = Get-M365OpsSecret -Name 'AZURE_OPENAI_DEPLOYMENT'
            if (-not ($apiKey -and $endpoint -and $deployment)) {
                throw "Servono AZURE_OPENAI_KEY, AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_DEPLOYMENT come variabili d'ambiente."
            }

            # Normalizzazione dell'endpoint: il portale Azure mostra DUE forme diverse a
            # seconda di dove lo copi - quella "classica" della risorsa Azure OpenAI
            # ("https://risorsa.openai.azure.com/", a volte con lo slash finale) e quella piu'
            # recente "Project endpoint" di Azure AI Foundry ("https://risorsa.services.ai.
            # azure.com/openai/v1"). Il percorso REST classico che questa funzione costruisce
            # sotto (/openai/deployments/{deployment}/chat/completions) va sempre applicato
            # alla RADICE della risorsa - senza normalizzare, incollare la seconda forma
            # produrrebbe un URL con "/openai/" ripetuto due volte (bug reale riscontrato).
            $endpointRoot = $endpoint.TrimEnd('/') -replace '/openai/v1$', '' -replace '/openai$', ''
            $uri = "$endpointRoot/openai/deployments/$deployment/chat/completions?api-version=2024-06-01"
            $headers = @{ "api-key" = $apiKey; "Content-Type" = "application/json" }

            # I modelli piu' recenti (serie reasoning: o1/o3/o4 e famiglia gpt-5.x) rifiutano
            # il parametro "max_tokens" con un 400 e vogliono "max_completion_tokens" al suo
            # posto - non e' deducibile in anticipo dal solo nome del deployment (bug reale
            # riscontrato con gpt-5.4-mini). Si prova prima con max_tokens (compatibile con la
            # maggior parte dei modelli piu' vecchi) e, solo su quell'errore specifico, si
            # riprova UNA volta con max_completion_tokens invece di fallire e basta.
            $bodyObj = @{ messages = @(@{ role = "user"; content = $fullPrompt }); max_tokens = $MaxTokens }
            # -TimeoutSec 120: vedi il commento esteso sulla chiamata Claude sopra - stesso
            # motivo (server GUI a thread singolo, mai bloccarlo a tempo indeterminato).
            try {
                $response = Invoke-RestMethod -Method POST -Uri $uri -TimeoutSec 120 -Headers $headers -Body ($bodyObj | ConvertTo-Json -Depth 8) -ErrorAction Stop
            }
            catch {
                $detail = $_.ErrorDetails.Message
                if ($detail -match 'max_tokens' -and $detail -match 'max_completion_tokens') {
                    $bodyObj.Remove('max_tokens')
                    $bodyObj.max_completion_tokens = $MaxTokens
                    try {
                        $response = Invoke-RestMethod -Method POST -Uri $uri -TimeoutSec 120 -Headers $headers -Body ($bodyObj | ConvertTo-Json -Depth 8) -ErrorAction Stop
                    }
                    catch {
                        throw "Azure OpenAI: richiesta fallita anche con max_completion_tokens: $($_.Exception.Message)`n$($_.ErrorDetails.Message)"
                    }
                } else {
                    throw "Azure OpenAI: richiesta fallita: $($_.Exception.Message)`n$detail"
                }
            }
            $script:M365OpsAiCallCount.AzureOpenAI++

            $azureText = $response.choices[0].message.content
            if (-not $azureText) {
                # Stesso controllo aggiunto a Invoke-M365OpsAgentTools il 17/08/2026, mai
                # applicato qui: su un modello reasoning (gpt-5.x) un contenuto vuoto (budget di
                # ragionamento esaurito prima di produrre output) arrivava fino al chiamante -
                # qui e' particolarmente subdolo perche' questa funzione e' anche il fallback
                # silenzioso di Server.ps1 quando Invoke-M365OpsAgentTools fallisce (vedi sotto):
                # un doppio fallimento produceva un messaggio bianco in chat senza ALCUNA riga
                # nel log a spiegare perche' (bug reale scoperto il 17/08/2026 investigando
                # esattamente questo sintomo).
                Write-M365OpsLog "Azure OpenAI (Invoke-M365OpsAgent): risposta vuota (finish_reason=$($response.choices[0].finish_reason), completion_tokens=$($response.usage.completion_tokens), reasoning_tokens=$($response.usage.completion_tokens_details.reasoning_tokens))" -Level Error
                $azureText = "Il modello non ha prodotto una risposta (motivo interno: $($response.choices[0].finish_reason)) - prova a riformulare in modo piu' semplice."
            }
            if ($ReturnUsage) {
                return [pscustomobject]@{
                    Text         = $azureText
                    InputTokens  = $response.usage.prompt_tokens
                    OutputTokens = $response.usage.completion_tokens
                    CachedTokens = $response.usage.prompt_tokens_details.cached_tokens
                }
            }
            return $azureText
        }
    }
}
