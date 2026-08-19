function Set-M365OpsConfigurationPolicy {
    <#
    .SYNOPSIS
        Modifica nome/descrizione/scope tag/impostazioni di una policy Settings
        Catalog/Endpoint Security/Baseline esistente.
    .PARAMETER Settings
        Se specificato, SOSTITUISCE l'intero elenco di impostazioni (l'API Graph non supporta una
        patch parziale della singola impostazione) - stessa struttura di New-M365OpsConfigurationPolicy,
        mai indovinata, cerca prima con Get-M365OpsConfigurationSettingDefinitions.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [string]$Name,
        [string]$Description,
        [string[]]$RoleScopeTagIds,
        [hashtable[]]$Settings
    )

    $body = @{}
    if ($Name) { $body.name = $Name }
    if ($null -ne $Description) { $body.description = $Description }
    if ($RoleScopeTagIds) { $body.roleScopeTagIds = $RoleScopeTagIds }
    if ($Settings) { $body.settings = $Settings }
    if ($body.Count -eq 0) { throw "Nessun campo da modificare specificato." }

    Invoke-M365OpsGraphRequest -Method PATCH -Path "/deviceManagement/configurationPolicies/$Identity" -Body $body -Beta | Out-Null
    Write-Host "Policy $Identity aggiornata." -ForegroundColor Green
    Get-M365OpsConfigurationPolicies -Identity $Identity
}
