function Find-M365OpsAdminTemplateSetting {
    <#
    .SYNOPSIS
        Cerca le definizioni di impostazione Modelli amministrativi (Group Policy) disponibili
        per nome, per trovare il DefinitionId da passare a Set-M365OpsAdminTemplateSetting.
        Come per il Settings Catalog, l'universo delle impostazioni GP e' troppo vasto (decine
        di migliaia) per essere modellato con parametri dedicati per ognuna.
    #>
    param(
        [Parameter(Mandatory)] [string]$SearchText,
        [int]$Top = 25
    )
    $filter = "contains(displayName,'$($SearchText.Replace("'", "''"))')"
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/groupPolicyDefinitions?`$filter=$filter&`$top=$Top" -Beta).value |
        Select-Object id, displayName, classType, categoryPath, policyType, supportedOn
}
