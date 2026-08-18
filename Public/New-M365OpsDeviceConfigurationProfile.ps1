function New-M365OpsDeviceConfigurationProfile {
    <#
    .SYNOPSIS
        Crea un profilo di configurazione dispositivo Intune. NON assegnato: usa
        Set-M365OpsAppAssignment (o un'assegnazione manuale nel portale) per attivarlo.

    .EXAMPLE
        # Esempio equivalente al profilo BitLocker creato oggi
        $settings = @{
            bitLockerEncryptDevice = $true
            bitLockerSystemDrivePolicy = @{
                encryptionMethod = "xtsAes256"
                startupAuthenticationRequired = $true
                startupAuthenticationTpmUsage = "allowed"
            }
        }
        New-M365OpsDeviceConfigurationProfile -OdataType "windows10EndpointProtectionConfiguration" -DisplayName "Encryption-Baseline" -Description "..." -Settings $settings
    #>
    param(
        [Parameter(Mandatory)] [string]$OdataType,
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [Parameter(Mandatory)] [hashtable]$Settings
    )

    $body = @{
        "@odata.type" = "#microsoft.graph.$OdataType"
        displayName   = $DisplayName
        description   = $Description
    }
    foreach ($key in $Settings.Keys) { $body[$key] = $Settings[$key] }

    $result = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceConfigurations" -Body $body
    Write-Host "Creato, NON assegnato: $($result.displayName) ($($result.id))" -ForegroundColor Green
    $result
}
