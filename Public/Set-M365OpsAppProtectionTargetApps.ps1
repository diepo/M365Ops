function Set-M365OpsAppProtectionTargetApps {
    <#
    .SYNOPSIS
        Indica a quali app si applica un criterio di protezione app MAM - AGGIUNGE alla lista
        esistente (collezione OData "apps", metodo Create documentato). Identificatori: package
        id per Android (es. com.microsoft.office.outlook), bundle id per iOS (es.
        com.microsoft.Office.Outlook) - schema mobileAppIdentifier verificato dal vivo su
        Microsoft Learn il 19/08/2026.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Android', 'iOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$AppIdentifiers
    )
    $base = if ($Platform -eq 'Android') { "/deviceAppManagement/androidManagedAppProtections" } else { "/deviceAppManagement/iosManagedAppProtections" }
    $odataType = if ($Platform -eq 'Android') { "microsoft.graph.androidMobileAppIdentifier" } else { "microsoft.graph.iosMobileAppIdentifier" }
    $idProperty = if ($Platform -eq 'Android') { "packageId" } else { "bundleId" }

    foreach ($appId in $AppIdentifiers) {
        $body = @{
            mobileAppIdentifier = @{ "@odata.type" = $odataType; $idProperty = $appId }
        }
        Invoke-M365OpsGraphRequest -Method POST -Path "$base/$Identity/apps" -Body $body | Out-Null
    }
    Write-Host "Criterio $Identity ($Platform): aggiunte $($AppIdentifiers.Count) app di destinazione." -ForegroundColor Green
}
