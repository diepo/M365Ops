function Get-M365OpsChatHistory {
    <#
    .SYNOPSIS
        Legge lo storico conversazione salvato in locale per il tenant indicato (Config\ChatHistory-*.json).
        Usato da Server.ps1 per dare all'AI il contesto dei messaggi precedenti, invece di farle
        ripartire da zero ad ogni domanda (bug reale segnalato dall'utente: "risponde ma non si
        ricorda piu' di che parlavamo").
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $safeName = $TenantName -replace '[^\w\-]', '_'
    $path = Join-Path $script:M365OpsModuleRoot "Config\ChatHistory-$safeName.json"
    if (-not (Test-Path $path)) { return @() }

    try {
        $raw = Get-Content -Path $path -Raw -ErrorAction Stop
        if (-not $raw) { return @() }
        $parsed = @(ConvertFrom-Json -InputObject $raw -ErrorAction Stop)
        # Bug reale (18/08/2026): il file era sintatticamente JSON valido (quindi NON catturato
        # dal catch sotto) ma una voce aveva "role" nullo/non valido - passata cosi' com'e' fino
        # alla chiamata Azure, che ha rifiutato l'INTERA richiesta con 400 "expected one of
        # system/assistant/user/... but got null". Una sola voce corrotta bloccava ogni domanda
        # successiva nello stesso tenant, non solo quella che l'aveva causata. Ora le voci non
        # valide vengono scartate silenziosamente invece di propagarsi fino all'API.
        return @($parsed | Where-Object { $_.role -in @('user', 'assistant') -and $null -ne $_.text })
    }
    catch {
        # File corrotto/scritto a meta' da un crash - meglio ripartire senza storico che
        # bloccare la chat con un errore su un file di sola comodita'.
        return @()
    }
}
