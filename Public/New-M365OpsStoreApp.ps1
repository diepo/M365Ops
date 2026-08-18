function New-M365OpsStoreApp {
    <#
    .SYNOPSIS
        Crea un'app Store (winGetApp, endpoint beta) da un package identifier gia' pubblicato
        su Microsoft Store — es. Company Portal (9WZDNCRFJ3PZ). NON assegnata.
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$PackageIdentifier,
        [string]$Publisher = "Microsoft Corporation",
        [string]$Description = ""
    )

    $body = @{
        "@odata.type"     = "#microsoft.graph.winGetApp"
        displayName       = $DisplayName
        description       = $Description
        publisher         = $Publisher
        packageIdentifier = $PackageIdentifier
        installExperience = @{ runAsAccount = "system" }
    }

    $result = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceAppManagement/mobileApps" -Body $body -Beta
    Write-Host "Creata, NON assegnata: $($result.displayName) ($($result.id))" -ForegroundColor Green
    $result
}
