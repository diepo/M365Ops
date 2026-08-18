function Connect-M365Ops {
    <#
    .SYNOPSIS
        Attiva un profilo tenant salvato con Set-M365OpsTenant. Tutte le altre cmdlet del
        modulo operano sul tenant attivo finche' non richiami Connect-M365Ops con un altro nome.

    .EXAMPLE
        Connect-M365Ops -TenantProfile "contoso-test"
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantProfile
    )

    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\tenants.json'
    if (-not (Test-Path $configPath)) {
        throw "Nessun profilo salvato. Usa prima Set-M365OpsTenant."
    }

    $raw = Get-Content $configPath -Raw | ConvertFrom-Json
    $entry = $raw.$TenantProfile
    if (-not $entry) {
        $available = ($raw.PSObject.Properties.Name -join ', ')
        throw "Profilo '$TenantProfile' non trovato. Profili disponibili: $available"
    }

    # Lokka (sottoprocesso) e la sessione Exchange Online (remoting implicito) sono stato
    # GLOBALE, non parametrizzato per singola chiamata: se non li chiudessimo qui, un comando
    # eseguito dopo il cambio tenant rischierebbe di colpire ancora il tenant precedente.
    # Vanno chiusi esplicitamente ad ogni cambio profilo, mai lasciati sopravvivere.
    Disconnect-M365OpsLokka
    Disconnect-M365OpsExchange
    # IntuneWin32App non espone un vero "Disconnect" (nessuna sessione da chiudere come
    # Exchange) - resettiamo solo il nostro flag, cosi' Connect-M365OpsIntune richiede di
    # nuovo un connect esplicito (via -AllowInteractive) dopo un cambio tenant, invece di
    # riusare per sbaglio una connessione/cache del profilo precedente.
    $script:M365OpsIntuneConnected = $false
    $script:M365OpsIntuneConnectedAs = $null

    $script:M365OpsContext = @{
        Name                   = $TenantProfile
        TenantId               = $entry.TenantId
        ClientId               = $entry.ClientId
        SecretEnvVar           = $entry.SecretEnvVar
        ExchangeCertThumbprint = $entry.ExchangeCertThumbprint
        EmailSender            = $entry.EmailSender
        AuthMode               = if ($entry.AuthMode) { $entry.AuthMode } else { 'AppOnly' }
        DelegatedUpn           = $entry.DelegatedUpn
        SharePointInteractiveClientId = $entry.SharePointInteractiveClientId
    }
    $script:M365OpsTokenCache.Remove($TenantProfile)

    # Ultimo tenant attivo salvato su file (best-effort, non deve mai bloccare il cambio
    # tenant se il file non e' scrivibile) - usato da Launch-M365Ops.ps1 per far ripartire
    # il server sull'ultimo profilo usato invece che sempre sul default, quando lo si avvia
    # da zero (es. dopo aver chiuso tutto e ricliccato l'icona).
    try {
        $lastTenantFile = Join-Path $script:M365OpsModuleRoot 'Config\last-active-tenant.txt'
        Set-Content -Path $lastTenantFile -Value $TenantProfile -Encoding UTF8 -NoNewline
    } catch {}

    Write-Host "Tenant attivo: $TenantProfile ($($entry.TenantId)) [$($script:M365OpsContext.AuthMode)]" -ForegroundColor Green
}
