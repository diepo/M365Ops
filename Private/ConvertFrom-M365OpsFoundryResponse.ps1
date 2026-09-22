function ConvertFrom-M365OpsFoundryResponse {
    <#
    .SYNOPSIS
        Estrae il testo e i token da una risposta gia' deserializzata della Responses API
        (POST {project_endpoint}/openai/v1/responses) - separata dalla chiamata HTTP apposta,
        cosi' si puo' verificare la logica di lettura su un JSON campione senza dover chiamare
        davvero Foundry (utile qui: nessun progetto Foundry raggiungibile da questo PC per un
        test dal vivo end-to-end, vedi Invoke-M365OpsFoundryAgent.ps1).
    .DESCRIPTION
        "output_text" (usato dagli SDK ufficiali) e' un comodo calcolato LATO CLIENT, non un
        campo del JSON grezzo (verificato il 22/09/2026, non a memoria) - qui si legge sempre
        l'array "output" a mano: un item di tipo "message" puo' avere piu' blocchi in "content",
        si concatena il testo di ogni blocco di tipo "output_text" (mai assumere che il testo
        stia sempre nel primo elemento, la stessa API puo' restituire anche item di tipo
        "reasoning"/"function_call" prima del messaggio vero).
    .OUTPUTS
        pscustomobject { Text; InputTokens; OutputTokens; TotalTokens; Status; IncompleteReason }.
    #>
    param([Parameter(Mandatory)] $Response)

    $textParts = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Response.output)) {
        if ($item.type -ne 'message') { continue }
        foreach ($block in @($item.content)) {
            if ($block.type -eq 'output_text' -and $block.text) { $textParts.Add($block.text) }
        }
    }

    [pscustomobject]@{
        Text             = ($textParts -join "`n")
        InputTokens      = [int]$Response.usage.input_tokens
        OutputTokens     = [int]$Response.usage.output_tokens
        TotalTokens      = [int]$Response.usage.total_tokens
        Status           = [string]$Response.status
        IncompleteReason = $Response.incomplete_details.reason
    }
}
