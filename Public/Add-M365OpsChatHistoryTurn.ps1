function Add-M365OpsChatHistoryTurn {
    <#
    .SYNOPSIS
        Aggiunge uno scambio (utente + risposta) allo storico conversazione locale del tenant e
        salva su disco, con un tetto su numero di scambi e lunghezza di ciascun messaggio - senza
        limite, un report/elenco dispositivi lungo finirebbe reinviato per intero ad ogni chiamata
        AI successiva, gonfiando costo e tempo di risposta ad ogni turno.
    .NOTES
        Prima di salvare, redige eventuali password in chiaro presenti nel testo (es. corpo JSON di
        una scrittura utente proposta con passwordProfile) - principio "zero segreti su disco" gia'
        applicato a tenants.json, qui esteso ai segreti che possono comparire DENTRO una conversazione.
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$UserText,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$AssistantText,
        [object[]]$Attachments
    )

    if (-not $UserText -and -not $AssistantText) { return }

    $maxCharsPerTurn = 3000
    $maxPairs = 8

    $redact = {
        param($s)
        if (-not $s) { return $s }
        $s = $s -replace '("password"\s*:\s*")[^"]*(")', '$1[REDACTED]$2'
        if ($s.Length -gt $maxCharsPerTurn) { $s = $s.Substring(0, $maxCharsPerTurn) + " [...troncato]" }
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
