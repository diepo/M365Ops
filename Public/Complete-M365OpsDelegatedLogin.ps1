function Complete-M365OpsDelegatedLogin {
    <#
    .SYNOPSIS
        UN singolo tentativo di verifica che l'utente abbia completato il login avviato
        con Start-M365OpsDelegatedLogin per il tenant ATTIVO - pensata per essere chiamata
        ripetutamente (polling) dalla GUI, non blocca in attesa. Su successo, la sessione
        delegata viene messa in cache SOLO per questo tenant (isolata dagli altri profili).
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    $pending = $script:M365OpsPendingDeviceCode[$tenantName]
    if (-not $pending) {
        return [pscustomobject]@{ Status = 'Error'; Message = "Nessun login in corso per '$tenantName' - avvialo prima con Start-M365OpsDelegatedLogin." }
    }
    if ((Get-Date) -gt $pending.ExpiresAt) {
        $script:M365OpsPendingDeviceCode.Remove($tenantName)
        return [pscustomobject]@{ Status = 'Error'; Message = "Codice scaduto - riavvia il login." }
    }

    $result = Receive-M365OpsDeviceCodeToken -TenantId $script:M365OpsContext.TenantId -DeviceCode $pending.DeviceCode

    if ($result.Status -eq 'Completed') {
        $script:M365OpsPendingDeviceCode.Remove($tenantName)
        if (-not $script:M365OpsTokenCache[$tenantName]) { $script:M365OpsTokenCache[$tenantName] = @{} }
        $script:M365OpsTokenCache[$tenantName].Delegated = @{
            AccessToken  = $result.AccessToken
            RefreshToken = $result.RefreshToken
            ExpiresAt    = $result.ExpiresAt
        }
        Write-Host "Login delegato completato per '$tenantName'." -ForegroundColor Green
    }
    elseif ($result.Status -eq 'Error') {
        $script:M365OpsPendingDeviceCode.Remove($tenantName)
    }

    $result
}
