function Get-M365OpsConfigurationSettingDefinitions {
    <#
    .SYNOPSIS
        Cerca nel catalogo Impostazioni di Intune (decine di migliaia di voci: Settings Catalog,
        Endpoint Security ed Enrollment condividono lo stesso catalogo) per trovare il
        settingDefinitionId esatto e i valori ammessi PRIMA di costruire una policy - mai
        indovinare un settingDefinitionId o un value, va sempre cercato qui prima.
    .PARAMETER Keyword
        Cercato nel nome/displayName/keyword del catalogo (filtro LATO CLIENT sul risultato
        completo, dato che l'endpoint non documenta un parametro $search server-side affidabile
        per questo caso d'uso - stesso principio gia' adottato per /managedDevices).
    .PARAMETER Platform
        Filtra per piattaforma (es. 'windows10', 'macOS', 'iOS', 'android') se specificata.
    .EXAMPLE
        Get-M365OpsConfigurationSettingDefinitions -Keyword "BitLocker" -Platform windows10
    #>
    param(
        [string]$Keyword,
        [string]$Platform
    )

    $definitions = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/configurationSettings" -Beta).value
    if ($Keyword) {
        $definitions = @($definitions | Where-Object {
            $_.displayName -like "*$Keyword*" -or $_.name -like "*$Keyword*" -or ($_.keywords -and ($_.keywords -join ' ') -like "*$Keyword*")
        })
    }
    if ($Platform) { $definitions = @($definitions | Where-Object { $_.applicability.platform -eq $Platform }) }
    $definitions | Select-Object id, displayName, description, @{n = 'platform'; e = { $_.applicability.platform } }, @{n = 'technologies'; e = { $_.applicability.technologies } }, uxBehavior, riskLevel
}
