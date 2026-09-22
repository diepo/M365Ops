function Invoke-M365OpsFoundryAgent {
    <#
    .SYNOPSIS
        Invia un prompt a un agent Microsoft Foundry (Responses API sul PROJECT endpoint) e
        restituisce il testo della risposta. Canale SEPARATO dalla chat principale (richiesto
        esplicitamente dall'utente, 22/09/2026: "canale separato, prompt semplice" - NON
        integrato con gli strumenti M365 - graph_api_call/exo_query/ecc. - di
        Invoke-M365OpsAgentTools.ps1, che restano solo su Claude/Azure OpenAI).
    .DESCRIPTION
        Endpoint = {AZURE_FOUNDRY_PROJECT_ENDPOINT}/openai/v1/responses - un "project endpoint"
        di Foundry, DIVERSO dall'endpoint della risorsa Azure OpenAI classica gia' usata altrove
        in questo modulo (verificato sulla documentazione ufficiale, non a memoria: si copia
        dalla schermata di benvenuto del progetto Foundry, forma tipica
        https://<risorsa>.services.ai.azure.com/api/projects/<progetto>). E' l'API "Responses",
        compatibile OpenAI ma con i modelli/tool del catalogo Foundry - "ephemeral agent": le
        istruzioni/il modello si passano ad ogni chiamata, nessun agent persistito da creare o
        gestire nel portale.
        Autenticazione SOLO Entra ID (mai una chiave API - vedi Get-M365OpsFoundryToken.ps1),
        con un ritentativo automatico su 401 (token appena scaduto/ruolo appena assegnato,
        capita nei primi minuti dopo un role assignment nuovo per la propagazione RBAC).
    .PARAMETER Prompt
        Testo della domanda/richiesta.
    .PARAMETER Instructions
        Istruzioni di sistema opzionali (persona/contesto dell'agent per questa chiamata).
        Default: AZURE_FOUNDRY_INSTRUCTIONS se configurata, altrimenti nessuna.
    .PARAMETER MaxOutputTokens
        Limite token di output (default 2000 - un ephemeral agent puo' includere ragionamento
        interno su modelli reasoning, un limite basso rischia una risposta troncata/vuota).
    .OUTPUTS
        pscustomobject { Text; InputTokens; OutputTokens; TotalTokens }.
    #>
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Instructions,
        [int]$MaxOutputTokens = 2000
    )

    $endpoint = Get-M365OpsSecret -Name 'AZURE_FOUNDRY_PROJECT_ENDPOINT'
    $model = Get-M365OpsSecret -Name 'AZURE_FOUNDRY_MODEL'
    if (-not $Instructions) { $Instructions = Get-M365OpsSecret -Name 'AZURE_FOUNDRY_INSTRUCTIONS' }
    if (-not ($endpoint -and $model)) {
        throw "Servono AZURE_FOUNDRY_PROJECT_ENDPOINT e AZURE_FOUNDRY_MODEL come variabili d'ambiente (tab Motore AI, sezione 'Agent Foundry') - il project endpoint si copia dalla schermata di benvenuto del progetto su ai.azure.com, NON e' lo stesso endpoint di Azure OpenAI usato sopra."
    }

    $uri = "$($endpoint.TrimEnd('/'))/openai/v1/responses"
    $bodyObj = [ordered]@{ model = $model; input = $Prompt; max_output_tokens = $MaxOutputTokens }
    if ($Instructions) { $bodyObj.instructions = $Instructions }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 8

    $callOnce = {
        param($token)
        $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
        # -TimeoutSec 120: stesso motivo di Invoke-M365OpsAgent.ps1/Invoke-M365OpsAgentTools.ps1 -
        # il server GUI e' un HttpListener sincrono a thread singolo, mai bloccarlo a tempo
        # indeterminato su una chiamata esterna.
        Invoke-WebRequest -Method POST -Uri $uri -Headers $headers -Body $bodyJson -TimeoutSec 120 -SkipHttpErrorCheck -ErrorAction Stop
    }

    $token = Get-M365OpsFoundryToken
    $resp = & $callOnce $token

    if ([int]$resp.StatusCode -eq 401) {
        # Stesso principio del ritentativo su chiave ruotata di Get-M365OpsAzureOpenAIKey: un
        # token appena scaduto o un ruolo RBAC appena assegnato (la propagazione puo' richiedere
        # qualche minuto) si risolvono da soli riprovando UNA volta con un token fresco.
        Write-M365OpsLog "Foundry Agent Service ha risposto 401 - rileggo il token (possibile scadenza/propagazione RBAC) e ritento una volta."
        $token = Get-M365OpsFoundryToken
        $resp = & $callOnce $token
    }

    $status = [int]$resp.StatusCode
    $parsedBody = $null
    try { $parsedBody = $resp.Content | ConvertFrom-Json -ErrorAction Stop } catch { }

    if ($status -eq 403) {
        throw "Microsoft Foundry Agent Service: accesso negato (403). L'identita' usata non ha il ruolo RBAC 'Foundry Agent Consumer' sul progetto Foundry - e' un permesso Azure separato dai permessi Graph/Exchange gia' concessi a questo modulo, va assegnato a parte (vedi la sezione 'Agent Foundry' della guida). Dettaglio: $($parsedBody.error.message)"
    }
    if ($status -eq 404) {
        throw "Microsoft Foundry Agent Service: risorsa non trovata (404) - controlla AZURE_FOUNDRY_PROJECT_ENDPOINT (deve essere il PROJECT endpoint, non l'endpoint della risorsa Azure OpenAI) e AZURE_FOUNDRY_MODEL (il nome del deployment/modello nel catalogo del progetto). Dettaglio: $($parsedBody.error.message)"
    }
    if ($status -ge 400) {
        throw "Microsoft Foundry Agent Service: richiesta fallita (HTTP $status). $($parsedBody.error.message)"
    }
    if (-not $parsedBody) {
        throw "Microsoft Foundry Agent Service: risposta HTTP $status non interpretabile come JSON."
    }

    $result = ConvertFrom-M365OpsFoundryResponse -Response $parsedBody
    if (-not $result.Text) {
        $reasonNote = if ($result.IncompleteReason) { " (motivo: $($result.IncompleteReason))" } else { '' }
        throw "Microsoft Foundry Agent Service: l'agent non ha prodotto testo (status: $($result.Status)$reasonNote) - prova ad alzare -MaxOutputTokens o a riformulare in modo piu' semplice."
    }
    Write-M365OpsAiUsageLog -Provider FoundryAgent -Model $model -InputTokens $result.InputTokens -OutputTokens $result.OutputTokens -CachedTokens 0
    $result
}
