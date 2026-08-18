function Get-M365OpsManagedDevices {
    <#
    .SYNOPSIS
        Elenca i dispositivi gestiti da Intune sul tenant attivo. Dati grezzi, nessun
        raggruppamento o interpretazione: quella e' compito di Get-M365OpsCompliancePatterns.
    #>
    param(
        [switch]$NonCompliantOnly,
        [int]$Top = 100
    )

    # Bug reale confermato dal vivo il 18/08/2026: il filtro server-side OData
    # "$filter=complianceState ne 'compliant'" su /deviceManagement/managedDevices restituisce
    # l'INSIEME OPPOSTO di quello richiesto (su un tenant con 5 dispositivi noncompliant e 2
    # compliant, il filtro ha restituito i 2 compliant, non i 5 noncompliant) - quirk noto
    # dell'endpoint Graph su questo campo, non un errore di sintassi del filtro. Non ci si puo'
    # fidare del filtro server-side per questo campo: si recuperano sempre TUTTI i dispositivi e
    # si filtra lato client, cosi' il risultato e' garantito corretto a prescindere da come Graph
    # evolve il comportamento del suo $filter.
    $select = "id,deviceName,userPrincipalName,model,manufacturer,operatingSystem,osVersion,complianceState,lastSyncDateTime,isEncrypted"
    $path = "/deviceManagement/managedDevices?`$select=$select&`$top=$Top"

    $devices = (Invoke-M365OpsGraphRequest -Method GET -Path $path).value
    if ($NonCompliantOnly) { $devices = @($devices | Where-Object { $_.complianceState -ne 'compliant' }) }
    $devices
}
