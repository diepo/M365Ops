function Add-M365OpsChatHistoryTurn {
    <#
    .SYNOPSIS
        Aggiunge uno scambio (utente + risposta) allo storico conversazione locale del tenant e
        salva su disco, con un tetto sul numero di scambi conservati (gli ultimi $maxPairs).
    .NOTES
        Prima di salvare, redige eventuali password in chiaro presenti nel testo (es. corpo JSON di
        una scrittura utente proposta con passwordProfile) - principio "zero segreti su disco" gia'
        applicato a tenants.json, qui esteso ai segreti che possono comparire DENTRO una conversazione.

        Bug reale trovato dal vivo il 25/08/2026 (segnalato dall'utente: un'analisi lunga in chat
        appariva tagliata a meta' frase con "[...troncato]" - non nella risposta live appena
        ricevuta, ma dopo un ricaricamento della pagina): questa funzione troncava il testo a
        3000 caratteri PRIMA di salvarlo su disco - lo stesso file salvato viene pero' usato per
        DUE scopi diversi con esigenze opposte: (1) ridisegnare la chat per l'utente al
        caricamento pagina (GET /api/chat/history), dove va mostrato il testo COMPLETO, mai
        tagliato; (2) fornire contesto conversazionale all'IA nei turni successivi
        (Invoke-M365OpsAgentTools.ps1), dove un limite di lunghezza resta una scelta corretta per
        non gonfiare costo/tempo di risposta reinviando per intero un report lungo ad ogni
        chiamata. Il taglio a 3000 caratteri qui applicato ad ENTRAMBI gli scopi cancellava per
        sempre la parte finale del testo anche per la visualizzazione umana, l'unico caso dove
        non ha senso. Corretto separando i due scopi: qui si salva SEMPRE il testo completo (solo
        la redazione password resta), il limite di lunghezza per il contesto IA si applica ora
        SOLO al momento di costruire i messaggi per l'IA (vedi Invoke-M365OpsAgentTools.ps1,
        $maxHistoryCharsPerTurn), mai qui.
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$UserText,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$AssistantText,
        [object[]]$Attachments
    )

    if (-not $UserText -and -not $AssistantText) { return }

    $maxPairs = 8

    $redact = {
        param($s)
        if (-not $s) { return $s }
        $s = $s -replace '("password"\s*:\s*")[^"]*(")', '$1[REDACTED]$2'
        return $s
    }

    $history = @(Get-M365OpsChatHistory -TenantName $TenantName)
    $now = Get-Date -Format 'o'
    if ($UserText) { $history += [pscustomobject]@{ role = 'user'; text = (& $redact $UserText); timestamp = $now } }
    if ($AssistantText) {
        # Bug reale (18/08/2026): senza salvare gli allegati, un report generato in un turno
        # perdeva per sempre i pulsanti di download non appena la pagina veniva ricaricata (la
        # cronologia veniva ridisegnata solo con testo) - il file restava sul disco ma
        # diventava irraggiungibile dalla chat, l'utente doveva andare a cercarselo a mano.
        $entry = [pscustomobject]@{ role = 'assistant'; text = (& $redact $AssistantText); timestamp = $now }
        if ($Attachments -and $Attachments.Count -gt 0) { $entry | Add-Member -NotePropertyName 'attachments' -NotePropertyValue $Attachments }
        $history += $entry
    }

    $maxEntries = $maxPairs * 2
    if ($history.Count -gt $maxEntries) {
        $history = $history[($history.Count - $maxEntries)..($history.Count - 1)]
    }

    $safeName = $TenantName -replace '[^\w\-]', '_'
    $path = Join-Path $script:M365OpsModuleRoot "Config\ChatHistory-$safeName.json"
    try {
        # -InputObject, mai pipeIato: pipare un array con UN solo scambio lo "srotola" a un
        # singolo oggetto sulla pipeline, e ConvertTo-Json lo scrive su disco come oggetto nudo
        # invece che [...] - Get-M365OpsChatHistory lo ri-avvolgerebbe comunque in lettura (@()),
        # quindi non e' mai stato un crash, ma il file salvato aveva una forma incoerente
        # (stesso bug di fondo di GET /api/chat/history, corretto qui per coerenza il 16/08/2026).
        ConvertTo-Json -InputObject $history -Depth 4 | Set-Content -Path $path -Encoding utf8
    }
    catch {
        # Storico e' solo un miglioramento di comodita' - un fallimento di scrittura su disco
        # non deve mai interrompere la risposta gia' data all'utente.
    }
}
