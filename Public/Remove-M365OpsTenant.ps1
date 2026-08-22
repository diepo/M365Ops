function Remove-M365OpsTenant {
    <#
    .SYNOPSIS
        Rimuove un profilo tenant da Config\tenants.json - SOLO la registrazione (Tenant ID,
        Client ID, riferimento al nome della variabile d'ambiente del secret). Non tocca mai
        i dati gia' accumulati per quel tenant (storico chat, Knowledge Base, report), che
        restano sul disco finche' non li rimuove esplicitamente l'utente da Config\/Uploads\/
        Reports\ - stessa filosofia "mai cancellare dati per un'azione che riguarda solo la
        configurazione" gia' seguita altrove in questo modulo.

        Blocca la rimozione del profilo ATTUALMENTE ATTIVO: va prima attivato un altro
        profilo. Impedisce di lasciare l'app in uno stato senza tenant attivo, che
        romperebbe silenziosamente ogni cmdlet/tool AI in corso di sessione.
    .NOTES
        Mode: Write
    #>
    param(
        [Parameter(Mandatory)] [string]$Name
    )

    if ($script:M365OpsContext -and $script:M365OpsContext.Name -eq $Name) {
        throw "'$Name' e' il tenant attualmente attivo - attiva un altro profilo prima di rimuoverlo."
    }

    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\tenants.json'
    if (-not (Test-Path $configPath)) { throw "Nessun profilo tenant configurato." }

    $raw = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($Name -notin $raw.PSObject.Properties.Name) { throw "Profilo '$Name' non trovato." }

    $config = @{}
    foreach ($prop in $raw.PSObject.Properties) {
        if ($prop.Name -eq $Name) { continue }
        $config[$prop.Name] = $prop.Value
    }

    $config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8

    # I processi MCP sono isolati per tenant e possono restare vivi in background anche per un
    # profilo NON attivo (visitato in precedenza in questa sessione, vedi
    # Connect-M365OpsMcpServer.ps1) - un profilo appena rimosso non deve lasciarne uno orfano.
    try { Disconnect-M365OpsAllMcpServers -TenantName $Name } catch {}

    Write-Host "Profilo '$Name' rimosso da $configPath. Dati gia' accumulati (storico chat, Knowledge Base, report) non toccati." -ForegroundColor Green
    [pscustomobject]@{ Name = $Name; Removed = $true }
}
