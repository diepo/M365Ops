function Get-M365OpsConfigurationPolicyTemplates {
    <#
    .SYNOPSIS
        Elenca i template disponibili per creare una policy Endpoint Security o Security
        Baseline (Settings Catalog puro non ha template, usa New-M365OpsConfigurationPolicy
        senza -TemplateId) - usa questa funzione PRIMA di New-M365OpsConfigurationPolicy per
        trovare il templateId corretto, mai indovinato.
    .PARAMETER TemplateFamily
        Filtra per famiglia (LATO CLIENT, stesso principio di Get-M365OpsConfigurationPolicies):
        'endpointSecurityAntivirus', 'endpointSecurityDiskEncryption', 'endpointSecurityFirewall',
        'endpointSecurityEndpointDetectionAndResponse', 'endpointSecurityAttackSurfaceReduction',
        'endpointSecurityAccountProtection', 'endpointSecurityApplicationControl',
        'endpointSecurityEndpointPrivilegeManagement', 'baseline' (Security Baseline).
    #>
    param([string]$TemplateFamily)

    $templates = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/configurationPolicyTemplates" -Beta).value
    if ($TemplateFamily) { $templates = @($templates | Where-Object { $_.templateFamily -eq $TemplateFamily }) }
    # Solo l'ultima versione (lifecycleState 'active') di ciascun template per nome, a meno che
    # non venga chiesto un TemplateFamily specifico (dove vedere tutte le versioni puo' servire) -
    # altrimenti l'elenco completo e' dominato da versioni obsolete dello stesso template.
    if (-not $TemplateFamily) { $templates = @($templates | Where-Object { $_.lifecycleState -eq 'active' }) }
    $templates | Select-Object id, displayName, description, templateFamily, platforms, version, lifecycleState
}
