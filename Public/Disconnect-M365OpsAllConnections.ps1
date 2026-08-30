function Disconnect-M365OpsAllConnections {
    <#
    .SYNOPSIS
        Interrompe TUTTE le connessioni attive per il TENANT ATTIVO, a prescindere da quale
        parte del progetto le abbia aperte: sessioni Exchange/Teams/SharePoint/Compliance
        (PowerShell remoting), Intune (token Graph separato, modulo IntuneWin32App), ogni
        sottoprocesso MCP di questo tenant (Lokka, CLI-Microsoft365, ecc.), la cache del token
        Graph (app-only o delegato) e un eventuale login a codice dispositivo lasciato a meta'.
        Richiesto esplicitamente dall'utente (27/08/2026) come pulsante "Disconnetti tutto" -
        pensato per una pulizia radicale prima di riconnettersi da zero (Connect-
        M365OpsAllConnections), non per l'uso quotidiano.
    .NOTES
        Non tocca lo stato di ALTRI tenant (stesso principio di isolamento per tenant gia'
        applicato ovunque nel progetto - vedi Connect-M365OpsMcpServer.ps1). Ogni passo e'
        indipendente e non bloccante: un servizio mai connesso o gia' disconnesso e' un no-op
        sicuro per costruzione in ciascuna delle funzioni Disconnect-M365Ops* richiamate qui,
        quindi non serve try/catch per passo (a differenza di Connect-M365OpsAllConnections,
        dove un tentativo puo' davvero fallire).
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo." }
    $tenantName = $script:M365OpsContext.Name

    Disconnect-M365OpsExchange
    Disconnect-M365OpsTeams
    Disconnect-M365OpsSharePoint
    Disconnect-M365OpsCompliance

    # IntuneWin32App non espone un vero "Disconnect" - stesso principio di reset diretto del
    # flag gia' usato in Connect-M365Ops.ps1 ad ogni cambio tenant.
    $script:M365OpsIntuneConnected = $false
    $script:M365OpsIntuneConnectedAs = $null

    Disconnect-M365OpsAllMcpServers -TenantName $tenantName

    # Bug reale trovato dalla maratona di stress-test (31/08/2026): questa chiamata mancava,
    # nonostante la docstring sopra dichiari "TUTTE le connessioni... a prescindere da quale
    # parte del progetto le abbia aperte" - Remove-M365OpsTenant.ps1 (stesso identico scopo di
    # pulizia radicale, ma per un profilo che viene rimosso) chiama gia' correttamente ENTRAMBE
    # Disconnect-M365OpsAllMcpServers e Disconnect-M365OpsAllIsolatedWorkers. Senza questa riga,
    # un worker isolato (attivato dal conflitto .NET di sezione 6.6, con una sessione Exchange
    # reale ancora autenticata al suo interno) restava vivo anche dopo "Disconnetti tutto" - la
    # GUI mostrava "Tutte le connessioni disattivate" ma qualunque cmdlet proxato eseguito dopo
    # avrebbe comunque colpito il tenant "supposto scollegato" in silenzio.
    Disconnect-M365OpsAllIsolatedWorkers -TenantName $tenantName

    if ($script:M365OpsTokenCache) { $script:M365OpsTokenCache.Remove($tenantName) }

    # Un login delegato a codice dispositivo iniziato ma mai completato (utente non ha ancora
    # inserito il codice sul browser) resta "pendente" finche' non scade da solo - lo scartiamo
    # esplicitamente qui, cosi' "Disconnetti tutto" e' davvero un reset completo e non lascia
    # un login a meta' che potrebbe confondere un tentativo successivo.
    if ($script:M365OpsPendingDeviceCode) { $script:M365OpsPendingDeviceCode.Remove($tenantName) }

    Write-Host "Tutte le connessioni disattivate per il tenant '$tenantName'." -ForegroundColor Yellow
}
