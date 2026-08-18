function Test-M365OpsIntuneAuthValid {
    <#
    .SYNOPSIS
        Verifica DAL VIVO che $Global:AuthenticationHeader (impostato da Connect-MSIntuneGraph,
        modulo IntuneWin32App) sia davvero valido e appartenga al tenant attivo - non ci si
        fida del solo fatto che Connect-MSIntuneGraph non abbia sollevato un errore, ne' del
        nostro stesso flag $script:M365OpsIntuneConnected (bug reale osservato il 15/08/2026:
        una connessione ritenuta valida ha lasciato $Global:AuthenticationHeader vuoto/non
        valido, scoperto solo a meta' di New-M365OpsWin32App con un warning criptico del
        modulo invece che con un errore chiaro subito). Risponde anche alla domanda "sono
        sicuro che abbia usato l'utenza giusta?": chiama Graph con lo stesso header appena
        ottenuto e confronta il tenant id risolto con quello del profilo attivo.
    .OUTPUTS
        $true/$false. Su successo aggiorna anche $script:M365OpsIntuneConnectedAs
        (Upn/TenantId/TenantName) per mostrare in GUI chi/quale tenant ha risposto davvero.
    #>
    if (-not $Global:AuthenticationHeader) { return $false }
    try {
        $org = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains' -Headers $Global:AuthenticationHeader -ErrorAction Stop
        $resolvedTenantId = $org.value[0].id
        if (-not $resolvedTenantId) { return $false }

        # TenantId nel profilo puo' essere il GUID oppure un dominio (es.
        # "contoso.onmicrosoft.com" - vedi Config\tenants.json, campo popolato a mano
        # dall'utente in entrambi i formati) - /organization restituisce sempre il GUID,
        # quindi un confronto solo su quello avrebbe rifiutato SEMPRE una connessione valida
        # per qualunque profilo configurato con un dominio invece del GUID (bug reale
        # individuato in revisione, mai emerso nei test perche' Fabrikam-Prod usa gia' il GUID).
        $configuredTenantId = $script:M365OpsContext.TenantId
        $tenantMatches = $true
        if ($script:M365OpsContext -and $configuredTenantId) {
            if ($configuredTenantId -eq $resolvedTenantId) {
                $tenantMatches = $true
            } else {
                $verifiedDomainNames = @($org.value[0].verifiedDomains | ForEach-Object { $_.name })
                $tenantMatches = $configuredTenantId -in $verifiedDomainNames
            }
        }
        if (-not $tenantMatches) {
            Write-M365OpsLog "Connessione Intune rifiutata: il token risolve al tenant '$resolvedTenantId' ($($org.value[0].displayName)) ma il tenant attivo e' '$configuredTenantId' - probabile token/cache riusato da un'altra sessione." -Level Error
            return $false
        }

        $upn = $null
        try { $upn = (Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=userPrincipalName' -Headers $Global:AuthenticationHeader -ErrorAction Stop).userPrincipalName } catch { }

        $script:M365OpsIntuneConnectedAs = [pscustomobject]@{
            Upn        = $upn
            TenantId   = $resolvedTenantId
            TenantName = $org.value[0].displayName
        }
        return $true
    }
    catch {
        return $false
    }
}
