function Get-M365OpsAzureOpenAIEndpointInfo {
    <#
    .SYNOPSIS
        Da QUALUNQUE forma di endpoint incollata dal portale Azure/Foundry ricava la RADICE della
        risorsa (a cui il modulo aggiunge sempre il percorso REST classico
        /openai/deployments/{deployment}/chat/completions) e, se presente, il nome del
        deployment scritto nell'URL (21/09/2026, bug reale segnalato dal vivo dall'utente: "Errore:
        Azure OpenAI ... 404 Resource not found").
    .DESCRIPTION
        Il portale mostra forme diverse a seconda di dove si copia:
          - classica:        https://risorsa.openai.azure.com/  (o .cognitiveservices.azure.com)
          - Project endpoint: https://risorsa.services.ai.azure.com/openai/v1
          - "Target URI" di un deployment Foundry (la piu' comoda da copiare, ed e' quella che ha
            rotto l'app): https://risorsa.cognitiveservices.azure.com/openai/deployments/model-router/chat/completions?api-version=2025-01-01-preview
        Prima si toglievano solo i suffissi "/openai/v1" e "/openai": incollando il Target URI
        completo il modulo costruiva un indirizzo con il percorso duplicato -> 404 su OGNI chiamata.
        Ora si taglia tutto da "/openai" in poi (e query/fragment) - un eventuale prefisso di
        percorso PRIMA di "/openai" (gateway APIM) viene conservato.
    .OUTPUTS
        pscustomobject { Root; Deployment ($null se l'URL non ne contiene uno); ApiVersion ($null se assente) }.
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Endpoint)

    $text = $Endpoint.Trim()
    $deployment = $null
    if ($text -match '/openai/deployments/(?<d>[^/?#]+)') { $deployment = [System.Uri]::UnescapeDataString($Matches['d']) }
    $apiVersion = $null
    if ($text -match '[?&]api-version=(?<v>[^&#]+)') { $apiVersion = $Matches['v'] }

    $withoutQuery = ($text -split '[?#]', 2)[0]
    $root = ($withoutQuery -replace '/openai(/.*)?$', '').TrimEnd('/')
    [pscustomobject]@{ Root = $root; Deployment = $deployment; ApiVersion = $apiVersion }
}
