function Test-M365OpsCliMicrosoft365UpdateCheckDue {
    <#
    .SYNOPSIS
        Restituisce $true se e' passato almeno un giorno dall'ultimo controllo aggiornamento
        CLI Microsoft 365 (o se non ne e' mai stato fatto uno) - throttle per
        Assert-M365OpsCliMicrosoft365Installed.ps1 (16/09/2026), cosi' il controllo (una vera
        chiamata di rete, npm view) non rallenta OGNI singola connessione al server MCP
        CLI-Microsoft365, solo la prima di ogni giorno. Il timestamp e' salvato in
        Config\cli-m365-last-update-check.txt (stesso pattern di Config\last-active-tenant.txt) -
        globale per il PC, non per tenant: e' la stessa installazione npm globale per qualunque
        tenant attivo.
    #>
    $path = Join-Path $script:M365OpsModuleRoot 'Config\cli-m365-last-update-check.txt'
    if (-not (Test-Path $path)) { return $true }
    try {
        $raw = (Get-Content -Path $path -Raw -ErrorAction Stop).Trim()
        $lastChecked = [datetime]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture)
        return ((Get-Date) - $lastChecked) -gt (New-TimeSpan -Days 1)
    } catch {
        # File assente/corrotto/illeggibile: meglio ricontrollare (costo minimo, una volta) che
        # restare bloccati per sempre a non controllare mai piu'.
        return $true
    }
}
