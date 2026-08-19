function Set-M365OpsAdminTemplateSetting {
    <#
    .SYNOPSIS
        Abilita o disabilita una singola impostazione Modelli amministrativi (Group Policy) su
        un profilo, tramite l'azione updateDefinitionValues. Usa Find-M365OpsAdminTemplateSetting
        per trovare il -DefinitionId. -PresentationValues accetta un array di hashtable gia' nel
        formato Graph (groupPolicyPresentationValue*) per le impostazioni con parametri: se
        omesso, l'impostazione viene semplicemente abilitata/disabilitata senza valori aggiuntivi.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$DefinitionId,
        [Parameter(Mandatory)] [bool]$Enabled,
        [hashtable[]]$PresentationValues
    )
    $definitionValue = @{
        "enabled"                      = $Enabled
        "definition@odata.bind"        = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$DefinitionId')"
    }
    $body = @{ added = @(@{ definitionValue = $definitionValue }); updated = @(); deleted = @() }
    if ($PresentationValues) { $body.added[0].definitionValue.presentationValues = $PresentationValues }

    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/groupPolicyConfigurations/$Identity/updateDefinitionValues" -Body $body -Beta | Out-Null
    $state = if ($Enabled) { "abilitata" } else { "disabilitata" }
    Write-Host "Profilo ${Identity}: impostazione $DefinitionId $state." -ForegroundColor Green
}
