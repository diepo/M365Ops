function New-M365OpsConfigurationPolicy {
    <#
    .SYNOPSIS
        Crea una policy Settings Catalog (o Endpoint Security/Security Baseline, se -TemplateId e'
        specificato - stesso motore, vedi Get-M365OpsConfigurationPolicies) - schema Graph
        (deviceManagementConfigurationPolicy) verificato dal vivo su Microsoft Learn il
        19/08/2026 prima di scrivere questa funzione. NON assegnata: usa
        Set-M365OpsConfigurationPolicyAssignment per attivarla.
    .PARAMETER TemplateId
        Facoltativo - id di un template Endpoint Security/Baseline da
        Get-M365OpsConfigurationPolicyTemplates. Omesso = Settings Catalog puro (templateFamily
        'none'). MAI indovinato: va sempre cercato prima con Get-M365OpsConfigurationPolicyTemplates.
    .PARAMETER Settings
        Array di hashtable, ciascuna con la struttura JSON REALE di un
        deviceManagementConfigurationSetting.settingInstance (vedi la documentazione Graph per
        deviceManagementConfigurationChoiceSettingInstance/SimpleSettingInstance) - questo modulo
        non tenta di offrire parametri dedicati per ciascuna delle decine di migliaia di
        impostazioni possibili nel catalogo Intune: usa PRIMA
        Get-M365OpsConfigurationSettingDefinitions per trovare il settingDefinitionId e i valori
        ammessi esatti, mai indovinati. NON omettere in pratica: verificato dal vivo il 23/08/2026
        contro un tenant reale che Graph rifiuta con 400 "dCV2Policy.Settings : The Settings field
        is required." sia senza -TemplateId sia CON -TemplateId (provato con un template Endpoint
        Security Antivirus reale, "Defender Update controls") - il commento precedente che
        prometteva un contenitore vuoto valido, coi default forniti dal template, era sbagliato:
        nessun caso osservato accetta un array Settings vuoto/omesso. Passa sempre almeno una
        voce reale (anche per una policy basata su template).
    .EXAMPLE
        New-M365OpsConfigurationPolicy -Name "Baseline BitLocker" -Platforms windows10 -Technologies mdm `
            -Settings @(@{ "@odata.type"="#microsoft.graph.deviceManagementConfigurationSetting"; settingInstance=@{ "@odata.type"="#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"; settingDefinitionId="..."; choiceSettingValue=@{ "@odata.type"="#microsoft.graph.deviceManagementConfigurationChoiceSettingValue"; value="..." } } })
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$Description = "",
        [Parameter(Mandatory)] [string]$Platforms,
        [Parameter(Mandatory)] [string]$Technologies,
        [string]$TemplateId,
        [string[]]$RoleScopeTagIds,
        [hashtable[]]$Settings
    )

    $body = @{
        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationPolicy"
        name          = $Name
        description   = $Description
        platforms     = $Platforms
        technologies  = $Technologies
    }
    if ($TemplateId) { $body.templateReference = @{ "@odata.type" = "microsoft.graph.deviceManagementConfigurationPolicyTemplateReference"; templateId = $TemplateId } }
    if ($RoleScopeTagIds) { $body.roleScopeTagIds = $RoleScopeTagIds }
    if ($Settings) { $body.settings = $Settings }

    $policy = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/configurationPolicies" -Body $body -Beta
    Write-Host "Creata, NON assegnata: $($policy.name) ($($policy.id))" -ForegroundColor Green
    $policy
}
