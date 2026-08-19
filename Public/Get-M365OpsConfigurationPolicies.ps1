function Get-M365OpsConfigurationPolicies {
    <#
    .SYNOPSIS
        Elenca/legge le policy Settings Catalog di Intune - stesso motore usato anche per le
        policy Endpoint Security (Antivirus, Disk Encryption, Firewall, EDR, Attack Surface
        Reduction, Account Protection, Application Control, Endpoint Privilege Management) e le
        Security Baseline: si distinguono solo per il campo templateReference.templateFamily
        (19/08/2026, schema verificato dal vivo su Microsoft Learn prima di scrivere questa
        funzione - deviceManagementConfigurationPolicy, non a memoria). 'none' = Settings Catalog
        puro, senza template.
    .PARAMETER Identity
        Id di UNA policy - restituisce anche le impostazioni complete (Settings). Omesso =
        elenco di tutte le policy (senza dettaglio impostazioni, per non appesantire la risposta).
    .PARAMETER TemplateFamily
        Filtra per famiglia di template (es. 'endpointSecurityAntivirus', 'baseline', 'none' per
        il solo Settings Catalog puro) - filtro applicato LATO CLIENT, non via $filter server-side
        (stesso principio giа adottato per /managedDevices: piu' affidabile).
    .EXAMPLE
        Get-M365OpsConfigurationPolicies
        Get-M365OpsConfigurationPolicies -TemplateFamily endpointSecurityAntivirus
        Get-M365OpsConfigurationPolicies -Identity <id>
    #>
    param(
        [string]$Identity,
        [string]$TemplateFamily
    )

    if ($Identity) {
        $policy = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/configurationPolicies/$Identity" -Beta
        $settings = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/configurationPolicies/$Identity/settings" -Beta).value
        $policy | Add-Member -NotePropertyName Settings -NotePropertyValue $settings -Force
        return $policy
    }

    $policies = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/configurationPolicies" -Beta).value
    if ($TemplateFamily) { $policies = @($policies | Where-Object { $_.templateReference.templateFamily -eq $TemplateFamily }) }
    $policies
}
